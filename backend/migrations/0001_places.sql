ALTER TABLE "channels" DROP CONSTRAINT "channels_workspace_matches_type";--> statement-breakpoint
ALTER TABLE "workspaces" ADD COLUMN "place_key" text;--> statement-breakpoint
ALTER TABLE "workspaces" ADD COLUMN "place_secret_hash" "bytea";--> statement-breakpoint
ALTER TABLE "workspaces" ADD COLUMN "team_chat_channel_id" bigint;--> statement-breakpoint
ALTER TABLE "workspaces" ADD CONSTRAINT "workspaces_place_key_unique" UNIQUE("place_key");--> statement-breakpoint
ALTER TABLE "channels" ADD CONSTRAINT "channels_workspace_matches_type" CHECK ("channels"."type" in ('dm', 'group_dm') or "channels"."workspace_id" is not null);