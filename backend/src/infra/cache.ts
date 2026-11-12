import { Redis } from "ioredis";

/**
 * Short-lived shared state: rate limit counters, slowmode, login flows,
 * session lookups. Redis when several instances run; memory for one.
 */
export interface Cache {
	get(key: string): Promise<string | null>;
	set(key: string, value: string, ttlSeconds: number): Promise<void>;
	/** Sets only when the key doesn't exist; true when it was set. */
	setIfAbsent(key: string, value: string, ttlSeconds: number): Promise<boolean>;
	del(key: string): Promise<void>;
	/** Adds 1 and returns the new count and the seconds left in the window (fixed-window counter). */
	increment(key: string, windowSeconds: number): Promise<{ count: number; resetIn: number }>;
	ping(): Promise<boolean>;
	close(): Promise<void>;
}

export class MemoryCache implements Cache {
	private readonly entries = new Map<string, { value: string; expiresAt: number }>();
	private readonly sweeper = setInterval(() => this.sweep(), 60_000).unref();

	private live(key: string) {
		const entry = this.entries.get(key);
		if (entry && entry.expiresAt <= Date.now()) {
			this.entries.delete(key);
			return undefined;
		}
		return entry;
	}

	private sweep() {
		const now = Date.now();
		for (const [key, entry] of this.entries) if (entry.expiresAt <= now) this.entries.delete(key);
	}

	async get(key: string) {
		return this.live(key)?.value ?? null;
	}

	async set(key: string, value: string, ttlSeconds: number) {
		this.entries.set(key, { value, expiresAt: Date.now() + ttlSeconds * 1000 });
	}

	async setIfAbsent(key: string, value: string, ttlSeconds: number) {
		if (this.live(key)) return false;
		await this.set(key, value, ttlSeconds);
		return true;
	}

	async del(key: string) {
		this.entries.delete(key);
	}

	async increment(key: string, windowSeconds: number) {
		const entry = this.live(key);
		if (!entry) {
			this.entries.set(key, { value: "1", expiresAt: Date.now() + windowSeconds * 1000 });
			return { count: 1, resetIn: windowSeconds };
		}
		entry.value = String(Number(entry.value) + 1);
		return { count: Number(entry.value), resetIn: Math.max(1, Math.ceil((entry.expiresAt - Date.now()) / 1000)) };
	}

	async ping() {
		return true;
	}

	async close() {
		clearInterval(this.sweeper);
		this.entries.clear();
	}
}

const INCREMENT = `
local count = redis.call('INCR', KEYS[1])
if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
local ttl = redis.call('TTL', KEYS[1])
if ttl < 0 then redis.call('EXPIRE', KEYS[1], ARGV[1]); ttl = tonumber(ARGV[1]) end
return {count, ttl}`;

export class RedisCache implements Cache {
	constructor(readonly redis: Redis) {}

	get(key: string) {
		return this.redis.get(key);
	}

	async set(key: string, value: string, ttlSeconds: number) {
		await this.redis.set(key, value, "EX", ttlSeconds);
	}

	async setIfAbsent(key: string, value: string, ttlSeconds: number) {
		return (await this.redis.set(key, value, "EX", ttlSeconds, "NX")) === "OK";
	}

	async del(key: string) {
		await this.redis.del(key);
	}

	async increment(key: string, windowSeconds: number) {
		const [count, ttl] = (await this.redis.eval(INCREMENT, 1, key, windowSeconds)) as [number, number];
		return { count, resetIn: Math.max(1, ttl) };
	}

	async ping() {
		try {
			return (await this.redis.ping()) === "PONG";
		} catch {
			return false;
		}
	}

	async close() {
		await this.redis.quit().catch(() => this.redis.disconnect());
	}
}

export function redisClient(url: string): Redis {
	return new Redis(url, { maxRetriesPerRequest: 2, enableOfflineQueue: false });
}
