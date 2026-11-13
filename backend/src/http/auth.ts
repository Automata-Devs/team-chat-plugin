import { and, eq, gt, isNull, sql } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import type { Actor, Services } from "../context.js";
import { bots, sessions, users } from "../db/schema.js";
import { sha256 } from "../lib/crypto.js";
import { forbidden, unauthorized } from "../lib/errors.js";

const LOOKUP_CACHE_SECONDS = 30;
const TOUCH_EVERY_SECONDS = 300;

const sessionKey = (hash: Buffer) => `session:${hash.toString("hex")}`;
const botKey = (hash: Buffer) => `bot-token:${hash.toString("hex")}`;

/**
 * Reads the Authorization header:
 *   Bearer <session token>   a person, signed in with a password or Roblox
 *   Bot <bot token>          a bot
 * Tokens are only ever stored as SHA-256 hashes.
 */
export async function authenticate(services: Services, request: FastifyRequest): Promise<Actor | null> {
	const header = request.headers.authorization;
	if (!header) return null;
	const [scheme, token] = header.split(" ", 2);
	if (!token || token.length > 512) throw unauthorized("Malformed Authorization header");
	if (scheme === "Bearer") return sessionActor(services, token);
	if (scheme === "Bot") return botActor(services, token);
	throw unauthorized("Use Bearer <session token> or Bot <bot token>");
}

async function sessionActor(services: Services, token: string): Promise<Actor> {
	const hash = sha256(token);
	const cached = await services.cache.get(sessionKey(hash));
	if (cached === "invalid") throw unauthorized("Session expired or signed out");
	if (cached) {
		const [userId, sessionId] = cached.split(":");
		return { kind: "user", userId: BigInt(userId), sessionId: BigInt(sessionId) };
	}

	const [row] = await services.db
		.select({ sessionId: sessions.id, userId: sessions.userId, status: users.status })
		.from(sessions)
		.innerJoin(users, eq(users.id, sessions.userId))
		.where(and(eq(sessions.tokenHash, hash), isNull(sessions.revokedAt), gt(sessions.expiresAt, sql`now()`)))
		.limit(1);

	if (!row || row.status !== "active") {
		await services.cache.set(sessionKey(hash), "invalid", LOOKUP_CACHE_SECONDS);
		throw unauthorized("Session expired or signed out");
	}
	await services.cache.set(sessionKey(hash), `${row.userId}:${row.sessionId}`, LOOKUP_CACHE_SECONDS);

	if (await services.cache.setIfAbsent(`touch:session:${row.sessionId}`, "1", TOUCH_EVERY_SECONDS)) {
		// A session in use keeps going: it only ends after SESSION_TTL_DAYS without use (or signing out)
		const now = new Date();
		const expiresAt = new Date(now.getTime() + services.config.SESSION_TTL_DAYS * 86_400_000);
		await services.db.update(sessions).set({ lastUsedAt: now, expiresAt }).where(eq(sessions.id, row.sessionId));
		await services.db.update(users).set({ lastActiveAt: new Date() }).where(eq(users.id, row.userId));
	}
	return { kind: "user", userId: row.userId, sessionId: row.sessionId };
}

async function botActor(services: Services, token: string): Promise<Actor> {
	const hash = sha256(token);
	const cached = await services.cache.get(botKey(hash));
	if (cached === "invalid") throw unauthorized("Invalid bot token");
	if (cached === "disabled") throw forbidden("This bot is disabled");
	if (cached) return { kind: "bot", userId: BigInt(cached) };

	const [row] = await services.db
		.select({ userId: bots.userId, status: bots.status, userStatus: users.status })
		.from(bots)
		.innerJoin(users, eq(users.id, bots.userId))
		.where(eq(bots.tokenHash, hash))
		.limit(1);
	if (!row || row.userStatus !== "active") {
		await services.cache.set(botKey(hash), "invalid", LOOKUP_CACHE_SECONDS);
		throw unauthorized("Invalid bot token");
	}
	if (row.status !== "active") {
		await services.cache.set(botKey(hash), "disabled", LOOKUP_CACHE_SECONDS);
		throw forbidden("This bot is disabled");
	}
	await services.cache.set(botKey(hash), String(row.userId), LOOKUP_CACHE_SECONDS);

	if (await services.cache.setIfAbsent(`touch:bot:${row.userId}`, "1", 60)) {
		await services.db.update(bots).set({ lastActiveAt: new Date() }).where(eq(bots.userId, row.userId));
	}
	return { kind: "bot", userId: row.userId };
}

/** Drops cached lookups, so a revoked token or disabled bot stops working at once. */
export async function forgetToken(services: Services, tokenHash: Buffer, kind: "session" | "bot"): Promise<void> {
	await services.cache.del(kind === "session" ? sessionKey(tokenHash) : botKey(tokenHash));
}
