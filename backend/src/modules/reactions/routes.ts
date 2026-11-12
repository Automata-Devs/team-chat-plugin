import { and, asc, eq, gt, isNull } from "drizzle-orm";
import { z } from "zod";
import type { Actor, Services } from "../../context.js";
import { messages, reactions, users } from "../../db/schema.js";
import { enqueue } from "../../infra/jobs.js";
import { actorOf, type Module } from "../../http/types.js";
import { badRequest, forbidden, notFound } from "../../lib/errors.js";
import { Permission, has } from "../../lib/permissions.js";
import { limit, parse, snowflake } from "../../lib/validation.js";
import { isConversation, requireChannelPermission } from "../access.js";
import { assertNotBlockedInDm } from "../messages/service.js";
import { publicUser, publish } from "../shared.js";

const MAX_EMOJIS_PER_MESSAGE = 20;

const UNICODE_EMOJI = /^[\p{Extended_Pictographic}\p{Emoji_Component}‍️⃣]+$/u;
const HAS_PICTURE = /[\p{Extended_Pictographic}\p{Regional_Indicator}⃣]/u;
const CUSTOM_EMOJI = /^[A-Za-z0-9_]{2,32}:[0-9]{1,19}$/;

/** A Unicode emoji (sequences included) or a custom one as name:id. Nothing else is stored. */
export const emoji = z
	.string()
	.max(64)
	.transform((value) => value.normalize("NFC"))
	.refine(
		(value) => CUSTOM_EMOJI.test(value) || (UNICODE_EMOJI.test(value) && HAS_PICTURE.test(value) && [...value].length <= 16),
		"Not an emoji",
	);

const Params = z.object({ channelId: snowflake, messageId: snowflake, emoji });
const Who = z.object({ after: snowflake.optional(), limit: limit(25, 100) });

async function assertLiveMessage(services: Services, channelId: bigint, messageId: bigint) {
	const [row] = await services.db
		.select({ id: messages.id })
		.from(messages)
		.where(and(eq(messages.id, messageId), eq(messages.channelId, channelId), isNull(messages.deletedAt)));
	if (!row) throw notFound("Message");
}

async function addReaction(services: Services, actor: Actor, channelId: bigint, messageId: bigint, value: string) {
	const access = await requireChannelPermission(services.db, channelId, actor.userId, Permission.READ_MESSAGE_HISTORY);
	await assertNotBlockedInDm(services.db, access, actor.userId);
	const added = await services.db.transaction(async (tx) => {
		// Locking the message keeps the "20 different emoji" limit under concurrent reactions
		const [message] = await tx
			.select({ id: messages.id })
			.from(messages)
			.where(and(eq(messages.id, messageId), eq(messages.channelId, channelId), isNull(messages.deletedAt)))
			.for("update");
		if (!message) throw notFound("Message");
		const existing = await tx
			.select({ emoji: reactions.emoji })
			.from(reactions)
			.where(eq(reactions.messageId, messageId))
			.groupBy(reactions.emoji);
		if (!existing.some((r) => r.emoji === value)) {
			// Starting a new reaction needs ADD_REACTIONS; joining one only needs to read the message
			if (!has(access.permissions, Permission.ADD_REACTIONS)) throw forbidden("You can't add new reactions here");
			if (existing.length >= MAX_EMOJIS_PER_MESSAGE) {
				throw badRequest(`A message can have at most ${MAX_EMOJIS_PER_MESSAGE} different reactions`);
			}
		}
		const inserted = await tx
			.insert(reactions)
			.values({ messageId, emoji: value, userId: actor.userId })
			.onConflictDoNothing()
			.returning();
		if (inserted.length > 0 && !isConversation(access.channel)) {
			await enqueue(tx, "bot.event", {
				workspaceId: access.channel.workspaceId,
				channelId,
				type: "reaction.add",
				data: { channelId, messageId, emoji: value, userId: actor.userId },
			});
		}
		return inserted.length > 0;
	});
	if (added) publish(services, `channel:${channelId}`, "reaction.add", { channelId, messageId, emoji: value, userId: actor.userId });
}

export const reactionsModule: Module = (app, services) => {
	const any = { auth: "any" as const };

	app.put("/channels/:channelId/messages/:messageId/reactions/:emoji/@me", { config: any }, async (request, reply) => {
		const p = parse(Params, request.params);
		await addReaction(services, actorOf(request), p.channelId, p.messageId, p.emoji);
		return reply.status(204).send();
	});

	app.delete("/channels/:channelId/messages/:messageId/reactions/:emoji/@me", { config: any }, async (request, reply) => {
		const p = parse(Params, request.params);
		const actor = actorOf(request);
		await requireChannelPermission(services.db, p.channelId, actor.userId, Permission.VIEW_CHANNEL);
		await assertLiveMessage(services, p.channelId, p.messageId);
		const removed = await services.db
			.delete(reactions)
			.where(and(eq(reactions.messageId, p.messageId), eq(reactions.emoji, p.emoji), eq(reactions.userId, actor.userId)))
			.returning();
		if (removed.length > 0) {
			publish(services, `channel:${p.channelId}`, "reaction.remove", {
				channelId: p.channelId,
				messageId: p.messageId,
				emoji: p.emoji,
				userId: actor.userId,
			});
		}
		return reply.status(204).send();
	});

	/** Clears one emoji from a message (moderators). */
	app.delete("/channels/:channelId/messages/:messageId/reactions/:emoji", { config: any }, async (request, reply) => {
		const p = parse(Params, request.params);
		const access = await requireChannelPermission(services.db, p.channelId, actorOf(request).userId, Permission.MANAGE_MESSAGES);
		if (isConversation(access.channel)) throw forbidden();
		await assertLiveMessage(services, p.channelId, p.messageId);
		await services.db.delete(reactions).where(and(eq(reactions.messageId, p.messageId), eq(reactions.emoji, p.emoji)));
		publish(services, `channel:${p.channelId}`, "reaction.clear", { channelId: p.channelId, messageId: p.messageId, emoji: p.emoji });
		return reply.status(204).send();
	});

	/** Who reacted with this emoji, in user id order. */
	app.get("/channels/:channelId/messages/:messageId/reactions/:emoji", { config: any }, async (request) => {
		const p = parse(Params, request.params);
		const query = parse(Who, request.query);
		await requireChannelPermission(services.db, p.channelId, actorOf(request).userId, Permission.READ_MESSAGE_HISTORY);
		await assertLiveMessage(services, p.channelId, p.messageId);
		const rows = await services.db
			.select({ user: users })
			.from(reactions)
			.innerJoin(users, eq(users.id, reactions.userId))
			.where(
				and(
					eq(reactions.messageId, p.messageId),
					eq(reactions.emoji, p.emoji),
					query.after ? gt(reactions.userId, query.after) : undefined,
				),
			)
			.orderBy(asc(reactions.userId))
			.limit(query.limit);
		return { users: rows.map((r) => publicUser(r.user)) };
	});
};
