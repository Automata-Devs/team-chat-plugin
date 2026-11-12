import { and, asc, desc, eq, gt, inArray, isNull, lt, lte, ne, or, sql } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import type { z } from "zod";
import type { Actor, Services } from "../../context.js";
import { pgCode, UNIQUE_VIOLATION, type Tx } from "../../db/client.js";
import { attachments, channelMembers, channels, messages, pins, reactions, readStates, relationships, users } from "../../db/schema.js";
import { enqueue } from "../../infra/jobs.js";
import { AppError, badRequest, forbidden, notFound } from "../../lib/errors.js";
import { Permission, has } from "../../lib/permissions.js";
import { type ChannelAccess, isConversation, requireChannelPermission } from "../access.js";
import { audit, publish, type PublicUser, usersById } from "../shared.js";
import type { CreateMessage, EditMessage, ListMessages } from "./shapes.js";
import { parseMentions } from "./shapes.js";

export type MessageRow = typeof messages.$inferSelect;
type MessageType = MessageRow["type"];

const MAX_PINS = 50;

/**
 * Turns rows into API messages: authors, attachments, reactions and the
 * replied-to message come from 4 batched queries, whatever the page size.
 */
export async function serializeMessages(tx: Tx, rows: MessageRow[], viewerId: bigint) {
	if (rows.length === 0) return [];
	const ids = rows.map((m) => m.id);
	const replyIds = [...new Set(rows.map((m) => m.replyToId).filter((id): id is bigint => id !== null))];

	const [files, reactionRows, replies] = await Promise.all([
		tx
			.select({
				id: attachments.id,
				messageId: attachments.messageId,
				filename: attachments.filename,
				contentType: attachments.contentType,
				size: attachments.size,
			})
			.from(attachments)
			.where(and(inArray(attachments.messageId, ids), eq(attachments.status, "uploaded"))),
		tx
			.select({
				messageId: reactions.messageId,
				emoji: reactions.emoji,
				count: sql<number>`count(*)::int`,
				me: sql<boolean>`bool_or(${reactions.userId} = ${viewerId})`,
				first: sql<Date>`min(${reactions.createdAt})`,
			})
			.from(reactions)
			.where(inArray(reactions.messageId, ids))
			.groupBy(reactions.messageId, reactions.emoji)
			.orderBy(sql`min(${reactions.createdAt})`),
		replyIds.length === 0
			? Promise.resolve([])
			: tx
					.select({ id: messages.id, authorId: messages.authorId, content: messages.content, deletedAt: messages.deletedAt })
					.from(messages)
					.where(inArray(messages.id, replyIds)),
	]);

	const authors = await usersById(tx, [...rows.map((m) => m.authorId), ...replies.map((r) => r.authorId)]);
	const author = (id: bigint): PublicUser =>
		authors.get(id) ?? { id, username: "unknown", displayName: null, avatarUrl: null, isBot: false, createdAt: new Date(0) };

	const filesByMessage = group(files, (f) => f.messageId!);
	const reactionsByMessage = group(reactionRows, (r) => r.messageId);
	const replyById = new Map(replies.map((r) => [r.id, r]));

	return rows.map((m) => {
		const reply = m.replyToId ? replyById.get(m.replyToId) : undefined;
		return {
			id: m.id,
			channelId: m.channelId,
			author: author(m.authorId),
			type: m.type,
			content: m.content,
			flags: m.flags,
			replyTo: m.replyToId
				? reply && !reply.deletedAt
					? { id: reply.id, author: author(reply.authorId), content: reply.content.slice(0, 200), deleted: false }
					: { id: m.replyToId, author: null, content: null, deleted: true }
				: null,
			mentions: m.mentions,
			mentionEveryone: m.mentionEveryone,
			embeds: m.embeds,
			components: m.components,
			metadata: m.metadata,
			attachments: (filesByMessage.get(m.id) ?? []).map(({ messageId: _m, ...file }) => file),
			reactions: (reactionsByMessage.get(m.id) ?? []).map((r) => ({ emoji: r.emoji, count: r.count, me: r.me })),
			nonce: m.nonce,
			createdAt: m.createdAt,
			editedAt: m.editedAt,
		};
	});
}

function group<T, K>(items: T[], key: (item: T) => K): Map<K, T[]> {
	const map = new Map<K, T[]>();
	for (const item of items) {
		const list = map.get(key(item)) ?? [];
		list.push(item);
		map.set(key(item), list);
	}
	return map;
}

export type ApiMessage = Awaited<ReturnType<typeof serializeMessages>>[number];

