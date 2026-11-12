/**
 * Background jobs. Every purge re-checks that its target is really deleted
 * before touching anything, and works one channel at a time, so a bug or a
 * replayed job can never remove live data.
 */
import { and, eq, inArray, isNotNull, isNull, lt, or, sql } from "drizzle-orm";
import type { Services } from "./context.js";
import { attachments, botInstallations, channels, invites, messages, roles, sessions, workspaceMembers, workspaces } from "./db/schema.js";
import { enqueue, type JobRunner } from "./infra/jobs.js";
import { deliverToBot, queueBotEvent } from "./modules/bots/service.js";
import { serializeMessages } from "./modules/messages/service.js";
import { fanOutMessage } from "./modules/notifications/fanout.js";

const PURGE_BATCH = 500;
const BATCHES_PER_RUN = 20;
const PENDING_UPLOAD_HOURS = 24;
const SESSION_RETENTION_DAYS = 30;
const HOUR = 3_600_000;

/** Periodic jobs: at most one waiting per hour slot, however many instances start. */
export async function schedulePeriodic(services: Services, type: string, everyMs = HOUR): Promise<void> {
	const slot = Math.floor(Date.now() / everyMs) + 1;
	await enqueue(services.db, type, {}, { dedupeKey: `periodic:${type}:${slot}`, delaySeconds: Math.max(0, (slot * everyMs - Date.now()) / 1000) });
}

async function deleteObjects(services: Services, ids: bigint[]) {
	if (ids.length === 0) return;
	const rows = await services.db.select().from(attachments).where(and(inArray(attachments.id, ids), eq(attachments.status, "deleted")));
	for (const row of rows) await services.storage?.delete(row.storageKey);
	await services.db.delete(attachments).where(and(inArray(attachments.id, rows.map((r) => r.id)), eq(attachments.status, "deleted")));
}

/** Deletes a deleted channel's messages and files in batches; re-queues itself until done. */
async function purgeChannel(services: Services, channelId: bigint) {
	const db = services.db;
	const [channel] = await db.select().from(channels).where(eq(channels.id, channelId));
	if (!channel || !channel.deletedAt) return; // never purge a live channel

	for (let batch = 0; batch < BATCHES_PER_RUN; batch++) {
		const ids = (
			await db.select({ id: messages.id }).from(messages).where(eq(messages.channelId, channelId)).limit(PURGE_BATCH)
		).map((m) => m.id);
		if (ids.length === 0) {
			const files = await db
				.update(attachments)
				.set({ status: "deleted" })
				.where(eq(attachments.channelId, channelId))
				.returning({ id: attachments.id });
			await deleteObjects(services, files.map((f) => f.id));
			await db.execute(sql`delete from read_states where channel_id = ${channelId}`);
			await db.execute(sql`delete from channel_members where channel_id = ${channelId}`);
			await db.execute(sql`delete from permission_overwrites where channel_id = ${channelId}`);
			await db.execute(sql`delete from channel_user_settings where channel_id = ${channelId}`);
			await db.execute(sql`delete from pins where channel_id = ${channelId}`);
			return;
		}
		const files = await db
			.update(attachments)
			.set({ status: "deleted" })
			.where(and(inArray(attachments.messageId, ids), eq(attachments.channelId, channelId)))
			.returning({ id: attachments.id });
		await deleteObjects(services, files.map((f) => f.id));
		// Reactions, pins and notifications go with their message (cascade)
		await db.delete(messages).where(and(inArray(messages.id, ids), eq(messages.channelId, channelId)));
	}
	await enqueue(db, "channel.purge", { channelId });
}

async function purgeWorkspace(services: Services, workspaceId: bigint) {
	const db = services.db;
	const [workspace] = await db.select().from(workspaces).where(eq(workspaces.id, workspaceId));
	if (!workspace || !workspace.deletedAt) return;
	await db.transaction(async (tx) => {
		const live = await tx
			.update(channels)
			.set({ deletedAt: new Date() })
			.where(and(eq(channels.workspaceId, workspaceId), isNull(channels.deletedAt)))
			.returning({ id: channels.id });
		const all = await tx.select({ id: channels.id }).from(channels).where(eq(channels.workspaceId, workspaceId));
		for (const { id } of all) await enqueue(tx, "channel.purge", { channelId: id });
		await tx.delete(invites).where(eq(invites.workspaceId, workspaceId));
		await tx.delete(botInstallations).where(eq(botInstallations.workspaceId, workspaceId));
		await tx.delete(workspaceMembers).where(eq(workspaceMembers.workspaceId, workspaceId));
		await tx.delete(roles).where(eq(roles.workspaceId, workspaceId));
		return live.length;
	});
}

