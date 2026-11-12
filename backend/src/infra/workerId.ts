import type { Redis } from "ioredis";

const TTL_SECONDS = 60;

/**
 * Leases a snowflake worker id (0-1023) from Redis so instances never share
 * one, and keeps renewing it. Losing the lease (Redis down too long) stops the
 * process: two instances with one worker id could make the same message id.
 */
export async function leaseWorkerId(
	redis: Redis,
	onLost: (error: Error) => void,
): Promise<{ workerId: number; release(): Promise<void> }> {
	const owner = `${process.pid}-${Math.random().toString(36).slice(2)}`;
	const start = Math.floor(Math.random() * 1024);
	for (let i = 0; i < 1024; i++) {
		const workerId = (start + i) % 1024;
		const key = `snowflake:worker:${workerId}`;
		if ((await redis.set(key, owner, "EX", TTL_SECONDS, "NX")) !== "OK") continue;

		const renew = setInterval(async () => {
			try {
				const renewed = await redis.eval(
					"if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('EXPIRE', KEYS[1], ARGV[2]) else return 0 end",
					1,
					key,
					owner,
					TTL_SECONDS,
				);
				if (renewed !== 1) throw new Error(`Lost the lease on worker id ${workerId}`);
			} catch (error) {
				clearInterval(renew);
				onLost(error as Error);
			}
		}, (TTL_SECONDS / 3) * 1000);
		renew.unref();

		return {
			workerId,
			release: async () => {
				clearInterval(renew);
				await redis
					.eval("if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) else return 0 end", 1, key, owner)
					.catch(() => undefined);
			},
		};
	}
	throw new Error("All 1024 snowflake worker ids are taken");
}