async function blockedBetween(tx: Tx, a: bigint, b: bigint): Promise<boolean> {
	const [row] = await tx
		.select({ userId: relationships.userId })
		.from(relationships)
		.where(
			and(
				eq(relationships.type, "block"),
				or(
					and(eq(relationships.userId, a), eq(relationships.targetId, b)),
					and(eq(relationships.userId, b), eq(relationships.targetId, a)),
				),
			),
		)
		.limit(1);
	return !!row;
}

/** In a 1:1 DM, either side blocking the other stops new messages and reactions. */
export async function assertNotBlockedInDm(tx: Tx, access: ChannelAccess, userId: bigint): Promise<void> {
	if (access.channel.type !== "dm") return;
	const [other] = await tx
		.select({ userId: channelMembers.userId })
		.from(channelMembers)
		.where(and(eq(channelMembers.channelId, access.channel.id), ne(channelMembers.userId, userId)))
		.limit(1);
	if (other && (await blockedBetween(tx, userId, other.userId))) throw forbidden("You can't message this user");
}

async function messageByNonce(tx: Tx, authorId: bigint, nonce: string) {
	const [row] = await tx
		.select()
		.from(messages)
		.where(and(eq(messages.authorId, authorId), eq(messages.nonce, nonce)))
		.limit(1);
	return row;
}

async function checkSlowmode(services: Services, access: ChannelAccess, userId: bigint) {
	const seconds = access.channel.slowmodeSeconds;
	if (seconds <= 0 || has(access.permissions, Permission.MANAGE_MESSAGES) || has(access.permissions, Permission.MANAGE_CHANNELS)) return;
	const key = `slowmode:${access.channel.id}:${userId}`;
	if (!(await services.cache.setIfAbsent(key, "1", seconds))) {
		throw new AppError(429, "slowmode", `Slowmode is on: wait ${seconds} seconds between messages`, { retryAfter: seconds });
	}
}

export async function createMessage(
	services: Services,
	actor: Actor,
	channelId: bigint,
	input: z.infer<typeof CreateMessage>,
): Promise<ApiMessage> {
	const db = services.db;
	const access = await requireChannelPermission(db, channelId, actor.userId, Permission.SEND_MESSAGES);
	if (input.nonce) {
		const existing = await messageByNonce(db, actor.userId, input.nonce);
		if (existing) {
			if (existing.channelId !== channelId) throw badRequest("That nonce was used in another channel");
			return (await serializeMessages(db, [existing], actor.userId))[0];
		}
	}

	if (access.channel.type === "category") throw badRequest("Categories hold channels, not messages");
	if (input.attachments.length > 0 && !has(access.permissions, Permission.ATTACH_FILES)) throw forbidden("You can't attach files here");
	if (input.embeds.length > 0 && !has(access.permissions, Permission.EMBED_LINKS)) throw forbidden("You can't send embeds here");
	if (input.components.length > 0 && actor.kind !== "bot") throw forbidden("Only bots can send buttons");
	await assertNotBlockedInDm(db, access, actor.userId);

	let type: MessageType = "default";
	let metadata: Record<string, unknown> = {};
	if (input.interactionId) {
		if (actor.kind !== "bot") throw forbidden("Only bots answer interactions");
		const raw = await services.cache.get(`interaction:${input.interactionId}`);
		const interaction = raw ? (JSON.parse(raw) as { botId: string; channelId: string; userId: string; command: string }) : null;
		if (!interaction || interaction.botId !== String(actor.userId) || interaction.channelId !== String(channelId)) {
			throw badRequest("Unknown or expired interaction");
		}
		await services.cache.del(`interaction:${input.interactionId}`);
		type = "command";
		metadata = { interaction: { id: input.interactionId, userId: interaction.userId, command: interaction.command } };
	}

	const mentioned = parseMentions(input.content);
	const mentionEveryone = mentioned.everyone && !isConversation(access.channel) && has(access.permissions, Permission.MENTION_EVERYONE);

	if (input.replyTo !== undefined) {
		const [target] = await db
			.select({ id: messages.id })
			.from(messages)
			.where(and(eq(messages.id, input.replyTo), eq(messages.channelId, channelId), isNull(messages.deletedAt)))
			.limit(1);
		if (!target) throw badRequest("The message you're replying to doesn't exist");
		if (type === "default") type = "reply";
	}

	await checkSlowmode(services, access, actor.userId);

	let row: MessageRow;
	try {
		row = await db.transaction(async (tx) => {
			const mentionIds =
				mentioned.users.length === 0
					? []
					: (await tx.select({ id: users.id }).from(users).where(inArray(users.id, mentioned.users))).map((u) => u.id);

			const id = services.ids.next();
			const [inserted] = await tx
				.insert(messages)
				.values({
					id,
					channelId,
					authorId: actor.userId,
					type,
					content: input.content,
					flags: input.flags,
					replyToId: input.replyTo ?? null,
					mentions: mentionIds,
					mentionEveryone,
					embeds: input.embeds,
					components: input.components,
					metadata,
					nonce: input.nonce ?? null,
				})
				.returning();

			if (input.attachments.length > 0) {
				const linked = await tx
					.update(attachments)
					.set({ messageId: id })
					.where(
						and(
							inArray(attachments.id, input.attachments),
							eq(attachments.uploaderId, actor.userId),
							eq(attachments.channelId, channelId),
							eq(attachments.status, "uploaded"),
							isNull(attachments.messageId),
						),
					)
					.returning({ id: attachments.id });
				if (linked.length !== new Set(input.attachments).size) {
					throw badRequest("An attachment isn't uploaded yet, is already used, or belongs to another channel");
				}
			}

			await tx
				.update(channels)
				.set({ lastMessageId: sql`greatest(coalesce(${channels.lastMessageId}, 0), ${id})` })
				.where(eq(channels.id, channelId));
			// Your own message is read by you
			await tx
				.insert(readStates)
				.values({ userId: actor.userId, channelId, lastReadMessageId: id })
				.onConflictDoUpdate({
					target: [readStates.userId, readStates.channelId],
					set: { lastReadMessageId: sql`greatest(${readStates.lastReadMessageId}, ${id})`, updatedAt: new Date() },
				});
			// Notifications and bot events run after commit, as a job (an outbox)
			await enqueue(tx, "message.created", { messageId: id });
			return inserted;
		});
	} catch (error) {
		// The same nonce sent twice at once: the other request won, answer with its message
		if (input.nonce && pgCode(error) === UNIQUE_VIOLATION) {
			const existing = await messageByNonce(db, actor.userId, input.nonce);
			if (existing) return (await serializeMessages(db, [existing], actor.userId))[0];
		}
		throw error;
	}

	const [message] = await serializeMessages(db, [row], actor.userId);
	publish(services, `channel:${channelId}`, "message.create", message);
	return message;
}

