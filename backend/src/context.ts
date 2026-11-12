import type { FastifyBaseLogger } from "fastify";
import type { Config } from "./config.js";
import type { Database } from "./db/client.js";
import type { Cache } from "./infra/cache.js";
import type { EventBus } from "./infra/events.js";
import type { JobRunner } from "./infra/jobs.js";
import type { ObjectStorage } from "./infra/storage.js";
import type { SecretBox } from "./lib/crypto.js";
import type { SnowflakeGenerator } from "./lib/snowflake.js";

/** Everything a module needs, built once in main.ts (or by the tests). */
export interface Services {
	config: Config;
	db: Database;
	cache: Cache;
	events: EventBus;
	storage: ObjectStorage | null;
	ids: SnowflakeGenerator;
	secrets: SecretBox;
	jobs: JobRunner;
	log: FastifyBaseLogger;
	/** Outgoing HTTP (Roblox OAuth, bot events). Swapped out in tests. */
	fetch: typeof fetch;
	/** Resolves a hostname for the bot URL check. Swapped out in tests. */
	resolveHost: (hostname: string) => Promise<string[]>;
}

export interface Actor {
	userId: bigint;
	kind: "user" | "bot";
	sessionId?: bigint;
}
