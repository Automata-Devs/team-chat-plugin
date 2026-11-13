import { and, asc, desc, eq, inArray, isNotNull, isNull, lt, or, sql } from "drizzle-orm";
import type { Actor, Services } from "../../context.js";
import type { Tx } from "../../db/client.js";
import {
	channelMembers,
	channels,
	channelUserSettings,
	readStates,
	relationships,
	userSettings,
	users,
	workspaceMembers,
} from "../../db/schema.js";
import { enqueue } from "../../infra/jobs.js";
import { badRequest, forbidden, notFound } from "../../lib/errors.js";
import { type Channel, channelAccess, isConversation, workspaceAccess } from "../access.js";
import { insertSystemMessage } from "../messages/service.js";
import { withDefaults } from "../settings/defaults.js";
import { publish, usersById } from "../shared.js";

export const MAX_GROUP_SIZE = 10;

const dmKey = (a: bigint, b: bigint, workspaceId?: bigint) =>
	(workspaceId ? `${workspaceId}:` : "") + (a < b ? `${a}:${b}` : `${b}:${a}`);

/** Whether `from` may start a conversation with `to`: blocks and the recipient's privacy setting. */
async function assertCanMessage(tx: Tx, from: bigint, to: bigint): Promise<void> {
	const [target] = await tx.select().from(users).where(eq(users.id, to)).limit(1);
	if (!target || target.status !== "active") throw notFound("User");
	if (target.isBot) throw badRequest("Bots can't be in conversations");

	const [block] = await tx
		.select({ userId: relationships.userId })
		.from(relationships)
		.where(
			and(
				eq(relationships.type, "block"),
				or(
					and(eq(relationships.userId, from), eq(relationships.targetId, to)),
					and(eq(relationships.userId, to), eq(relationships.targetId, from)),
				),
			),
		)
		.limit(1);
	if (block) throw forbidden("You can't message this user");

	const [row] = await tx.select({ settings: userSettings.settings }).from(userSettings).where(eq(userSettings.userId, to));
	const privacy = withDefaults(row?.settings).privacy.allowDirectMessages;
	if (privacy === "none") throw forbidden("This user doesn't accept direct messages");
	if (privacy === "workspace_members") {
		const shared = await tx.execute(sql`
			select 1 from workspace_members a
			join workspace_members b on b.workspace_id = a.workspace_id
			join workspaces w on w.id = a.workspace_id and w.deleted_at is null
			where a.user_id = ${from} and b.user_id = ${to} limit 1`);
		if (shared.rows.length === 0) throw forbidden("This user only accepts messages from people in their workspaces");
	}
}

/** Conversations as the API returns them, for one user: recipients, read state, unread count, settings. */
export async function serializeConversations(tx: Tx, rows: Channel[], viewerId: bigint) {
	if (rows.length === 0) return [];
	const ids = rows.map((c) => c.id);
	const idList = sql.join(
		ids.map((id) => sql`${id}`),
		sql`, `,
	);
	const [members, states, settings, unread] = await Promise.all([
		tx.select().from(channelMembers).where(inArray(channelMembers.channelId, ids)),
		tx
			.select()
			.from(readStates)
			.where(and(inArray(readStates.channelId, ids), eq(readStates.userId, viewerId))),
		tx
			.select()
			.from(channelUserSettings)
			.where(and(inArray(channelUserSettings.channelId, ids), eq(channelUserSettings.userId, viewerId))),
		// Counted up to 100 per conversation ("99+"), along the (channel_id, id) index
		tx.execute<{ channel_id: string; unread: number }>(sql`
			select c.id as channel_id, (
				select count(*)::int from (
					select 1 from messages m
					where m.channel_id = c.id and m.deleted_at is null and m.author_id <> ${viewerId}
					  and m.id > coalesce((select r.last_read_message_id from read_states r
					                       where r.channel_id = c.id and r.user_id = ${viewerId}), 0)
					limit 100
				) x
			) as unread
			from channels c where c.id in (${idList})`),
	]);
	const people = await usersById(
		tx,
		members.map((m) => m.userId),
	);
	const unreadById = new Map(unread.rows.map((r) => [BigInt(r.channel_id), r.unread]));
	const now = new Date();
	return rows.map((channel) => {
		const state = states.find((s) => s.channelId === channel.id);
		const mine = settings.find((s) => s.channelId === channel.id);
		return {
			id: channel.id,
			type: channel.type,
			workspaceId: channel.workspaceId,
			name: channel.name,
			iconUrl: channel.iconUrl,
			ownerId: channel.ownerId,
			lastMessageId: channel.lastMessageId,
			createdAt: channel.createdAt,
			recipients: members
				.filter((m) => m.channelId === channel.id && m.userId !== viewerId)
				.map((m) => people.get(m.userId))
				.filter((u) => u !== undefined),
			readState: { lastReadMessageId: state?.lastReadMessageId ?? 0n, mentionCount: state?.mentionCount ?? 0 },
			unreadCount: unreadById.get(channel.id) ?? 0,
			settings: {
				muted: !!mine?.muted && (!mine.mutedUntil || mine.mutedUntil > now),
				mutedUntil: mine?.mutedUntil ?? null,
				notificationLevel: mine?.notificationLevel ?? null,
				archived: !!mine?.archivedAt,
			},
		};
	});
}