/** Messages the system writes (someone joined, a pin, a rename). */
export async function insertSystemMessage(
	services: Services,
	tx: Tx,
	channelId: bigint,
	authorId: bigint,
	type: MessageType,
	metadata: Record<string, unknown>,
) {
	const id = services.ids.next();
	const json = JSON.parse(JSON.stringify(metadata, (_k, v) => (typeof v === "bigint" ? v.toString() : v)));
	const [row] = await tx.insert(messages).values({ id, channelId, authorId, type, metadata: json }).returning();
	await tx
		.update(channels)
		.set({ lastMessageId: sql`greatest(coalesce(${channels.lastMessageId}, 0), ${id})` })
		.where(eq(channels.id, channelId));
	return row;
}

async function loadMessage(tx: Tx, channelId: bigint, messageId: bigint): Promise<MessageRow> {
	const [row] = await tx
		.select()
		.from(messages)
		.where(and(eq(messages.id, messageId), eq(messages.channelId, channelId), isNull(messages.deletedAt)))
		.limit(1);
	if (!row) throw notFound("Message");
	return row;
}

export async function getMessage(services: Services, actor: Actor, channelId: bigint, messageId: bigint) {
	await requireChannelPermission(services.db, channelId, actor.userId, Permission.READ_MESSAGE_HISTORY);
	return (await serializeMessages(services.db, [await loadMessage(services.db, channelId, messageId)], actor.userId))[0];
}

/** A page of messages, newest first, keyed on message ids (no offsets). */
export async function listMessages(services: Services, actor: Actor, channelId: bigint, query: z.infer<typeof ListMessages>) {
	const db = services.db;
	await requireChannelPermission(db, channelId, actor.userId, Permission.READ_MESSAGE_HISTORY);
	const live = and(eq(messages.channelId, channelId), isNull(messages.deletedAt));

	let rows: MessageRow[];
	if (query.after !== undefined) {
		rows = await db
			.select()
			.from(messages)
			.where(and(live, gt(messages.id, query.after)))
			.orderBy(asc(messages.id))
			.limit(query.limit);
		rows.reverse();
	} else if (query.around !== undefined) {
		const half = Math.max(1, Math.floor(query.limit / 2));
		const [older, newer] = await Promise.all([
			db
				.select()
				.from(messages)
				.where(and(live, lte(messages.id, query.around)))
				.orderBy(desc(messages.id))
				.limit(query.limit - half),
			db
				.select()
				.from(messages)
				.where(and(live, gt(messages.id, query.around)))
				.orderBy(asc(messages.id))
				.limit(half),
		]);
		rows = [...newer.reverse(), ...older];
	} else {
		rows = await db
			.select()
			.from(messages)
			.where(and(live, query.before !== undefined ? lt(messages.id, query.before) : undefined))
			.orderBy(desc(messages.id))
			.limit(query.limit);
	}
	return serializeMessages(db, rows, actor.userId);
}

