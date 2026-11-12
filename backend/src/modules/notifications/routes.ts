import { and, desc, eq, gt, inArray, isNull, lt, lte } from "drizzle-orm";
import { z } from "zod";
import { notifications, readStates } from "../../db/schema.js";
import { actorOf, type Module } from "../../http/types.js";
import { limit, parse, snowflake } from "../../lib/validation.js";

const List = z.object({
	before: snowflake.optional(),
	limit: limit(25, 100),
	unread: z.enum(["true", "false"]).default("false").transform((v) => v === "true"),
});
const MarkRead = z
	.object({ ids: z.array(snowflake).max(100).optional(), upTo: snowflake.optional() })
	.strict()
	.refine((b) => b.ids || b.upTo, "Give ids or upTo");

export const notificationsModule: Module = (app, services) => {
	/** Your inbox: mentions, replies and direct messages, newest first. */
	app.get("/notifications", async (request) => {
		const userId = actorOf(request).userId;
		const query = parse(List, request.query);
		const rows = await services.db
			.select()
			.from(notifications)
			.where(
				and(
					eq(notifications.userId, userId),
					query.before ? lt(notifications.id, query.before) : undefined,
					query.unread ? isNull(notifications.readAt) : undefined,
				),
			)
			.orderBy(desc(notifications.id))
			.limit(query.limit);
		return { notifications: rows };
	});

	app.post("/notifications/read", async (request, reply) => {
		const userId = actorOf(request).userId;
		const body = parse(MarkRead, request.body);
		await services.db
			.update(notifications)
			.set({ readAt: new Date() })
			.where(
				and(
					eq(notifications.userId, userId),
					isNull(notifications.readAt),
					body.ids ? inArray(notifications.id, body.ids) : lte(notifications.id, body.upTo!),
				),
			);
		return reply.status(204).send();
	});

	/** Where you are in every channel, and your mention badges. */
	app.get("/users/@me/read-states", async (request) => {
		const rows = await services.db
			.select()
			.from(readStates)
			.where(and(eq(readStates.userId, actorOf(request).userId), gt(readStates.lastReadMessageId, -1n)));
		return { readStates: rows };
	});
};