export function registerJobs(runner: JobRunner, services: Services): JobRunner {
	return runner
		.register("message.created", async ({ messageId }) => {
			const result = await fanOutMessage(services, BigInt(messageId));
			if (!result || !result.workspaceId) return;
			const author = await services.db.select().from(messages).where(eq(messages.id, BigInt(messageId)));
			const [serialized] = await serializeMessages(services.db, author, result.authorId);
			await queueBotEvent(services, {
				workspaceId: String(result.workspaceId),
				channelId: String(result.channelId),
				type: "message.create",
				data: { message: serialized },
				authorId: String(result.authorId),
			});
		})
		.register("message.updated", async ({ messageId }) => {
			const rows = await services.db.select().from(messages).where(eq(messages.id, BigInt(messageId)));
			const message = rows[0];
			if (!message || message.deletedAt) return;
			const [channel] = await services.db.select().from(channels).where(eq(channels.id, message.channelId));
			if (!channel?.workspaceId) return;
			const [serialized] = await serializeMessages(services.db, rows, message.authorId);
			await queueBotEvent(services, {
				workspaceId: String(channel.workspaceId),
				channelId: String(channel.id),
				type: "message.update",
				data: { message: serialized },
				authorId: String(message.authorId),
			});
		})
		.register("message.deleted", async ({ messageId, channelId }) => {
			const [channel] = await services.db.select().from(channels).where(eq(channels.id, BigInt(channelId)));
			if (!channel?.workspaceId) return;
			await queueBotEvent(services, {
				workspaceId: String(channel.workspaceId),
				channelId: String(channelId),
				type: "message.delete",
				data: { id: messageId, channelId },
			});
		})
		.register("bot.event", (payload) => queueBotEvent(services, payload))
		.register("bot.deliver", ({ botId, event }) => deliverToBot(services, BigInt(botId), event))
		.register("attachments.purge", ({ ids }) => deleteObjects(services, (ids as string[]).map(BigInt)))
		.register("channel.purge", ({ channelId }) => purgeChannel(services, BigInt(channelId)))
		.register("workspace.purge", ({ workspaceId }) => purgeWorkspace(services, BigInt(workspaceId)))
		.register("attachments.cleanup", async () => {
			// Uploads never sent, and files whose purge didn't finish
			const stale = await services.db
				.update(attachments)
				.set({ status: "deleted" })
				.where(
					or(
						and(eq(attachments.status, "pending"), lt(attachments.createdAt, new Date(Date.now() - PENDING_UPLOAD_HOURS * HOUR))),
						and(
							eq(attachments.status, "uploaded"),
							isNull(attachments.messageId),
							lt(attachments.createdAt, new Date(Date.now() - PENDING_UPLOAD_HOURS * HOUR)),
						),
					),
				)
				.returning({ id: attachments.id });
			const leftover = await services.db.select({ id: attachments.id }).from(attachments).where(eq(attachments.status, "deleted")).limit(1000);
			await deleteObjects(services, [...stale, ...leftover].map((a) => a.id));
			await schedulePeriodic(services, "attachments.cleanup");
		})
		.register("sessions.cleanup", async () => {
			const cutoff = new Date(Date.now() - SESSION_RETENTION_DAYS * 24 * HOUR);
			await services.db
				.delete(sessions)
				.where(or(lt(sessions.expiresAt, cutoff), and(isNotNull(sessions.revokedAt), lt(sessions.revokedAt, cutoff))));
			// Finished jobs are deleted; failed ones are kept 30 days for inspection
			await services.db.execute(sql`delete from jobs where attempts >= max_attempts and created_at < ${cutoff}`);
			await schedulePeriodic(services, "sessions.cleanup");
		});
}
