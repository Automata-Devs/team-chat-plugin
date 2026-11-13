-- Messages in a place are end-to-end encrypted, and sealed text is longer than what it hides:
-- the server still keeps readable text to 4000 characters (messages/shapes.ts).
ALTER TABLE "messages" DROP CONSTRAINT "messages_content_length";--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_content_length" CHECK (char_length("messages"."content") <= 24000);--> statement-breakpoint
-- Places join with a proof of their secret (sha256 in hex) instead of the secret itself:
-- the stored sha256(secret) becomes sha256(proof), so every place keeps working.
UPDATE "workspaces" SET "place_secret_hash" = sha256(convert_to(encode("place_secret_hash", 'hex'), 'UTF8')) WHERE "place_secret_hash" IS NOT NULL;