/**
 * Opens a DM or starts a group. With `workspaceId` it belongs to that
 * workspace (a place's DMs): everyone in it must be a member, and the same two
 * people have a separate DM in every workspace.
 */
export async function openConversation(
	services: Services,
	actor: Actor,
	input: { recipients: bigint[]; name?: string; workspaceId?: bigint },
) {
	const recipients = [...new Set(input.recipients)].filter((id) => id !== actor.userId);
	if (recipients.length === 0) throw badRequest("Add at least one other person");
	if (recipients.length + 1 > MAX_GROUP_SIZE) throw badRequest(`A group can have at most ${MAX_GROUP_SIZE} people`);

	const workspaceId = input.workspaceId ?? null;
	const opened = await services.db.transaction(async (tx) => {
		if (workspaceId) {
			await workspaceAccess(tx, workspaceId, actor.userId);
			const members = await tx
				.select({ userId: workspaceMembers.userId })
				.from(workspaceMembers)
				.where(and(eq(workspaceMembers.workspaceId, workspaceId), inArray(workspaceMembers.userId, recipients)));
			if (members.length !== recipients.length) throw notFound("Member");
		}
		for (const id of recipients) await assertCanMessage(tx, actor.userId, id);

		if (recipients.length === 1 && input.name === undefined) {
			// One DM per pair, also when both open it at the same moment (dm_key is unique)
			const key = dmKey(actor.userId, recipients[0], workspaceId ?? undefined);
			const [created] = await tx
				.insert(channels)
				.values({ id: services.ids.next(), type: "dm", dmKey: key, workspaceId })
				.onConflictDoNothing({ target: channels.dmKey })
				.returning();
			const [dm] = created ? [created] : await tx.select().from(channels).where(eq(channels.dmKey, key));
			await tx
				.insert(channelMembers)
				.values([actor.userId, recipients[0]].map((userId) => ({ channelId: dm.id, userId })))
				.onConflictDoNothing();
			// Opening an archived DM brings it back
			await tx
				.update(channelUserSettings)
				.set({ archivedAt: null })
				.where(and(eq(channelUserSettings.channelId, dm.id), eq(channelUserSettings.userId, actor.userId)));
			return { channel: dm, isNew: !!created };
		}

		const [group] = await tx
			.insert(channels)
			.values({ id: services.ids.next(), type: "group_dm", ownerId: actor.userId, name: input.name ?? null, workspaceId })
			.returning();
		await tx.insert(channelMembers).values([actor.userId, ...recipients].map((userId) => ({ channelId: group.id, userId })));
		return { channel: group, isNew: true };
	});

	const [conversation] = await serializeConversations(services.db, [opened.channel], actor.userId);
	if (opened.isNew) {
		for (const userId of [actor.userId, ...recipients]) {
			publish(services, `user:${userId}`, "conversation.create", { id: opened.channel.id });
		}
	}
	return conversation;
}

