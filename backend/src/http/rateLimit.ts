import type { FastifyReply } from "fastify";
import type { Cache } from "../infra/cache.js";
import { AppError } from "../lib/errors.js";

export interface Limit {
	/** Counted separately from other buckets. */
	bucket: string;
	max: number;
	windowSeconds: number;
}

export const LIMITS = {
	user: { bucket: "global", max: 300, windowSeconds: 60 },
	bot: { bucket: "global-bot", max: 600, windowSeconds: 60 },
	anonymous: { bucket: "global-ip", max: 120, windowSeconds: 60 },
	auth: { bucket: "auth", max: 10, windowSeconds: 60 },
	signup: { bucket: "signup", max: 5, windowSeconds: 3600 },
	sendMessage: { bucket: "send", max: 10, windowSeconds: 10 },
	upload: { bucket: "upload", max: 20, windowSeconds: 60 },
	search: { bucket: "search", max: 30, windowSeconds: 60 },
	botAdmin: { bucket: "bot-admin", max: 20, windowSeconds: 300 },
} satisfies Record<string, Limit>;

/** Counts one request against `limit` for `subject` (a user id or an IP). Throws 429 when over. */
export async function hit(cache: Cache, limit: Limit, subject: string, reply?: FastifyReply, scale = 1): Promise<void> {
	const max = Math.max(1, Math.floor(limit.max * scale));
	const { count, resetIn } = await cache.increment(`rl:${limit.bucket}:${subject}`, limit.windowSeconds);
	if (reply) {
		reply.header("X-RateLimit-Limit", max);
		reply.header("X-RateLimit-Remaining", Math.max(0, max - count));
		reply.header("X-RateLimit-Reset-After", resetIn);
		reply.header("X-RateLimit-Bucket", limit.bucket);
	}
	if (count > max) {
		reply?.header("Retry-After", resetIn);
		throw new AppError(429, "rate_limited", "Too many requests, slow down", { retryAfter: resetIn, bucket: limit.bucket });
	}
}