export async function editMessage(
	services: Services,
	actor: Actor,
	channelId: bigint,
	messageId: bigint,
	input: z.infer<typeof EditMessage>,
) {
	const db = services.db;
	const access = await requireChannelPermission(db, channelId, actor.userId, Permission.VIEW_CHANNEL);
	const row = await db.transaction(async (tx) => {
		const [current] = await tx
			.select()
			.from(messages)
			.where(and(eq(messages.id, messageId), eq(messages.channelId, channelId), isNull(messages.deletedAt)))
			.for("update")
			.limit(1);
		if (!current) throw notFound("Message");
		if (current.authorId !== actor.userId) throw forbidden("You can only edit your own messages");
		if (!["default", "reply", "command"].includes(current.type)) throw badRequest("System messages can't be edited");
		if (input.components && actor.kind !== "bot") throw forbidden("Only bots can send buttons");
		if (input.embeds?.length && !has(access.permissions, Permission.EMBED_LINKS)) throw forbidden("You can't send embeds here");

		const content = input.content ?? current.content;
		const embeds = input.embeds ?? (current.embeds as unknown[]);
		const hasFiles = (
			await tx
				.select({ id: attachments.id })
				.from(attachments)
				.where(and(eq(attachments.messageId, messageId), eq(attachments.status, "uploaded")))
				.limit(1)
		).length > 0;
		if (content.length === 0 && embeds.length === 0 && !hasFiles) throw badRequest("A message needs text, a file or an embed");

		let mentions = current.mentions;
		let mentionEveryone = current.mentionEveryone;
		if (input.content !== undefined) {
			const parsed = parseMentions(content);
			mentions =
				parsed.users.length === 0
					? []
					: (await tx.select({ id: users.id }).from(users).where(inArray(users.id, parsed.users))).map((u) => u.id);
			mentionEveryone =
				parsed.everyone && !isConversation(access.channel) && has(access.permissions, Permission.MENTION_EVERYONE);
		}
		const [updated] = await tx
			.update(messages)
			.set({
				content,
				embeds,
				components: input.components ?? current.components,
				flags: input.flags ?? current.flags,
				mentions,
				mentionEveryone,
				editedAt: new Date(),
			})
			.where(eq(messages.id, messageId))
			.returning();
		await enqueue(tx, "message.updated", { messageId });
		return updated;
	});
	const [message] = await serializeMessages(db, [row], actor.userId);
	publish(services, `channel:${channelId}`, "message.update", message);
	return message;
}

/**
 * Deleting keeps a tombstone row (so replies and ids stay valid) but wipes the
 * content, reactions, pins and files at once.
 */
export async function deleteMessage(
	services: Services,
	request: FastifyRequest | null,
	actor: Actor,
	channelId: bigint,
	messageId: bigint,
) {
	const db = services.db;
	const access = await requireChannelPermission(db, channelId, actor.userId, Permission.VIEW_CHANNEL);
	await db.transaction(async (tx) => {
		const [current] = await tx
			.select()
			.from(messages)
			.where(and(eq(messages.id, messageId), eq(messages.channelId, channelId), isNull(messages.deletedAt)))
			.for("update")
			.limit(1);
		if (!current) throw notFound("Message");
		const own = current.authorId === actor.userId;
		const moderator = !isConversation(access.channel) && has(access.permissions, Permission.MANAGE_MESSAGES);
		if (!own && !moderator) throw forbidden("You can only delete your own messages");

		await tx
			.update(messages)
			.set({ deletedAt: new Date(), content: "", embeds: [], components: [], metadata: {}, mentions: [], mentionEveryone: false })
			.where(eq(messages.id, messageId));
		await tx.delete(reactions).where(eq(reactions.messageId, messageId));
		await tx.delete(pins).where(eq(pins.messageId, messageId));
		const removed = await tx
			.update(attachments)
			.set({ status: "deleted" })
			.where(and(eq(attachments.messageId, messageId), ne(attachments.status, "deleted")))
			.returning({ id: attachments.id });
		if (removed.length > 0) await enqueue(tx, "attachments.purge", { ids: removed.map((a) => a.id) });
		await enqueue(tx, "message.deleted", { messageId, channelId });
		if (!own) {
			await audit(services, tx, request, {
				action: "message.delete",
				actorId: actor.userId,
				workspaceId: access.channel.workspaceId,
				targetType: "message",
				targetId: messageId,
				data: { channelId, authorId: current.authorId },
			});
		}
	});
	publish(services, `channel:${channelId}`, "message.delete", { id: messageId, channelId });
}