export async function listConversations(
	services: Services,
	actor: Actor,
	query: { archived: boolean; before?: bigint; limit: number; workspaceId?: bigint },
) {
	const activity = sql`coalesce(${channels.lastMessageId}, ${channels.id})`;
	const rows = await services.db
		.select({ channel: channels })
		.from(channels)
		.innerJoin(channelMembers, and(eq(channelMembers.channelId, channels.id), eq(channelMembers.userId, actor.userId)))
		.leftJoin(
			channelUserSettings,
			and(eq(channelUserSettings.channelId, channels.id), eq(channelUserSettings.userId, actor.userId)),
		)
		.where(
			and(
				inArray(channels.type, ["dm", "group_dm"]),
				isNull(channels.deletedAt),
				query.archived ? isNotNull(channelUserSettings.archivedAt) : isNull(channelUserSettings.archivedAt),
				query.before !== undefined ? lt(activity, query.before) : undefined,
				query.workspaceId !== undefined ? eq(channels.workspaceId, query.workspaceId) : undefined,
			),
		)
		.orderBy(desc(activity))
		.limit(query.limit);
	return serializeConversations(
		services.db,
		rows.map((r) => r.channel),
		actor.userId,
	);
}

async function loadConversation(tx: Tx, channelId: bigint, userId: bigint) {
	const access = await channelAccess(tx, channelId, userId);
	if (!isConversation(access.channel)) throw notFound("Conversation");
	return access.channel;
}

export async function getConversation(services: Services, actor: Actor, channelId: bigint) {
	const channel = await loadConversation(services.db, channelId, actor.userId);
	return (await serializeConversations(services.db, [channel], actor.userId))[0];
}

export async function updateConversation(
	services: Services,
	actor: Actor,
	channelId: bigint,
	input: { name?: string | null; iconUrl?: string | null },
) {
	const updated = await services.db.transaction(async (tx) => {
		const channel = await loadConversation(tx, channelId, actor.userId);
		if (channel.type !== "group_dm") throw badRequest("Only group conversations have a name and icon");
		const [row] = await tx
			.update(channels)
			.set({
				name: input.name === undefined ? channel.name : input.name,
				iconUrl: input.iconUrl === undefined ? channel.iconUrl : input.iconUrl,
			})
			.where(eq(channels.id, channelId))
			.returning();
		if (input.name !== undefined && input.name !== channel.name) {
			await insertSystemMessage(services, tx, channelId, actor.userId, "channel_name_change", { name: input.name });
		}
		return row;
	});
	publish(services, `channel:${channelId}`, "conversation.update", { id: channelId, name: updated.name, iconUrl: updated.iconUrl });
	return (await serializeConversations(services.db, [updated], actor.userId))[0];
}

export async function addRecipient(services: Services, actor: Actor, channelId: bigint, userId: bigint) {
	await services.db.transaction(async (tx) => {
		const channel = await loadConversation(tx, channelId, actor.userId);
		if (channel.type !== "group_dm") throw badRequest("Start a group to add more people");
		// Lock the conversation so two adds at once can't pass the size limit
		await tx.select({ id: channels.id }).from(channels).where(eq(channels.id, channelId)).for("update");
		await assertCanMessage(tx, actor.userId, userId);
		const [{ count }] = await tx
			.select({ count: sql<number>`count(*)::int` })
			.from(channelMembers)
			.where(eq(channelMembers.channelId, channelId));
		if (count >= MAX_GROUP_SIZE) throw badRequest(`A group can have at most ${MAX_GROUP_SIZE} people`);
		const added = await tx.insert(channelMembers).values({ channelId, userId }).onConflictDoNothing().returning();
		if (added.length > 0) await insertSystemMessage(services, tx, channelId, actor.userId, "recipient_add", { userId });
	});
	publish(services, `channel:${channelId}`, "conversation.recipient_add", { channelId, userId });
	publish(services, `user:${userId}`, "conversation.create", { id: channelId });
}

/**
 * Removes someone from a group conversation (yourself: leaving). The owner may
 * remove anyone. An owner who leaves hands the group to the longest member;
 * when the last person leaves, the conversation is deleted and purged.
 * The caller locks the channel row first.
 */
