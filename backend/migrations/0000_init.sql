CREATE TYPE "public"."account_provider" AS ENUM('roblox');--> statement-breakpoint
CREATE TYPE "public"."attachment_status" AS ENUM('pending', 'uploaded', 'deleted');--> statement-breakpoint
CREATE TYPE "public"."bot_status" AS ENUM('active', 'disabled');--> statement-breakpoint
CREATE TYPE "public"."channel_type" AS ENUM('text', 'category', 'dm', 'group_dm');--> statement-breakpoint
CREATE TYPE "public"."message_type" AS ENUM('default', 'reply', 'command', 'recipient_add', 'recipient_remove', 'channel_name_change', 'pin', 'member_join');--> statement-breakpoint
CREATE TYPE "public"."notification_level" AS ENUM('all', 'mentions', 'none');--> statement-breakpoint
CREATE TYPE "public"."notification_type" AS ENUM('mention', 'reply', 'direct_message');--> statement-breakpoint
CREATE TYPE "public"."overwrite_target" AS ENUM('role', 'member');--> statement-breakpoint
CREATE TYPE "public"."relationship_type" AS ENUM('block', 'mute');--> statement-breakpoint
CREATE TYPE "public"."user_status" AS ENUM('active', 'suspended', 'deleted');--> statement-breakpoint
CREATE TABLE "attachments" (
	"id" bigint PRIMARY KEY NOT NULL,
	"channel_id" bigint NOT NULL,
	"message_id" bigint,
	"uploader_id" bigint NOT NULL,
	"filename" text NOT NULL,
	"content_type" text NOT NULL,
	"size" bigint NOT NULL,
	"storage_key" text NOT NULL,
	"status" "attachment_status" DEFAULT 'pending' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"uploaded_at" timestamp with time zone,
	CONSTRAINT "attachments_storage_key_unique" UNIQUE("storage_key")
);
--> statement-breakpoint
CREATE TABLE "audit_log" (
	"id" bigint PRIMARY KEY NOT NULL,
	"workspace_id" bigint,
	"actor_id" bigint,
	"action" text NOT NULL,
	"target_type" text,
	"target_id" text,
	"data" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"ip" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "bot_commands" (
	"id" bigint PRIMARY KEY NOT NULL,
	"bot_id" bigint NOT NULL,
	"workspace_id" bigint,
	"name" text NOT NULL,
	"description" text DEFAULT '' NOT NULL,
	"options" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "bot_commands_name_key" UNIQUE NULLS NOT DISTINCT("bot_id","workspace_id","name")
);
--> statement-breakpoint
CREATE TABLE "bot_installations" (
	"workspace_id" bigint NOT NULL,
	"bot_id" bigint NOT NULL,
	"role_id" bigint NOT NULL,
	"installed_by" bigint NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "bot_installations_workspace_id_bot_id_pk" PRIMARY KEY("workspace_id","bot_id")
);
--> statement-breakpoint
CREATE TABLE "bots" (
	"user_id" bigint PRIMARY KEY NOT NULL,
	"owner_id" bigint NOT NULL,
	"description" text,
	"is_public" boolean DEFAULT false NOT NULL,
	"status" "bot_status" DEFAULT 'active' NOT NULL,
	"token_hash" "bytea" NOT NULL,
	"token_created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"events_url" text,
	"events" text[] DEFAULT '{}'::text[] NOT NULL,
	"signing_secret" text NOT NULL,
	"permissions" bigint DEFAULT 0 NOT NULL,
	"config" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_active_at" timestamp with time zone,
	CONSTRAINT "bots_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
CREATE TABLE "channel_members" (
	"channel_id" bigint NOT NULL,
	"user_id" bigint NOT NULL,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "channel_members_channel_id_user_id_pk" PRIMARY KEY("channel_id","user_id")
);
--> statement-breakpoint
CREATE TABLE "channel_user_settings" (
	"user_id" bigint NOT NULL,
	"channel_id" bigint NOT NULL,
	"muted" boolean DEFAULT false NOT NULL,
	"muted_until" timestamp with time zone,
	"notification_level" "notification_level",
	"archived_at" timestamp with time zone,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "channel_user_settings_user_id_channel_id_pk" PRIMARY KEY("user_id","channel_id")
);
--> statement-breakpoint
CREATE TABLE "channels" (
	"id" bigint PRIMARY KEY NOT NULL,
	"type" "channel_type" NOT NULL,
	"workspace_id" bigint,
	"parent_id" bigint,
	"name" text,
	"topic" text,
	"icon_url" text,
	"position" integer DEFAULT 0 NOT NULL,
	"is_private" boolean DEFAULT false NOT NULL,
	"slowmode_seconds" integer DEFAULT 0 NOT NULL,
	"owner_id" bigint,
	"dm_key" text,
	"last_message_id" bigint,
	"settings" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "channels_dm_key_unique" UNIQUE("dm_key"),
	CONSTRAINT "channels_workspace_matches_type" CHECK (("channels"."type" in ('dm', 'group_dm')) = ("channels"."workspace_id" is null)),
	CONSTRAINT "channels_slowmode_range" CHECK ("channels"."slowmode_seconds" between 0 and 21600)
);
--> statement-breakpoint
CREATE TABLE "connected_accounts" (
	"id" bigint PRIMARY KEY NOT NULL,
	"user_id" bigint NOT NULL,
	"provider" "account_provider" NOT NULL,
	"provider_user_id" text NOT NULL,
	"provider_username" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "connected_accounts_provider_key" UNIQUE("provider","provider_user_id")
);
--> statement-breakpoint
CREATE TABLE "invites" (
	"code" text PRIMARY KEY NOT NULL,
	"workspace_id" bigint NOT NULL,
	"inviter_id" bigint NOT NULL,
	"max_uses" integer,
	"uses" integer DEFAULT 0 NOT NULL,
	"expires_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "jobs" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"type" text NOT NULL,
	"payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"run_at" timestamp with time zone DEFAULT now() NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"max_attempts" integer DEFAULT 5 NOT NULL,
	"locked_until" timestamp with time zone,
	"last_error" text,
	"dedupe_key" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "jobs_dedupe_key_unique" UNIQUE("dedupe_key")
);
--> statement-breakpoint
CREATE TABLE "member_roles" (
	"workspace_id" bigint NOT NULL,
	"user_id" bigint NOT NULL,
	"role_id" bigint NOT NULL,
	CONSTRAINT "member_roles_workspace_id_user_id_role_id_pk" PRIMARY KEY("workspace_id","user_id","role_id")
);
--> statement-breakpoint
CREATE TABLE "messages" (
	"id" bigint PRIMARY KEY NOT NULL,
	"channel_id" bigint NOT NULL,
	"author_id" bigint NOT NULL,
	"type" "message_type" DEFAULT 'default' NOT NULL,
	"content" text DEFAULT '' NOT NULL,
	"flags" integer DEFAULT 0 NOT NULL,
	"reply_to_id" bigint,
	"mentions" bigint[] DEFAULT '{}'::bigint[] NOT NULL,
	"mention_everyone" boolean DEFAULT false NOT NULL,
	"embeds" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"components" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"nonce" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"edited_at" timestamp with time zone,
	"deleted_at" timestamp with time zone,
	"search" "tsvector" GENERATED ALWAYS AS (to_tsvector('simple', content)) STORED,
	CONSTRAINT "messages_content_length" CHECK (char_length("messages"."content") <= 4000)
);
--> statement-breakpoint
CREATE TABLE "notifications" (
	"id" bigint PRIMARY KEY NOT NULL,
	"user_id" bigint NOT NULL,
	"type" "notification_type" NOT NULL,
	"channel_id" bigint NOT NULL,
	"message_id" bigint,
	"actor_id" bigint,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"read_at" timestamp with time zone,
	CONSTRAINT "notifications_once_key" UNIQUE("user_id","message_id","type")
);
--> statement-breakpoint
CREATE TABLE "permission_overwrites" (
	"channel_id" bigint NOT NULL,
	"target_type" "overwrite_target" NOT NULL,
	"target_id" bigint NOT NULL,
	"allow" bigint DEFAULT 0 NOT NULL,
	"deny" bigint DEFAULT 0 NOT NULL,
	CONSTRAINT "permission_overwrites_channel_id_target_type_target_id_pk" PRIMARY KEY("channel_id","target_type","target_id")
);
--> statement-breakpoint
CREATE TABLE "pins" (
	"channel_id" bigint NOT NULL,
	"message_id" bigint NOT NULL,
	"pinned_by" bigint,
	"pinned_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "pins_channel_id_message_id_pk" PRIMARY KEY("channel_id","message_id")
);
--> statement-breakpoint
CREATE TABLE "reactions" (
	"message_id" bigint NOT NULL,
	"emoji" text NOT NULL,
	"user_id" bigint NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "reactions_message_id_emoji_user_id_pk" PRIMARY KEY("message_id","emoji","user_id")
);
--> statement-breakpoint
CREATE TABLE "read_states" (
	"user_id" bigint NOT NULL,
	"channel_id" bigint NOT NULL,
	"last_read_message_id" bigint DEFAULT 0 NOT NULL,
	"mention_count" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "read_states_user_id_channel_id_pk" PRIMARY KEY("user_id","channel_id")
);
--> statement-breakpoint
CREATE TABLE "relationships" (
	"user_id" bigint NOT NULL,
	"target_id" bigint NOT NULL,
	"type" "relationship_type" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "relationships_user_id_target_id_type_pk" PRIMARY KEY("user_id","target_id","type")
);
--> statement-breakpoint
CREATE TABLE "roles" (
	"id" bigint PRIMARY KEY NOT NULL,
	"workspace_id" bigint NOT NULL,
	"name" text NOT NULL,
	"color" integer DEFAULT 0 NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	"permissions" bigint DEFAULT 0 NOT NULL,
	"mentionable" boolean DEFAULT false NOT NULL,
	"managed" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sessions" (
	"id" bigint PRIMARY KEY NOT NULL,
	"user_id" bigint NOT NULL,
	"token_hash" "bytea" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"last_used_at" timestamp with time zone,
	"ip" text,
	"user_agent" text,
	"revoked_at" timestamp with time zone,
	CONSTRAINT "sessions_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
CREATE TABLE "user_credentials" (
	"user_id" bigint PRIMARY KEY NOT NULL,
	"password_hash" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "user_settings" (
	"user_id" bigint PRIMARY KEY NOT NULL,
	"settings" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" bigint PRIMARY KEY NOT NULL,
	"username" text NOT NULL,
	"display_name" text,
	"avatar_url" text,
	"status" "user_status" DEFAULT 'active' NOT NULL,
	"is_bot" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_active_at" timestamp with time zone,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "workspace_members" (
	"workspace_id" bigint NOT NULL,
	"user_id" bigint NOT NULL,
	"nickname" text,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "workspace_members_workspace_id_user_id_pk" PRIMARY KEY("workspace_id","user_id")
);
--> statement-breakpoint
CREATE TABLE "workspaces" (
	"id" bigint PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"description" text,
	"icon_url" text,
	"owner_id" bigint NOT NULL,
	"settings" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "attachments" ADD CONSTRAINT "attachments_channel_id_channels_id_fk" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "attachments" ADD CONSTRAINT "attachments_message_id_messages_id_fk" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "attachments" ADD CONSTRAINT "attachments_uploader_id_users_id_fk" FOREIGN KEY ("uploader_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bot_commands" ADD CONSTRAINT "bot_commands_bot_id_bots_user_id_fk" FOREIGN KEY ("bot_id") REFERENCES "public"."bots"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bot_commands" ADD CONSTRAINT "bot_commands_workspace_id_workspaces_id_fk" FOREIGN KEY ("workspace_id") REFERENCES "public"."workspaces"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bot_installations" ADD CONSTRAINT "bot_installations_workspace_id_workspaces_id_fk" FOREIGN KEY ("workspace_id") REFERENCES "public"."workspaces"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bot_installations" ADD CONSTRAINT "bot_installations_bot_id_bots_user_id_fk" FOREIGN KEY ("bot_id") REFERENCES "public"."bots"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bot_installations" ADD CONSTRAINT "bot_installations_role_id_roles_id_fk" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bot_installations" ADD CONSTRAINT "bot_installations_installed_by_users_id_fk" FOREIGN KEY ("installed_by") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bots" ADD CONSTRAINT "bots_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bots" ADD CONSTRAINT "bots_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "channel_members" ADD CONSTRAINT "channel_members_channel_id_channels_id_fk" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "channel_members" ADD CONSTRAINT "channel_members_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "channel_user_settings" ADD CONSTRAINT "channel_user_settings_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "channel_user_settings" ADD CONSTRAINT "channel_user_settings_channel_id_channels_id_fk" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "channels" ADD CONSTRAINT "channels_workspace_id_workspaces_id_fk" FOREIGN KEY ("workspace_id") REFERENCES "public"."workspaces"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "channels" ADD CONSTRAINT "channels_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "channels" ADD CONSTRAINT "channels_parent_id_channels_id_fk" FOREIGN KEY ("parent_id") REFERENCES "public"."channels"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "connected_accounts" ADD CONSTRAINT "connected_accounts_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "invites" ADD CONSTRAINT "invites_workspace_id_workspaces_id_fk" FOREIGN KEY ("workspace_id") REFERENCES "public"."workspaces"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "invites" ADD CONSTRAINT "invites_inviter_id_users_id_fk" FOREIGN KEY ("inviter_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "member_roles" ADD CONSTRAINT "member_roles_role_id_roles_id_fk" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "member_roles" ADD CONSTRAINT "member_roles_workspace_id_user_id_workspace_members_workspace_id_user_id_fk" FOREIGN KEY ("workspace_id","user_id") REFERENCES "public"."workspace_members"("workspace_id","user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_channel_id_channels_id_fk" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_author_id_users_id_fk" FOREIGN KEY ("author_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_channel_id_channels_id_fk" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_message_id_messages_id_fk" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_actor_id_users_id_fk" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "permission_overwrites" ADD CONSTRAINT "permission_overwrites_channel_id_channels_id_fk" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pins" ADD CONSTRAINT "pins_channel_id_channels_id_fk" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pins" ADD CONSTRAINT "pins_message_id_messages_id_fk" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pins" ADD CONSTRAINT "pins_pinned_by_users_id_fk" FOREIGN KEY ("pinned_by") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "reactions" ADD CONSTRAINT "reactions_message_id_messages_id_fk" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "reactions" ADD CONSTRAINT "reactions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "read_states" ADD CONSTRAINT "read_states_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "read_states" ADD CONSTRAINT "read_states_channel_id_channels_id_fk" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "relationships" ADD CONSTRAINT "relationships_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "relationships" ADD CONSTRAINT "relationships_target_id_users_id_fk" FOREIGN KEY ("target_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "roles" ADD CONSTRAINT "roles_workspace_id_workspaces_id_fk" FOREIGN KEY ("workspace_id") REFERENCES "public"."workspaces"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sessions" ADD CONSTRAINT "sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_credentials" ADD CONSTRAINT "user_credentials_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_settings" ADD CONSTRAINT "user_settings_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workspace_members" ADD CONSTRAINT "workspace_members_workspace_id_workspaces_id_fk" FOREIGN KEY ("workspace_id") REFERENCES "public"."workspaces"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workspace_members" ADD CONSTRAINT "workspace_members_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workspaces" ADD CONSTRAINT "workspaces_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "attachments_message_id_index" ON "attachments" USING btree ("message_id");--> statement-breakpoint
CREATE INDEX "attachments_status_created_at_index" ON "attachments" USING btree ("status","created_at");--> statement-breakpoint
CREATE INDEX "audit_log_workspace_id_id_index" ON "audit_log" USING btree ("workspace_id","id" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "audit_log_actor_id_id_index" ON "audit_log" USING btree ("actor_id","id" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "bot_installations_bot_id_index" ON "bot_installations" USING btree ("bot_id");--> statement-breakpoint
CREATE INDEX "bots_owner_id_index" ON "bots" USING btree ("owner_id");--> statement-breakpoint
CREATE INDEX "channel_members_user_id_index" ON "channel_members" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "channels_workspace_id_index" ON "channels" USING btree ("workspace_id");--> statement-breakpoint
CREATE INDEX "connected_accounts_user_id_index" ON "connected_accounts" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "invites_workspace_id_index" ON "invites" USING btree ("workspace_id");--> statement-breakpoint
CREATE INDEX "jobs_ready_idx" ON "jobs" USING btree ("run_at") WHERE "jobs"."attempts" < "jobs"."max_attempts";--> statement-breakpoint
CREATE INDEX "member_roles_role_id_index" ON "member_roles" USING btree ("role_id");--> statement-breakpoint
CREATE INDEX "messages_channel_id_idx" ON "messages" USING btree ("channel_id","id" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "messages_author_id_idx" ON "messages" USING btree ("author_id","id" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "messages_mentions_idx" ON "messages" USING gin ("mentions");--> statement-breakpoint
CREATE INDEX "messages_search_idx" ON "messages" USING gin ("search");--> statement-breakpoint
CREATE UNIQUE INDEX "messages_author_nonce_key" ON "messages" USING btree ("author_id","nonce") WHERE "messages"."nonce" is not null;--> statement-breakpoint
CREATE INDEX "notifications_user_id_id_index" ON "notifications" USING btree ("user_id","id" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "relationships_target_id_type_index" ON "relationships" USING btree ("target_id","type");--> statement-breakpoint
CREATE INDEX "roles_workspace_id_index" ON "roles" USING btree ("workspace_id");--> statement-breakpoint
CREATE INDEX "sessions_user_id_index" ON "sessions" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "users_username_lower_key" ON "users" USING btree (lower("username"));--> statement-breakpoint
CREATE INDEX "workspace_members_user_id_index" ON "workspace_members" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "workspaces_owner_id_index" ON "workspaces" USING btree ("owner_id");