import { and, eq, isNull, ne, sql } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import type { Services } from "../../context.js";
import { pgCode, UNIQUE_VIOLATION, type Tx } from "../../db/client.js";
import { connectedAccounts, sessions, userCredentials, users } from "../../db/schema.js";
import { forgetToken } from "../../http/auth.js";
import { dummyPasswordHash, hashPassword, randomToken, sha256, verifyPassword } from "../../lib/crypto.js";
import { conflict, forbidden, unauthorized } from "../../lib/errors.js";
import { audit, publicUser } from "../shared.js";

export async function createSession(services: Services, tx: Tx, userId: bigint, request: FastifyRequest | null) {
	const token = randomToken(32);
	const expiresAt = new Date(Date.now() + services.config.SESSION_TTL_DAYS * 86_400_000);
	const id = services.ids.next();
	await tx.insert(sessions).values({
		id,
		userId,
		tokenHash: sha256(token),
		expiresAt,
		ip: request?.ip,
		userAgent: request?.headers["user-agent"]?.slice(0, 256),
	});
	return { token, sessionId: id, expiresAt };
}

export async function register(
	services: Services,
	request: FastifyRequest,
	input: { username: string; password: string; displayName?: string },
) {
	const passwordHash = await hashPassword(input.password);
	try {
		return await services.db.transaction(async (tx) => {
			const id = services.ids.next();
			const [user] = await tx
				.insert(users)
				.values({ id, username: input.username, displayName: input.displayName ?? null, lastActiveAt: new Date() })
				.returning();
			await tx.insert(userCredentials).values({ userId: id, passwordHash });
			const session = await createSession(services, tx, id, request);
			await audit(services, tx, request, { action: "auth.register", actorId: id, targetType: "user", targetId: id });
			return { user: publicUser(user), ...session };
		});
	} catch (error) {
		if (pgCode(error) === UNIQUE_VIOLATION) throw conflict("That username is taken");
		throw error;
	}
}

export async function login(services: Services, request: FastifyRequest, input: { username: string; password: string }) {
	const [row] = await services.db
		.select({ user: users, passwordHash: userCredentials.passwordHash })
		.from(users)
		.leftJoin(userCredentials, eq(userCredentials.userId, users.id))
		.where(and(sql`lower(${users.username}) = lower(${input.username})`, eq(users.isBot, false)))
		.limit(1);

	// Always run one scrypt, so the answer time doesn't tell whether the username exists
	const valid = await verifyPassword(input.password, row?.passwordHash ?? (await dummyPasswordHash()));
	if (!row || !row.passwordHash || !valid) {
		if (row) {
			await audit(services, services.db, request, {
				action: "auth.login_failed",
				actorId: row.user.id,
				targetType: "user",
				targetId: row.user.id,
			});
		}
		throw unauthorized("Wrong username or password");
	}
	if (row.user.status !== "active") throw forbidden("This account can't sign in");

	return services.db.transaction(async (tx) => {
		const session = await createSession(services, tx, row.user.id, request);
		await audit(services, tx, request, {
			action: "auth.login",
			actorId: row.user.id,
			targetType: "session",
			targetId: session.sessionId,
		});
		return { user: publicUser(row.user), ...session };
	});
}

export async function revokeSession(services: Services, request: FastifyRequest | null, userId: bigint, sessionId: bigint) {
	const [session] = await services.db
		.update(sessions)
		.set({ revokedAt: new Date() })
		.where(and(eq(sessions.id, sessionId), eq(sessions.userId, userId), isNull(sessions.revokedAt)))
		.returning({ tokenHash: sessions.tokenHash });
	if (!session) return false;
	await forgetToken(services, session.tokenHash, "session");
	await audit(services, services.db, request, {
		action: "auth.session_revoke",
		actorId: userId,
		targetType: "session",
		targetId: sessionId,
	});
	return true;
}

/** Revokes every session of a user except `keep`. */
export async function revokeAllSessions(services: Services, tx: Tx, userId: bigint, keep?: bigint) {
	const revoked = await tx
		.update(sessions)
		.set({ revokedAt: new Date() })
		.where(and(eq(sessions.userId, userId), isNull(sessions.revokedAt), keep ? ne(sessions.id, keep) : undefined))
		.returning({ tokenHash: sessions.tokenHash });
	for (const session of revoked) await forgetToken(services, session.tokenHash, "session");
	return revoked.length;
}

export async function changePassword(
	services: Services,
	request: FastifyRequest,
	userId: bigint,
	sessionId: bigint | undefined,
	input: { currentPassword?: string; newPassword: string },
) {
	const [existing] = await services.db.select().from(userCredentials).where(eq(userCredentials.userId, userId));
	if (existing && !(input.currentPassword && (await verifyPassword(input.currentPassword, existing.passwordHash)))) {
		throw forbidden("Your current password is wrong");
	}
	const passwordHash = await hashPassword(input.newPassword);
	await services.db.transaction(async (tx) => {
		await tx
			.insert(userCredentials)
			.values({ userId, passwordHash })
			.onConflictDoUpdate({ target: userCredentials.userId, set: { passwordHash, updatedAt: new Date() } });
		// Someone who knew the old password is signed out everywhere else
		await revokeAllSessions(services, tx, userId, sessionId);
		await audit(services, tx, request, { action: "auth.password_change", actorId: userId, targetType: "user", targetId: userId });
	});
}

/** A free username based on `base` (for accounts made from a Roblox sign-in). */
export async function freeUsername(tx: Tx, base: string): Promise<string> {
	const clean = base.replace(/[^A-Za-z0-9_.]/g, "").slice(0, 26) || "user";
	const padded = clean.length < 3 ? `${clean}___`.slice(0, 3) : clean;
	for (let attempt = 0; attempt < 20; attempt++) {
		const candidate = attempt === 0 ? padded : `${padded}_${Math.floor(Math.random() * 10_000)}`;
		const [taken] = await tx
			.select({ id: users.id })
			.from(users)
			.where(sql`lower(${users.username}) = lower(${candidate})`)
			.limit(1);
		if (!taken) return candidate;
	}
	return `user_${randomToken(6).replace(/[^A-Za-z0-9]/g, "")}`;
}

export async function connectedAccountsOf(services: Services, userId: bigint) {
	return services.db
		.select({
			provider: connectedAccounts.provider,
			providerUserId: connectedAccounts.providerUserId,
			providerUsername: connectedAccounts.providerUsername,
			createdAt: connectedAccounts.createdAt,
		})
		.from(connectedAccounts)
		.where(eq(connectedAccounts.userId, userId));
}
