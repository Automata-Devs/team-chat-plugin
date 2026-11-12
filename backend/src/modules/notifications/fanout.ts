import { and, eq, inArray, sql } from "drizzle-orm";
import type { Services } from "../../context.js";
import {
	channelMembers,
	channels,
	channelUserSettings,
	messages,
	notifications,
	readStates,
	relationships,
	userSettings,
	workspaceMembers,
} from "../../db/schema.js";
import { isConversation, readersOf } from "../access.js";
import { serializeMessages } from "../messages/service.js";
import { MessageFlags } from "../messages/shapes.js";
import { withDefaults } from "../settings/defaults.js";
import { publish } from "../shared.js";

const MAX_EVERYONE_FANOUT = 5000;

type Kind = "mention" | "reply" | "direct_message";

/**
 * Runs after a message is committed (job "message.created"): writes the
 * notification inbox, bumps mention badges and pushes live notifications.
 * Safe to retry: a notification is unique per user, message and kind.
 */
export async function fanOutMessage(services: Services, messageId: bigint) {
	const db = services.db;
	const [row] = await db
		.select({ message: messages, channel: channels })
		.from(messages)
		.innerJoin(channels, eq(channels.id, messages.channelId))
		.where(eq(messages.id, messageId));
	if (!row || row.message.deletedAt || row.channel.deletedAt) return null;
	const { message, channel } = row;
	const result = { workspaceId: channel.workspaceId, channelId: channel.id, authorId: message.authorId, message };
	if (message.flags & MessageFlags.SUPPRESS_NOTIFICATIONS) return result;

	// Who could be notified, and why (the first reason wins)
	const reasons = new Map<bigint, Kind>();
	if (isConversation(channel)) {
		const members = await db.select({ userId: channelMembers.userId }).from(channelMembers).where(eq(channelMembers.channelId, channel.id));
		for (const { userId } of members) {
			reasons.set(userId, channel.type === "group_dm" && message.mentions.includes(userId) ? "mention" : "direct_message");
		}
	} else {
		for (const userId of message.mentions) reasons.set(userId, "mention");
		if (message.replyToId) {
			const [replied] = await db.select({ authorId: messages.authorId }).from(messages).where(eq(messages.id, message.replyToId));
			if (replied && !reasons.has(replied.authorId)) reasons.set(replied.authorId, "reply");
		}
		if (message.mentionEveryone) {
			const members = await db
				.select({ userId: workspaceMembers.userId })
				.from(workspaceMembers)
				.where(eq(workspaceMembers.workspaceId, channel.workspaceId!))
				.limit(MAX_EVERYONE_FANOUT);
			for (const { userId } of members) if (!reasons.has(userId)) reasons.set(userId, "mention");
		}
	}
	reasons.delete(message.authorId);
	if (reasons.size === 0) return result;

	// Only people who can read the channel and haven't blocked or muted the author
	const candidates = [...(await readersOf(db, channel, [...reasons.keys()]))];
	if (candidates.length === 0) return result;
	const [settingsRows, channelSettings, ignored] = await Promise.all([
		db.select().from(userSettings).where(inArray(userSettings.userId, candidates)),
		db
			.select()
			.from(channelUserSettings)
			.where(and(eq(channelUserSettings.channelId, channel.id), inArray(channelUserSettings.userId, candidates))),
		db
			.select({ userId: relationships.userId })
			.from(relationships)
			.where(and(eq(relationships.targetId, message.authorId), inArray(relationships.userId, candidates))),
	]);
	const ignoredBy = new Set(ignored.map((r) => r.userId));
	const prefsOf = new Map(settingsRows.map((r) => [r.userId, withDefaults(r.settings).notifications]));
	const defaults = withDefaults(undefined).notifications;
	const channelSettingsOf = new Map(channelSettings.map((r) => [r.userId, r]));

	const rows: Array<typeof notifications.$inferInsert> = [];
	for (const userId of candidates) {
		if (ignoredBy.has(userId)) continue;
		const kind = reasons.get(userId)!;
		const prefs = prefsOf.get(userId) ?? defaults;
		const viaEveryone = message.mentionEveryone && !message.mentions.includes(userId);
		if (kind === "direct_message" && !prefs.directMessages) continue;
		if (kind === "mention" && !(viaEveryone ? prefs.everyone : prefs.mentions)) continue;
		if (kind === "reply" && !prefs.replies) continue;
		rows.push({ id: services.ids.next(), userId, type: kind, channelId: channel.id, messageId: message.id, actorId: message.authorId });
	}
	if (rows.length === 0) return result;

	const inserted = await db.transaction(async (tx) => {
		const created = await tx.insert(notifications).values(rows).onConflictDoNothing().returning();
		if (created.length > 0) {
			await tx
				.insert(readStates)
				.values(created.map((n) => ({ userId: n.userId, channelId: channel.id, mentionCount: 1 })))
				.onConflictDoUpdate({
					target: [readStates.userId, readStates.channelId],
					set: { mentionCount: sql`${readStates.mentionCount} + 1`, updatedAt: new Date() },
				});
		}
		return created;
	});

	// Live pushes respect mutes and notification levels; the inbox keeps everything
	const now = new Date();
	const pushTo = inserted.filter((n) => {
		const own = channelSettingsOf.get(n.userId);
		if (own?.muted && (!own.mutedUntil || own.mutedUntil > now)) return false;
		const level = own?.notificationLevel ?? (isConversation(channel) ? "all" : (prefsOf.get(n.userId) ?? defaults).defaultLevel);
		return level === "all" || (level === "mentions" && n.type !== "direct_message");
	});
	if (pushTo.length > 0) {
		const [preview] = await serializeMessages(db, [message], message.authorId);
		for (const n of pushTo) publish(services, `user:${n.userId}`, "notification.create", { notification: n, message: preview });
	}
	return result;
}
