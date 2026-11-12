import RedisMock from "ioredis-mock";
import { afterAll, describe, expect, test } from "vitest";
import { RedisCache } from "../src/infra/cache.js";
import { RedisEventBus } from "../src/infra/events.js";
import { leaseWorkerId } from "../src/infra/workerId.js";

// ioredis-mock runs the same commands and Lua scripts as Redis, in memory
const redis = new RedisMock() as any;
afterAll(() => redis.disconnect());

describe("Redis cache", () => {
	const cache = new RedisCache(redis);

	test("get, set with expiry, set-if-absent, delete", async () => {
		await cache.set("a", "1", 60);
		expect(await cache.get("a")).toBe("1");
		expect(await cache.setIfAbsent("a", "2", 60)).toBe(false);
		expect(await cache.setIfAbsent("b", "2", 60)).toBe(true);
		await cache.del("a");
		expect(await cache.get("a")).toBeNull();
		expect(await cache.ping()).toBe(true);
	});

	test("rate-limit counters count up inside one window", async () => {
		const first = await cache.increment("rl:test", 30);
		const second = await cache.increment("rl:test", 30);
		expect(first.count).toBe(1);
		expect(second.count).toBe(2);
		expect(second.resetIn).toBeGreaterThan(0);
		expect(second.resetIn).toBeLessThanOrEqual(30);
	});
});

describe("Redis event bus", () => {
	test("events published on one instance reach subscribers on another", async () => {
		const a = new RedisEventBus(redis, redis.duplicate());
		const b = new RedisEventBus(redis, redis.duplicate());
		const got: unknown[] = [];
		const off = await b.subscribe(["channel:1"], (_topic, event) => got.push(event));
		await a.publish("channel:1", { type: "message.create", data: { id: 5n } });
		await a.publish("channel:2", { type: "message.create", data: { id: 6n } });
		await new Promise((r) => setTimeout(r, 50));
		expect(got).toEqual([{ type: "message.create", data: { id: "5" } }]);
		await off();
		await a.publish("channel:1", { type: "message.create", data: { id: 7n } });
		await new Promise((r) => setTimeout(r, 50));
		expect(got).toHaveLength(1);
	});
});

describe("snowflake worker id lease", () => {
	test("instances get different worker ids, and a released id can be taken again", async () => {
		const leases = await Promise.all(Array.from({ length: 20 }, () => leaseWorkerId(redis, () => undefined)));
		expect(new Set(leases.map((l) => l.workerId)).size).toBe(20);
		const freed = leases[0].workerId;
		await leases[0].release();
		expect(await redis.get(`snowflake:worker:${freed}`)).toBeNull();
		for (const lease of leases.slice(1)) await lease.release();
	});
});