export async function listPins(services: Services, actor: Actor, channelId: bigint) {
	const db = services.db;
	await requireChannelPermission(db, channelId, actor.userId, Permission.READ_MESSAGE_HISTORY);
	const rows = await db
		.select({ message: messages, pinnedAt: pins.pinnedAt })
		.from(pins)
		.innerJoin(messages, eq(messages.id, pins.messageId))
		.where(and(eq(pins.channelId, channelId), isNull(messages.deletedAt)))
		.orderBy(desc(pins.pinnedAt));
	const serialized = await serializeMessages(
		db,
		rows.map((r) => r.message),
		actor.userId,
	);
	return serialized.map((message, i) => ({ ...message, pinnedAt: rows[i].pinnedAt }));
}

function canPin(access: ChannelAccess) {
	return isConversation(access.channel) || has(access.permissions, Permission.MANAGE_MESSAGES);
}

export async function pinMessage(services: Services, actor: Actor, channelId: bigint, messageId: bigint) {
	const db = services.db;
	const access = await requireChannelPermission(db, channelId, actor.userId, Permission.READ_MESSAGE_HISTORY);
	if (!canPin(access)) throw forbidden();
	const pinned = await db.transaction(async (tx) => {
		const message = await loadMessage(tx, channelId, messageId);
		// Lock the channel row so two pins at once can't pass the limit together
		await tx.select({ id: channels.id }).from(channels).where(eq(channels.id, channelId)).for("update");
		const [{ count }] = await tx
			.select({ count: sql<number>`count(*)::int` })
			.from(pins)
			.where(eq(pins.channelId, channelId));
		const inserted = await tx
			.insert(pins)
			.values({ channelId, messageId: message.id, pinnedBy: actor.userId })
			.onConflictDoNothing()
			.returning();
		if (inserted.length === 0) return false;
		if (count >= MAX_PINS) throw badRequest(`A channel can have at most ${MAX_PINS} pins`);
		await insertSystemMessage(services, tx, channelId, actor.userId, "pin", { messageId });
		return true;
	});
	if (pinned) publish(services, `channel:${channelId}`, "pin.add", { channelId, messageId, pinnedBy: actor.userId });
}

export async function unpinMessage(services: Services, actor: Actor, channelId: bigint, messageId: bigint) {
	const access = await requireChannelPermission(services.db, channelId, actor.userId, Permission.READ_MESSAGE_HISTORY);
	if (!canPin(access)) throw forbidden();
	const removed = await services.db
		.delete(pins)
		.where(and(eq(pins.channelId, channelId), eq(pins.messageId, messageId)))
		.returning();
	if (removed.length === 0) throw notFound("Pin");
	publish(services, `channel:${channelId}`, "pin.remove", { channelId, messageId });
}

/** Marks a channel read up to `messageId` (default: its newest message). Read states only move forward. */
export async function acknowledge(services: Services, actor: Actor, channelId: bigint, messageId?: bigint) {
	const db = services.db;
	const access = await requireChannelPermission(db, channelId, actor.userId, Permission.VIEW_CHANNEL);
	let upTo = messageId ?? access.channel.lastMessageId ?? 0n;
	if (messageId !== undefined) {
		const [exists] = await db
			.select({ id: messages.id })
			.from(messages)
			.where(and(eq(messages.id, messageId), eq(messages.channelId, channelId)))
			.limit(1);
		if (!exists) throw notFound("Message");
		upTo = exists.id;
	}
	const [state] = await db
		.insert(readStates)
		.values({ userId: actor.userId, channelId, lastReadMessageId: upTo, mentionCount: 0 })
		.onConflictDoUpdate({
			target: [readStates.userId, readStates.channelId],
			set: {
				lastReadMessageId: sql`greatest(${readStates.lastReadMessageId}, ${upTo})`,
				mentionCount: 0,
				updatedAt: new Date(),
			},
		})
		.returning();
	publish(services, `user:${actor.userId}`, "read_state.update", state);
	return state;
}
