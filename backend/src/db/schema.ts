/**
 * The database schema. IDs are snowflakes (lib/snowflake.ts) in bigint columns.
 *
 * Retention: rows people care about (users, workspaces, channels, messages) are
 * never removed by a cascade. They're soft-deleted (deleted_at), and background
 * jobs purge what the retention rules say to purge, one channel at a time.
 * Cascades only remove rows that belong to a single parent and mean nothing
 * without it (sessions, reactions, overwrites, read states...).
 */
import { sql } from "drizzle-orm";
import {
	bigint,
	bigserial,
	boolean,
	check,
	customType,
	foreignKey,
	index,
	integer,
	jsonb,
	pgEnum,
	pgTable,
	primaryKey,
	text,
	timestamp,
	unique,
	uniqueIndex,
} from "drizzle-orm/pg-core";

const id = (name: string) => bigint(name, { mode: "bigint" });
const time = (name: string) => timestamp(name, { withTimezone: true, mode: "date" });
const created = () => time("created_at").notNull().defaultNow();

const bytea = customType<{ data: Buffer; driverData: Buffer }>({ dataType: () => "bytea" });
const tsvector = customType<{ data: string }>({ dataType: () => "tsvector" });

export const userStatus = pgEnum("user_status", ["active", "suspended", "deleted"]);
export const accountProvider = pgEnum("account_provider", ["roblox"]);
export const relationshipType = pgEnum("relationship_type", ["block", "mute"]);
export const channelType = pgEnum("channel_type", ["text", "category", "dm", "group_dm"]);
export const overwriteTarget = pgEnum("overwrite_target", ["role", "member"]);
export const notificationLevel = pgEnum("notification_level", ["all", "mentions", "none"]);
export const messageType = pgEnum("message_type", [
	"default",
	"reply",
	"command",
	"recipient_add",
	"recipient_remove",
	"channel_name_change",
	"pin",
	"member_join",
]);
export const attachmentStatus = pgEnum("attachment_status", ["pending", "uploaded", "deleted"]);
export const botStatus = pgEnum("bot_status", ["active", "disabled"]);
export const notificationType = pgEnum("notification_type", ["mention", "reply", "direct_message"]);

// ── Users ────────────────────────────────────────────────────────────────

export const users = pgTable(
	"users",
	{
		id: id("id").primaryKey(),
		username: text("username").notNull(),
		displayName: text("display_name"),
		avatarUrl: text("avatar_url"),
		status: userStatus("status").notNull().default("active"),
		isBot: boolean("is_bot").notNull().default(false),
		createdAt: created(),
		lastActiveAt: time("last_active_at"),
		deletedAt: time("deleted_at"),
	},
	(t) => [uniqueIndex("users_username_lower_key").on(sql`lower(${t.username})`)],
);

export const userCredentials = pgTable("user_credentials", {
	userId: id("user_id")
		.primaryKey()
		.references(() => users.id, { onDelete: "cascade" }),
	passwordHash: text("password_hash").notNull(),
	updatedAt: time("updated_at").notNull().defaultNow(),
});

export const connectedAccounts = pgTable(
	"connected_accounts",
	{
		id: id("id").primaryKey(),
		userId: id("user_id")
			.notNull()
			.references(() => users.id, { onDelete: "cascade" }),
		provider: accountProvider("provider").notNull(),
		providerUserId: text("provider_user_id").notNull(),
		providerUsername: text("provider_username"),
		createdAt: created(),
	},
	(t) => [unique("connected_accounts_provider_key").on(t.provider, t.providerUserId), index().on(t.userId)],
);

export const sessions = pgTable(
	"sessions",
	{
		id: id("id").primaryKey(),
		userId: id("user_id")
			.notNull()
			.references(() => users.id, { onDelete: "cascade" }),
		tokenHash: bytea("token_hash").notNull().unique(),
		createdAt: created(),
		expiresAt: time("expires_at").notNull(),
		lastUsedAt: time("last_used_at"),
		ip: text("ip"),
		userAgent: text("user_agent"),
		revokedAt: time("revoked_at"),
	},
	(t) => [index().on(t.userId)],
);