export async function removeRecipient(services: Services, tx: Tx, channel: Channel, userId: bigint, actorId: bigint) {
	if (channel.type !== "group_dm") throw badRequest("You can't leave a direct message; archive it instead");
	if (userId !== actorId && channel.ownerId !== actorId) throw forbidden("Only the owner can remove people");

	const removed = await tx
		.delete(channelMembers)
		.where(and(eq(channelMembers.channelId, channel.id), eq(channelMembers.userId, userId)))
		.returning();
	if (removed.length === 0) throw notFound("Recipient");
	await tx.delete(readStates).where(and(eq(readStates.channelId, channel.id), eq(readStates.userId, userId)));
	await tx
		.delete(channelUserSettings)
		.where(and(eq(channelUserSettings.channelId, channel.id), eq(channelUserSettings.userId, userId)));

	const [next] = await tx
		.select({ userId: channelMembers.userId })
		.from(channelMembers)
		.where(eq(channelMembers.channelId, channel.id))
		.orderBy(asc(channelMembers.joinedAt), asc(channelMembers.userId))
		.limit(1);
	if (!next) {
		await tx.update(channels).set({ deletedAt: new Date() }).where(eq(channels.id, channel.id));
		await enqueue(tx, "channel.purge", { channelId: channel.id });
		return { deleted: true, ownerId: null };
	}
	const ownerId = channel.ownerId === userId ? next.userId : channel.ownerId;
	if (ownerId !== channel.ownerId) await tx.update(channels).set({ ownerId }).where(eq(channels.id, channel.id));
	await insertSystemMessage(services, tx, channel.id, actorId, "recipient_remove", { userId });
	return { deleted: false, ownerId };
}

export async function leaveOrRemove(services: Services, actor: Actor, channelId: bigint, userId: bigint) {
	const result = await services.db.transaction(async (tx) => {
		await loadConversation(tx, channelId, actor.userId);
		const [locked] = await tx.select().from(channels).where(eq(channels.id, channelId)).for("update");
		return removeRecipient(services, tx, locked, userId, actor.userId);
	});
	publish(services, `channel:${channelId}`, "conversation.recipient_remove", { channelId, userId, ...result });
	publish(services, `user:${userId}`, "conversation.delete", { id: channelId });
}

export async function updateChannelSettings(
	services: Services,
	actor: Actor,
	channelId: bigint,
	input: { muted?: boolean; mutedUntil?: Date | null; notificationLevel?: "all" | "mentions" | "none" | null; archived?: boolean },
) {
	const access = await channelAccess(services.db, channelId, actor.userId);
	if (input.archived !== undefined && !isConversation(access.channel)) throw badRequest("Only conversations can be archived");
	const changes = {
		muted: input.muted,
		mutedUntil: input.mutedUntil,
		notificationLevel: input.notificationLevel,
		archivedAt: input.archived === undefined ? undefined : input.archived ? new Date() : null,
	};
	const set = Object.fromEntries(Object.entries(changes).filter(([, v]) => v !== undefined));
	const [row] = await services.db
		.insert(channelUserSettings)
		.values({ userId: actor.userId, channelId, ...set })
		.onConflictDoUpdate({
			target: [channelUserSettings.userId, channelUserSettings.channelId],
			set: { ...set, updatedAt: new Date() },
		})
		.returning();
	publish(services, `user:${actor.userId}`, "channel_settings.update", row);
	return row;
}

/** For account deletion: leaves every group conversation (1:1 DMs stay, for the other person). */
export async function leaveAllGroups(services: Services, tx: Tx, userId: bigint) {
	const groups = await tx
		.select({ id: channels.id })
		.from(channels)
		.innerJoin(channelMembers, and(eq(channelMembers.channelId, channels.id), eq(channelMembers.userId, userId)))
		.where(and(eq(channels.type, "group_dm"), isNull(channels.deletedAt)));
	for (const { id } of groups) {
		const [locked] = await tx.select().from(channels).where(eq(channels.id, id)).for("update");
		await removeRecipient(services, tx, locked, userId, userId);
	}
	return groups.map((g) => g.id);
}
