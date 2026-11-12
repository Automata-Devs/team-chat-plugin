import { and, eq, inArray, isNull } from "drizzle-orm";
import type { Actor, Services } from "../../context.js";
import { channelMembers, channels, workspaceMembers, workspaces } from "../../db/schema.js";
import type { GatewayEvent } from "../../infra/events.js";
import { actorOf, type Module } from "../../http/types.js";
import { visibleWorkspaceChannels, workspaceAccess } from "../access.js";

const HEARTBEAT_MS = 25_000;
const REFRESH_MS = 60_000;
const MAX_TOPICS = 2500;
/** These change what a client may see, so its subscriptions are recomputed at once. */
const REFRESH_ON = new Set([
	"workspace.join",
	"workspace.leave",
	"conversation.create",
	"conversation.delete",
	"channels.changed",
	"channel.create",
	"channel.delete",
	"member.update",
	"role.update",
	"role.delete",
]);

/** The topics a user may listen to: themselves, their workspaces, and every channel they can see. */
export async function topicsFor(services: Services, actor: Actor): Promise<string[]> {
	const db = services.db;
	const topics = [`user:${actor.userId}`];
	const memberships = await db
		.select({ id: workspaceMembers.workspaceId })
		.from(workspaceMembers)
		.innerJoin(workspaces, and(eq(workspaces.id, workspaceMembers.workspaceId), isNull(workspaces.deletedAt)))
		.where(eq(workspaceMembers.userId, actor.userId));
	for (const { id } of memberships) {
		topics.push(`workspace:${id}`);
		const access = await workspaceAccess(db, id, actor.userId);
		for (const { channel } of await visibleWorkspaceChannels(db, access)) topics.push(`channel:${channel.id}`);
	}
	const conversations = await db
		.select({ id: channels.id })
		.from(channels)
		.innerJoin(channelMembers, and(eq(channelMembers.channelId, channels.id), eq(channelMembers.userId, actor.userId)))
		.where(and(inArray(channels.type, ["dm", "group_dm"]), isNull(channels.deletedAt)));
	for (const { id } of conversations) topics.push(`channel:${id}`);
	return topics.slice(0, MAX_TOPICS);
}

export const gatewayModule: Module = (app, services) => {
	/**
	 * Server-Sent Events: one stream of everything the caller can see happen.
	 * Each event is "event: <type>" + "data: <json>". Subscriptions follow access
	 * changes: at once for the caller's own, within a minute otherwise. Works
	 * across instances when Redis is configured.
	 */
	app.get("/gateway", { config: { auth: "any" } }, async (request, reply) => {
		const actor = actorOf(request);
		let topics = await topicsFor(services, actor);
		reply.hijack();
		const res = reply.raw;
		res.writeHead(200, {
			"Content-Type": "text/event-stream; charset=utf-8",
			"Cache-Control": "no-cache, no-transform",
			Connection: "keep-alive",
			"X-Accel-Buffering": "no",
		});

		let closed = false;
		const send = (type: string, data: unknown) => {
			if (closed) return;
			res.write(`event: ${type}\ndata: ${JSON.stringify(data, (_k, v) => (typeof v === "bigint" ? v.toString() : v))}\n\n`);
		};

		let unsubscribe: () => Promise<void> = async () => undefined;
		let refreshing = false;
		const subscribe = async () => {
			const off = await services.events.subscribe(topics, (_topic: string, event: GatewayEvent) => {
				send(event.type, event.data);
				if (REFRESH_ON.has(event.type)) void refresh();
			});
			const previous = unsubscribe;
			unsubscribe = off;
			await previous();
		};
		const refresh = async () => {
			if (refreshing || closed) return;
			refreshing = true;
			try {
				const next = await topicsFor(services, actor);
				if (next.join() !== topics.join()) {
					topics = next;
					await subscribe();
				}
			} catch (error) {
				request.log.warn({ err: error }, "Gateway refresh failed");
			} finally {
				refreshing = false;
			}
		};

		await subscribe();
		send("ready", { userId: actor.userId, kind: actor.kind, topics: topics.length });
		const heartbeat = setInterval(() => !closed && res.write(": heartbeat\n\n"), HEARTBEAT_MS);
		const refresher = setInterval(() => void refresh(), REFRESH_MS);

		request.raw.on("close", () => {
			closed = true;
			clearInterval(heartbeat);
			clearInterval(refresher);
			void unsubscribe();
		});
	});
};