/** Only what a user changed from the defaults (modules/settings/defaults.ts). */
export const userSettings = pgTable("user_settings", {
	userId: id("user_id")
		.primaryKey()
		.references(() => users.id, { onDelete: "cascade" }),
	settings: jsonb("settings").notNull().default({}),
	version: integer("version").notNull().default(1),
	updatedAt: time("updated_at").notNull().defaultNow(),
});

export const relationships = pgTable(
	"relationships",
	{
		userId: id("user_id")
			.notNull()
			.references(() => users.id, { onDelete: "cascade" }),
		targetId: id("target_id")
			.notNull()
			.references(() => users.id, { onDelete: "cascade" }),
		type: relationshipType("type").notNull(),
		createdAt: created(),
	},
	(t) => [primaryKey({ columns: [t.userId, t.targetId, t.type] }), index().on(t.targetId, t.type)],
);

// ── Workspaces, roles, members ───────────────────────────────────────────

export const workspaces = pgTable(
	"workspaces",
	{
		id: id("id").primaryKey(),
		name: text("name").notNull(),
		description: text("description"),
		iconUrl: text("icon_url"),
		ownerId: id("owner_id")
			.notNull()
			.references(() => users.id, { onDelete: "restrict" }),
		settings: jsonb("settings").notNull().default({}),
		/** The Roblox place this workspace is for ("place:<PlaceId>", or "local:<guid>" while unpublished). */
		placeKey: text("place_key").unique(),
		/** SHA-256 of the secret saved in the place: knowing it shows you can open the place. */
		placeSecretHash: bytea("place_secret_hash"),
		/** The channel the place's team chat is stored in. */
		teamChatChannelId: id("team_chat_channel_id"),
		createdAt: created(),
		deletedAt: time("deleted_at"),
	},
	(t) => [index().on(t.ownerId)],
);

/** The @everyone role has the workspace's own id. */
export const roles = pgTable(
	"roles",
	{
		id: id("id").primaryKey(),
		workspaceId: id("workspace_id")
			.notNull()
			.references(() => workspaces.id, { onDelete: "cascade" }),
		name: text("name").notNull(),
		color: integer("color").notNull().default(0),
		position: integer("position").notNull().default(0),
		permissions: id("permissions").notNull().default(sql`0`),
		mentionable: boolean("mentionable").notNull().default(false),
		/** Made for a bot when it's installed; can't be edited or given to people. */
		managed: boolean("managed").notNull().default(false),
		createdAt: created(),
	},
	(t) => [index().on(t.workspaceId)],
);

export const workspaceMembers = pgTable(
	"workspace_members",
	{
		workspaceId: id("workspace_id")
			.notNull()
			.references(() => workspaces.id, { onDelete: "cascade" }),
		userId: id("user_id")
			.notNull()
			.references(() => users.id, { onDelete: "restrict" }),
		nickname: text("nickname"),
		joinedAt: time("joined_at").notNull().defaultNow(),
	},
	(t) => [primaryKey({ columns: [t.workspaceId, t.userId] }), index().on(t.userId)],
);

export const memberRoles = pgTable(
	"member_roles",
	{
		workspaceId: id("workspace_id").notNull(),
		userId: id("user_id").notNull(),
		roleId: id("role_id")
			.notNull()
			.references(() => roles.id, { onDelete: "cascade" }),
	},
	(t) => [
		primaryKey({ columns: [t.workspaceId, t.userId, t.roleId] }),
		foreignKey({
			columns: [t.workspaceId, t.userId],
			foreignColumns: [workspaceMembers.workspaceId, workspaceMembers.userId],
		}).onDelete("cascade"),
		index().on(t.roleId),
	],
);

export const invites = pgTable(
	"invites",
	{
		code: text("code").primaryKey(),
		workspaceId: id("workspace_id")
			.notNull()
			.references(() => workspaces.id, { onDelete: "cascade" }),
		inviterId: id("inviter_id")
			.notNull()
			.references(() => users.id, { onDelete: "restrict" }),
		maxUses: integer("max_uses"),
		uses: integer("uses").notNull().default(0),
		expiresAt: time("expires_at"),
		createdAt: created(),
	},
	(t) => [index().on(t.workspaceId)],
);

// ── Channels and conversations ───────────────────────────────────────────

