import { and, desc, eq, inArray, isNull, lt, sql } from "drizzle-orm";
import { z } from "zod";
import type { Actor, Services } from "../../context.js";
import { channelMembers, channels, messages, workspaceMembers, workspaces } from "../../db/schema.js";
import { LIMITS } from "../../http/rateLimit.js";
import { actorOf, type Module } from "../../http/types.js";
import { badRequest } from "../../lib/errors.js";
import { Permission, has } from "../../lib/permissions.js";
import { snowflakeAt } from "../../lib/snowflake.js";
import { limit, parse, snowflake } from "../../lib/validation.js";
import { requireChannelPermission, visibleWorkspaceChannels, workspaceAccess } from "../access.js";
import { serializeMessages } from "../messages/service.js";

const MAX_SCOPE_CHANNELS = 2000;

const Query = z
	.object({
		q: z.string().trim().max(200).optional(),
		channelId: snowflake.optional(),
		workspaceId: snowflake.optional(),
		authorId: snowflake.optional(),
		after: z.coerce.date().optional(),
		before: z.coerce.date().optional(),
		/** Results older than this message id (the previous page's nextCursor). */
		cursor: snowflake.optional(),
		limit: limit(25, 50),
	})
	.refine((q) => q.q || q.authorId, "Search for text or an author")
	.refine((q) => !(q.channelId && q.workspaceId), "Use channelId or workspaceId, not both");

/** Only channels the caller may read: one channel, a workspace's, or every one they're in. */
async function readableChannels(services: Services, actor: Actor, query: z.infer<typeof Query>): Promise<bigint[]> {
	const db = services.db;
	if (query.channelId) {
		await requireChannelPermission(db, query.channelId, actor.userId, Permission.READ_MESSAGE_HISTORY);
		return [query.channelId];
	}
	const workspaceIds = query.workspaceId
		? [query.workspaceId]
		: (
				await db
					.select({ id: workspaceMembers.workspaceId })
					.from(workspaceMembers)
					.innerJoin(workspaces, and(eq(workspaces.id, workspaceMembers.workspaceId), isNull(workspaces.deletedAt)))
					.where(eq(workspaceMembers.userId, actor.userId))
			).map((w) => w.id);

	const ids: bigint[] = [];
	for (const workspaceId of workspaceIds) {
		const access = await workspaceAccess(db, workspaceId, actor.userId);
		for (const { channel, permissions } of await visibleWorkspaceChannels(db, access)) {
			if (channel.type === "text" && has(permissions, Permission.READ_MESSAGE_HISTORY)) ids.push(channel.id);
		}
	}
	const conversations = await db
		.select({ id: channels.id })
		.from(channels)
		.innerJoin(channelMembers, and(eq(channelMembers.channelId, channels.id), eq(channelMembers.userId, actor.userId)))
		.where(
			and(
				inArray(channels.type, ["dm", "group_dm"]),
				isNull(channels.deletedAt),
				query.workspaceId ? eq(channels.workspaceId, query.workspaceId) : undefined,
			),
		);
	ids.push(...conversations.map((c) => c.id));
	return ids.slice(0, MAX_SCOPE_CHANNELS);
}

/** Words to a tsquery: every word must match, the last may be the start of one ("lig" finds "lighting"). */
export function toTsquery(text: string): string {
	const words = text
		.toLowerCase()
		.split(/[^\p{L}\p{N}_]+/u)
		.filter(Boolean)
		.slice(0, 10);
	return words.map((word, i) => (i === words.length - 1 ? `${word}:*` : word)).join(" & ");
}

export const searchModule: Module = (app, services) => {
	/**
	 * Full-text search over messages the caller can read, newest first. Filters:
	 * channel, workspace, author, date range. Private channels they're not in and
	 * other people's conversations are never searched.
	 */
	app.get("/search/messages", { config: { limit: LIMITS.search } }, async (request) => {
		const actor = actorOf(request);
		const query = parse(Query, request.query);
		if (query.after && query.before && query.after >= query.before) throw badRequest("after must be earlier than before");
		const scope = await readableChannels(services, actor, query);
		if (scope.length === 0) return { messages: [], nextCursor: null };

		const tsquery = toTsquery(query.q ?? "");
		if (query.q && !tsquery && !query.authorId) return { messages: [], nextCursor: null };

		const rows = await services.db
			.select()
			.from(messages)
			.where(
				and(
					inArray(messages.channelId, scope),
					isNull(messages.deletedAt),
					tsquery ? sql`${messages.search} @@ to_tsquery('simple', ${tsquery})` : undefined,
					query.authorId ? eq(messages.authorId, query.authorId) : undefined,
					query.after ? sql`${messages.id} >= ${snowflakeAt(query.after)}` : undefined,
					query.before ? lt(messages.id, snowflakeAt(query.before)) : undefined,
					query.cursor ? lt(messages.id, query.cursor) : undefined,
				),
			)
			.orderBy(desc(messages.id))
			.limit(query.limit);
		const results = await serializeMessages(services.db, rows, actor.userId);
		return { messages: results, nextCursor: rows.length === query.limit ? rows[rows.length - 1].id : null };
	});
};
