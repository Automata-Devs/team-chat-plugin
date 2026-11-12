import { lookup } from "node:dns/promises";
import pino from "pino";
import type { Config } from "./config.js";
import type { Services } from "./context.js";
import { connectDatabase, type DatabaseHandle } from "./db/client.js";
import { MemoryCache, RedisCache, redisClient } from "./infra/cache.js";
import { MemoryEventBus, RedisEventBus } from "./infra/events.js";
import { JobRunner } from "./infra/jobs.js";
import { s3Storage } from "./infra/storage.js";
import { leaseWorkerId } from "./infra/workerId.js";
import { registerJobs } from "./jobs.js";
import { SecretBox } from "./lib/crypto.js";
import { SnowflakeGenerator } from "./lib/snowflake.js";

export interface Runtime {
	services: Services;
	database: DatabaseHandle;
	close(): Promise<void>;
}

/** Wires up the database, Redis (if configured), storage, ids and jobs from the config. */
export async function bootstrap(config: Config, overrides: Partial<Services> = {}): Promise<Runtime> {
	const log =
		overrides.log ??
		pino({
			level: config.LOG_LEVEL,
			redact: ["req.headers.authorization", "req.headers.cookie", "*.password", "*.token", "*.signingSecret"],
		});
	const database = connectDatabase({
		url: config.DATABASE_URL,
		poolMax: config.DATABASE_POOL_MAX,
		statementTimeoutMs: config.DATABASE_STATEMENT_TIMEOUT_MS,
		onError: (error) => log.warn({ err: error }, "Idle database connection lost"),
	});

	const closers: Array<() => Promise<unknown>> = [];
	let cache = overrides.cache;
	let events = overrides.events;
	let workerId = config.WORKER_ID;

	if (config.REDIS_URL && (!cache || !events || workerId === undefined)) {
		const redis = redisClient(config.REDIS_URL);
		redis.on("error", (error) => log.warn({ err: error }, "Redis error"));
		if (workerId === undefined) {
			const lease = await leaseWorkerId(redis, (error) => {
				log.fatal({ err: error }, "Lost the snowflake worker id lease; stopping so ids stay unique");
				process.exit(1);
			});
			workerId = lease.workerId;
			closers.push(lease.release);
		}
		cache ??= new RedisCache(redis);
		events ??= new RedisEventBus(redis, redisClient(config.REDIS_URL));
	}
	cache ??= new MemoryCache();
	events ??= new MemoryEventBus();
	if (workerId === undefined) workerId = 0; // one instance without Redis

	const storage =
		overrides.storage !== undefined
			? overrides.storage
			: config.S3_BUCKET
				? s3Storage({
						endpoint: config.S3_ENDPOINT,
						region: config.S3_REGION,
						bucket: config.S3_BUCKET,
						accessKeyId: config.S3_ACCESS_KEY_ID,
						secretAccessKey: config.S3_SECRET_ACCESS_KEY,
						forcePathStyle: config.S3_FORCE_PATH_STYLE,
					})
				: null;

	const services: Services = {
		config,
		db: database.db,
		cache,
		events,
		storage,
		ids: overrides.ids ?? new SnowflakeGenerator(workerId),
		secrets: new SecretBox(config.ENCRYPTION_KEY),
		jobs: undefined as unknown as JobRunner,
		log,
		fetch: overrides.fetch ?? fetch,
		resolveHost: overrides.resolveHost ?? (async (hostname) => (await lookup(hostname, { all: true })).map((a) => a.address)),
	};
	services.jobs = registerJobs(new JobRunner(database.db, log), services);

	return {
		services,
		database,
		async close() {
			await services.jobs.stop();
			await services.events.close();
			await services.cache.close();
			for (const close of closers) await close();
			await database.close();
		},
	};
}