/**
 * Workspace channels (text, category) and conversations (dm, group_dm) share
 * this table, so every message lives in one place with one ID space.
 */
export const channels = pgTable(
	"channels",
	{
		id: id("id").primaryKey(),
		type: channelType("type").notNull(),
		workspaceId: id("workspace_id").references(() => workspaces.id, { onDelete: "restrict" }),
		parentId: id("parent_id"),
		name: text("name"),
		topic: text("topic"),
		iconUrl: text("icon_url"),
		position: integer("position").notNull().default(0),
		isPrivate: boolean("is_private").notNull().default(false),
		slowmodeSeconds: integer("slowmode_seconds").notNull().default(0),
		/** Group DMs only. */
		ownerId: id("owner_id").references(() => users.id, { onDelete: "restrict" }),
		/** 1:1 DMs only: "[<workspace id>:]<smaller user id>:<larger user id>", so a pair has one DM (per place). */
		dmKey: text("dm_key").unique(),
		lastMessageId: id("last_message_id"),
		settings: jsonb("settings").notNull().default({}),
		createdAt: created(),
		deletedAt: time("deleted_at"),
	},
	(t) => [
		foreignKey({ columns: [t.parentId], foreignColumns: [t.id] }).onDelete("set null"),
		index().on(t.workspaceId),
		// Text channels and categories belong to a workspace; conversations may (a place's DMs) or may not
		check("channels_workspace_matches_type", sql`${t.type} in ('dm', 'group_dm') or ${t.workspaceId} is not null`),
		check("channels_slowmode_range", sql`${t.slowmodeSeconds} between 0 and 21600`),
	],
);

/** Conversation participants, and the members of private workspace channels. */
export const channelMembers = pgTable(
	"channel_members",
	{
		channelId: id("channel_id")
			.notNull()
			.references(() => channels.id, { onDelete: "cascade" }),
		userId: id("user_id")
			.notNull()
			.references(() => users.id, { onDelete: "restrict" }),
		joinedAt: time("joined_at").notNull().defaultNow(),
	},
	(t) => [primaryKey({ columns: [t.channelId, t.userId] }), index().on(t.userId)],
);

export const permissionOverwrites = pgTable(
	"permission_overwrites",
	{
		channelId: id("channel_id")
			.notNull()
			.references(() => channels.id, { onDelete: "cascade" }),
		targetType: overwriteTarget("target_type").notNull(),
		targetId: id("target_id").notNull(),
		allow: id("allow").notNull().default(sql`0`),
		deny: id("deny").notNull().default(sql`0`),
	},
	(t) => [primaryKey({ columns: [t.channelId, t.targetType, t.targetId] })],
);

/** A user's own settings for one channel or conversation: mute, notifications, archive. */
export const channelUserSettings = pgTable(
	"channel_user_settings",
	{
		userId: id("user_id")
			.notNull()
			.references(() => users.id, { onDelete: "cascade" }),
		channelId: id("channel_id")
			.notNull()
			.references(() => channels.id, { onDelete: "cascade" }),
		muted: boolean("muted").notNull().default(false),
		mutedUntil: time("muted_until"),
		notificationLevel: notificationLevel("notification_level"),
		archivedAt: time("archived_at"),
		updatedAt: time("updated_at").notNull().defaultNow(),
	},
	(t) => [primaryKey({ columns: [t.userId, t.channelId] })],
);

export const readStates = pgTable(
	"read_states",
	{
		userId: id("user_id")
			.notNull()
			.references(() => users.id, { onDelete: "cascade" }),
		channelId: id("channel_id")
			.notNull()
			.references(() => channels.id, { onDelete: "cascade" }),
		lastReadMessageId: id("last_read_message_id").notNull().default(sql`0`),
		mentionCount: integer("mention_count").notNull().default(0),
		updatedAt: time("updated_at").notNull().defaultNow(),
	},
	(t) => [primaryKey({ columns: [t.userId, t.channelId] })],
);

// ── Messages ─────────────────────────────────────────────────────────────

/**
 * The hot table. Read by (channel_id, id) ranges, which the snowflake order
 * makes the same as time order. docs/backend/MESSAGES.md has the path to
 * partitions or ScyllaDB once one database isn't enough.
 */
