import { and, eq, inArray, or } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import type { Actor, Services } from "../../context.js";
import { pgCode, type Tx, UNIQUE_VIOLATION } from "../../db/client.js";
import {
	botInstallations,
	bots,
	connectedAccounts,
	relationships,
	roles,
	userCredentials,
	userSettings,
	users,
	workspaceMembers,
} from "../../db/schema.js";
import { forgetToken } from "../../http/auth.js";
import { verifyPassword } from "../../lib/crypto.js";
import { badRequest, conflict, forbidden, notFound } from "../../lib/errors.js";
import { revokeAllSessions } from "../auth/service.js";
import { leaveAllGroups } from "../conversations/service.js";
import { audit, publicUser, publish } from "../shared.js";
import { ensureNotOwner, leaveAllWorkspaces } from "../workspaces/service.js";

export async function getMe(services: Services, actor: Actor) {
	const [user] = await services.db.select().from(users).where(eq(users.id, actor.userId));
	if (!user) throw notFound("User");
	return { ...publicUser(user), status: user.status, lastActiveAt: user.lastActiveAt };
}

export async function getUser(services: Services, userId: bigint) {
	const [user] = await services.db.select().from(users).where(eq(users.id, userId));
	if (!user) throw notFound("User");
	return publicUser(user);
}

export async function updateMe(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	input: { username?: string; displayName?: string | null; avatarUrl?: string | null },
) {
	try {
		const user = await services.db.transaction(async (tx) => {
			const [row] = await tx.update(users).set(input).where(eq(users.id, actor.userId)).returning();
			if (input.username) {
				await audit(services, tx, request, {
					action: "user.rename",
					actorId: actor.userId,
					targetType: "user",
					targetId: actor.userId,
					data: { username: input.username },
				});
			}
			return row;
		});
		publish(services, `user:${actor.userId}`, "user.update", publicUser(user));
		return publicUser(user);
	} catch (error) {
		if (pgCode(error) === UNIQUE_VIOLATION) throw conflict("That username is taken");
		throw error;
	}
}

async function anonymize(tx: Tx, userId: bigint) {
	await tx
		.update(users)
		.set({ status: "deleted", username: `deleted-${userId}`, displayName: null, avatarUrl: null, deletedAt: new Date() })
		.where(eq(users.id, userId));
}

/** Uninstalls a bot from every workspace (its memberships and managed roles). */
export async function removeBotEverywhere(tx: Tx, botId: bigint) {
	const installs = await tx.delete(botInstallations).where(eq(botInstallations.botId, botId)).returning();
	await tx.delete(workspaceMembers).where(eq(workspaceMembers.userId, botId));
	if (installs.length > 0) {
		await tx.delete(roles).where(
			inArray(
				roles.id,
				installs.map((i) => i.roleId),
			),
		);
	}
}

/**
 * Account deletion. Retention policy:
 *  - kept: their messages (shown as "Deleted User") and 1:1 DMs, for the other people
 *  - removed: profile, password, Roblox link, sessions, settings, blocks and mutes,
 *    workspace memberships, group conversations (ownership passes on)
 *  - their bots are deleted the same way
 *  - refused while they own a workspace, so none is left without an owner
 */
export async function deleteMe(services: Services, request: FastifyRequest, actor: Actor, password?: string) {
	const [credentials] = await services.db.select().from(userCredentials).where(eq(userCredentials.userId, actor.userId));
	if (credentials && !(password && (await verifyPassword(password, credentials.passwordHash)))) {
		throw forbidden("Confirm with your password");
	}

	const botHashes = await services.db.transaction(async (tx) => {
		await tx.select({ id: users.id }).from(users).where(eq(users.id, actor.userId)).for("update");
		await ensureNotOwner(tx, actor.userId);

		const ownedBots = await tx.select({ id: bots.userId, tokenHash: bots.tokenHash }).from(bots).where(eq(bots.ownerId, actor.userId));
		for (const bot of ownedBots) {
			await removeBotEverywhere(tx, bot.id);
			await tx.update(bots).set({ status: "disabled" }).where(eq(bots.userId, bot.id));
			await anonymize(tx, bot.id);
		}

		await leaveAllGroups(services, tx, actor.userId);
		await leaveAllWorkspaces(tx, actor.userId);
		await revokeAllSessions(services, tx, actor.userId);
		await tx.delete(userCredentials).where(eq(userCredentials.userId, actor.userId));
		await tx.delete(connectedAccounts).where(eq(connectedAccounts.userId, actor.userId));
		await tx.delete(userSettings).where(eq(userSettings.userId, actor.userId));
		await tx.delete(relationships).where(or(eq(relationships.userId, actor.userId), eq(relationships.targetId, actor.userId)));
		await anonymize(tx, actor.userId);
		await audit(services, tx, request, {
			action: "user.delete",
			actorId: actor.userId,
			targetType: "user",
			targetId: actor.userId,
			data: { bots: ownedBots.length },
		});
		return ownedBots.map((b) => b.tokenHash);
	});
	for (const hash of botHashes) await forgetToken(services, hash, "bot");
	publish(services, `user:${actor.userId}`, "user.delete", { id: actor.userId });
}

// ── Blocks and mutes ─────────────────────────────────────────────────────

export async function listRelationships(services: Services, actor: Actor) {
	const rows = await services.db
		.select({ type: relationships.type, createdAt: relationships.createdAt, user: users })
		.from(relationships)
		.innerJoin(users, eq(users.id, relationships.targetId))
		.where(eq(relationships.userId, actor.userId));
	return rows.map((r) => ({ type: r.type, createdAt: r.createdAt, user: publicUser(r.user) }));
}

export async function setRelationship(services: Services, actor: Actor, targetId: bigint, type: "block" | "mute") {
	if (targetId === actor.userId) throw badRequest("You can't block or mute yourself");
	const [target] = await services.db.select({ id: users.id }).from(users).where(eq(users.id, targetId));
	if (!target) throw notFound("User");
	await services.db.insert(relationships).values({ userId: actor.userId, targetId, type }).onConflictDoNothing();
	publish(services, `user:${actor.userId}`, "relationship.add", { userId: targetId, type });
}

export async function removeRelationship(services: Services, actor: Actor, targetId: bigint, type: "block" | "mute") {
	const removed = await services.db
		.delete(relationships)
		.where(and(eq(relationships.userId, actor.userId), eq(relationships.targetId, targetId), eq(relationships.type, type)))
		.returning();
	if (removed.length === 0) throw notFound("Relationship");
	publish(services, `user:${actor.userId}`, "relationship.remove", { userId: targetId, type });
}