export const messages = pgTable(
	"messages",
	{
		id: id("id").primaryKey(),
		channelId: id("channel_id")
			.notNull()
			.references(() => channels.id, { onDelete: "restrict" }),
		authorId: id("author_id")
			.notNull()
			.references(() => users.id, { onDelete: "restrict" }),
		type: messageType("type").notNull().default("default"),
		content: text("content").notNull().default(""),
		flags: integer("flags").notNull().default(0),
		/** A soft reference: the message replied to may be deleted later. */
		replyToId: id("reply_to_id"),
		mentions: bigint("mentions", { mode: "bigint" }).array().notNull().default(sql`'{}'::bigint[]`),
		mentionEveryone: boolean("mention_everyone").notNull().default(false),
		embeds: jsonb("embeds").notNull().default([]),
		components: jsonb("components").notNull().default([]),
		metadata: jsonb("metadata").notNull().default({}),
		/** The client's retry key: the same nonce from the same author returns the first message. */
		nonce: text("nonce"),
		createdAt: created(),
		editedAt: time("edited_at"),
		deletedAt: time("deleted_at"),
		search: tsvector("search").generatedAlwaysAs(sql`to_tsvector('simple', content)`),
	},
	(t) => [
		index("messages_channel_id_idx").on(t.channelId, t.id.desc()),
		index("messages_author_id_idx").on(t.authorId, t.id.desc()),
		index("messages_mentions_idx").using("gin", t.mentions),
		index("messages_search_idx").using("gin", t.search),
		uniqueIndex("messages_author_nonce_key").on(t.authorId, t.nonce).where(sql`${t.nonce} is not null`),
		// Sealed (end-to-end encrypted) text is longer; readable text is kept to 4000 by the API
		check("messages_content_length", sql`char_length(${t.content}) <= 24000`),
	],
);

export const pins = pgTable(
	"pins",
	{
		channelId: id("channel_id")
			.notNull()
			.references(() => channels.id, { onDelete: "cascade" }),
		messageId: id("message_id")
			.notNull()
			.references(() => messages.id, { onDelete: "cascade" }),
		pinnedBy: id("pinned_by").references(() => users.id, { onDelete: "set null" }),
		pinnedAt: time("pinned_at").notNull().defaultNow(),
	},
	(t) => [primaryKey({ columns: [t.channelId, t.messageId] })],
);

export const reactions = pgTable(
	"reactions",
	{
		messageId: id("message_id")
			.notNull()
			.references(() => messages.id, { onDelete: "cascade" }),
		emoji: text("emoji").notNull(),
		userId: id("user_id")
			.notNull()
			.references(() => users.id, { onDelete: "cascade" }),
		createdAt: created(),
	},
	(t) => [primaryKey({ columns: [t.messageId, t.emoji, t.userId] })],
);

/** File metadata. The bytes live in S3-compatible storage under storage_key. */
export const attachments = pgTable(
	"attachments",
	{
		id: id("id").primaryKey(),
		channelId: id("channel_id")
			.notNull()
			.references(() => channels.id, { onDelete: "restrict" }),
		messageId: id("message_id").references(() => messages.id, { onDelete: "set null" }),
		uploaderId: id("uploader_id")
			.notNull()
			.references(() => users.id, { onDelete: "restrict" }),
		filename: text("filename").notNull(),
		contentType: text("content_type").notNull(),
		size: bigint("size", { mode: "number" }).notNull(),
		storageKey: text("storage_key").notNull().unique(),
		status: attachmentStatus("status").notNull().default("pending"),
		createdAt: created(),
		uploadedAt: time("uploaded_at"),
	},
	(t) => [index().on(t.messageId), index().on(t.status, t.createdAt)],
);

// ── Bots ─────────────────────────────────────────────────────────────────

/** A bot is a user (users.is_bot) plus this row. */
export const bots = pgTable(
	"bots",
	{
		userId: id("user_id")
			.primaryKey()
			.references(() => users.id, { onDelete: "cascade" }),
		ownerId: id("owner_id")
			.notNull()
			.references(() => users.id, { onDelete: "restrict" }),
		description: text("description"),
		isPublic: boolean("is_public").notNull().default(false),
		status: botStatus("status").notNull().default("active"),
		tokenHash: bytea("token_hash").notNull().unique(),
		tokenCreatedAt: time("token_created_at").notNull().defaultNow(),
		/** Where events are POSTed, signed with the signing secret. */
		eventsUrl: text("events_url"),
		events: text("events").array().notNull().default(sql`'{}'::text[]`),
		/** Encrypted (SecretBox): it must be readable to sign, so it can't be hashed. */
		signingSecret: text("signing_secret").notNull(),
		/** The permissions it asks for when installed. */
		permissions: id("permissions").notNull().default(sql`0`),
		config: jsonb("config").notNull().default({}),
		createdAt: created(),
		lastActiveAt: time("last_active_at"),
	},
	(t) => [index().on(t.ownerId)],
);

export const botCommands = pgTable(
	"bot_commands",
	{
		id: id("id").primaryKey(),
		botId: id("bot_id")
			.notNull()
			.references(() => bots.userId, { onDelete: "cascade" }),
		/** null: everywhere the bot is installed. */
		workspaceId: id("workspace_id").references(() => workspaces.id, { onDelete: "cascade" }),
		name: text("name").notNull(),
		description: text("description").notNull().default(""),
		options: jsonb("options").notNull().default([]),
		createdAt: created(),
		updatedAt: time("updated_at").notNull().defaultNow(),
	},
	(t) => [unique("bot_commands_name_key").on(t.botId, t.workspaceId, t.name).nullsNotDistinct()],
);

export const botInstallations = pgTable(
	"bot_installations",
	{
		workspaceId: id("workspace_id")
			.notNull()
			.references(() => workspaces.id, { onDelete: "cascade" }),
		botId: id("bot_id")
			.notNull()
			.references(() => bots.userId, { onDelete: "cascade" }),
		roleId: id("role_id")
			.notNull()
			.references(() => roles.id, { onDelete: "restrict" }),
		installedBy: id("installed_by")
			.notNull()
			.references(() => users.id, { onDelete: "restrict" }),
		createdAt: created(),
	},
	(t) => [primaryKey({ columns: [t.workspaceId, t.botId] }), index().on(t.botId)],
);

// ── Notifications, audit, jobs ───────────────────────────────────────────

export const notifications = pgTable(
	"notifications",
	{
		id: id("id").primaryKey(),
		userId: id("user_id")
			.notNull()
			.references(() => users.id, { onDelete: "cascade" }),
		type: notificationType("type").notNull(),
		channelId: id("channel_id")
			.notNull()
			.references(() => channels.id, { onDelete: "cascade" }),
		messageId: id("message_id").references(() => messages.id, { onDelete: "cascade" }),
		actorId: id("actor_id").references(() => users.id, { onDelete: "set null" }),
		createdAt: created(),
		readAt: time("read_at"),
	},
	(t) => [index().on(t.userId, t.id.desc()), unique("notifications_once_key").on(t.userId, t.messageId, t.type)],
);

export const auditLog = pgTable(
	"audit_log",
	{
		id: id("id").primaryKey(),
		workspaceId: id("workspace_id"),
		actorId: id("actor_id"),
		action: text("action").notNull(),
		targetType: text("target_type"),
		targetId: text("target_id"),
		data: jsonb("data").notNull().default({}),
		ip: text("ip"),
		createdAt: created(),
	},
	(t) => [index().on(t.workspaceId, t.id.desc()), index().on(t.actorId, t.id.desc())],
);

/** A job queue in Postgres, filled in the same transaction as the change it follows (an outbox). */
export const jobs = pgTable(
	"jobs",
	{
		id: bigserial("id", { mode: "bigint" }).primaryKey(),
		type: text("type").notNull(),
		payload: jsonb("payload").notNull().default({}),
		runAt: time("run_at").notNull().defaultNow(),
		attempts: integer("attempts").notNull().default(0),
		maxAttempts: integer("max_attempts").notNull().default(5),
		lockedUntil: time("locked_until"),
		lastError: text("last_error"),
		/** At most one waiting job per key (periodic jobs). */
		dedupeKey: text("dedupe_key").unique(),
		createdAt: created(),
	},
	(t) => [index("jobs_ready_idx").on(t.runAt).where(sql`${t.attempts} < ${t.maxAttempts}`)],
);
