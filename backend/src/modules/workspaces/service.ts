import { and, asc, eq, gt, inArray, isNull, or, sql } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import type { Actor, Services } from "../../context.js";
import type { Tx } from "../../db/client.js";
import {
	botInstallations,
	channels,
	connectedAccounts,
	invites,
	memberRoles,
	roles,
	users,
	workspaceMembers,
	workspaces,
} from "../../db/schema.js";
import { enqueue } from "../../infra/jobs.js";
import { randomToken } from "../../lib/crypto.js";
import { AppError, badRequest, conflict, forbidden, notFound } from "../../lib/errors.js";
import { ALL_PERMISSIONS, DEFAULT_EVERYONE_PERMISSIONS, Permission, has, isValidRoleBits } from "../../lib/permissions.js";
import { outranks, requireWorkspacePermission, type WorkspaceAccess, workspaceAccess } from "../access.js";
import { audit, publicUser, publish, usersById } from "../shared.js";

const MAX_WORKSPACES_OWNED = 100;
const MAX_ROLES = 250;

type WorkspaceRow = typeof workspaces.$inferSelect;

export function serializeWorkspace(workspace: WorkspaceRow, permissions?: bigint) {
	return {
		id: workspace.id,
		name: workspace.name,
		description: workspace.description,
		iconUrl: workspace.iconUrl,
		ownerId: workspace.ownerId,
		placeKey: workspace.placeKey,
		teamChatChannelId: workspace.teamChatChannelId,
		createdAt: workspace.createdAt,
		...(permissions !== undefined ? { permissions: permissions.toString() } : {}),
	};
}

export async function createWorkspace(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	input: { name: string; description?: string; iconUrl?: string },
	place?: { key: string; secretHash: Buffer },
) {
	const created = await services.db.transaction(async (tx) => {
		const [{ count }] = await tx
			.select({ count: sql<number>`count(*)::int` })
			.from(workspaces)
			.where(and(eq(workspaces.ownerId, actor.userId), isNull(workspaces.deletedAt)));
		if (count >= MAX_WORKSPACES_OWNED) throw badRequest(`You can own at most ${MAX_WORKSPACES_OWNED} workspaces`);

		const id = services.ids.next();
		const categoryId = services.ids.next();
		const generalId = services.ids.next();
		const [workspace] = await tx
			.insert(workspaces)
			.values({
				id,
				name: input.name,
				description: input.description,
				iconUrl: input.iconUrl,
				ownerId: actor.userId,
				placeKey: place?.key,
				placeSecretHash: place?.secretHash,
				teamChatChannelId: generalId,
			})
			.returning();
		await tx.insert(roles).values({ id, workspaceId: id, name: "@everyone", permissions: DEFAULT_EVERYONE_PERMISSIONS });
		await tx.insert(workspaceMembers).values({ workspaceId: id, userId: actor.userId });
		await tx.insert(channels).values([
			{ id: categoryId, type: "category", workspaceId: id, name: "Text channels", position: 0 },
			{ id: generalId, type: "text", workspaceId: id, parentId: categoryId, name: place ? "team-chat" : "general", position: 0 },
		]);
		await audit(services, tx, request, {
			action: "workspace.create",
			actorId: actor.userId,
			workspaceId: id,
			targetType: "workspace",
			targetId: id,
		});
		return workspace;
	});
	publish(services, `user:${actor.userId}`, "workspace.join", { id: created.id });
	return serializeWorkspace(created, ALL_PERMISSIONS);
}

export async function listMyWorkspaces(services: Services, actor: Actor) {
	const rows = await services.db
		.select({ workspace: workspaces })
		.from(workspaces)
		.innerJoin(workspaceMembers, and(eq(workspaceMembers.workspaceId, workspaces.id), eq(workspaceMembers.userId, actor.userId)))
		.where(isNull(workspaces.deletedAt))
		.orderBy(asc(workspaceMembers.joinedAt));
	return rows.map((r) => serializeWorkspace(r.workspace));
}

export async function getWorkspace(services: Services, actor: Actor, workspaceId: bigint) {
	const access = await workspaceAccess(services.db, workspaceId, actor.userId);
	return serializeWorkspace(access.workspace, access.permissions);
}

export async function updateWorkspace(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	workspaceId: bigint,
	input: { name?: string; description?: string | null; iconUrl?: string | null },
) {
	const updated = await services.db.transaction(async (tx) => {
		await requireWorkspacePermission(tx, workspaceId, actor.userId, Permission.MANAGE_WORKSPACE);
		const [row] = await tx.update(workspaces).set(input).where(eq(workspaces.id, workspaceId)).returning();
		await audit(services, tx, request, { action: "workspace.update", actorId: actor.userId, workspaceId, data: input });
		return row;
	});
	publish(services, `workspace:${workspaceId}`, "workspace.update", serializeWorkspace(updated));
	return serializeWorkspace(updated);
}

/**
 * Deleting a workspace hides it at once; a job then deletes its channels'
 * messages and files, one channel at a time. Nothing outside it is touched.
 */
export async function deleteWorkspace(services: Services, request: FastifyRequest, actor: Actor, workspaceId: bigint) {
	await services.db.transaction(async (tx) => {
		const access = await workspaceAccess(tx, workspaceId, actor.userId);
		if (!access.member.isOwner) throw forbidden("Only the owner can delete a workspace");
		await tx.update(workspaces).set({ deletedAt: new Date() }).where(eq(workspaces.id, workspaceId));
		await enqueue(tx, "workspace.purge", { workspaceId });
		await audit(services, tx, request, {
			action: "workspace.delete",
			actorId: actor.userId,
			workspaceId,
			targetType: "workspace",
			targetId: workspaceId,
		});
	});
	publish(services, `workspace:${workspaceId}`, "workspace.delete", { id: workspaceId });
}

export async function transferOwnership(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	workspaceId: bigint,
	newOwnerId: bigint,
) {
	await services.db.transaction(async (tx) => {
		const access = await workspaceAccess(tx, workspaceId, actor.userId);
		if (!access.member.isOwner) throw forbidden("Only the owner can transfer the workspace");
		const [target] = await tx
			.select({ isBot: users.isBot, status: users.status })
			.from(workspaceMembers)
			.innerJoin(users, eq(users.id, workspaceMembers.userId))
			.where(and(eq(workspaceMembers.workspaceId, workspaceId), eq(workspaceMembers.userId, newOwnerId)));
		if (!target) throw notFound("Member");
		if (target.isBot || target.status !== "active") throw badRequest("That member can't own a workspace");
		await tx.update(workspaces).set({ ownerId: newOwnerId }).where(eq(workspaces.id, workspaceId));
		await audit(services, tx, request, {
			action: "workspace.transfer",
			actorId: actor.userId,
			workspaceId,
			targetType: "user",
			targetId: newOwnerId,
		});
	});
	publish(services, `workspace:${workspaceId}`, "workspace.update", { id: workspaceId, ownerId: newOwnerId });
}

// ── Members ──────────────────────────────────────────────────────────────

async function memberTopPosition(tx: Tx, workspaceId: bigint, userId: bigint) {
	const [row] = await tx
		.select({ top: sql<number>`coalesce(max(${roles.position}), 0)::int` })
		.from(memberRoles)
		.innerJoin(roles, eq(roles.id, memberRoles.roleId))
		.where(and(eq(memberRoles.workspaceId, workspaceId), eq(memberRoles.userId, userId)));
	return row?.top ?? 0;
}

export async function listMembers(services: Services, actor: Actor, workspaceId: bigint, query: { after?: bigint; limit: number }) {
	await workspaceAccess(services.db, workspaceId, actor.userId);
	const rows = await services.db
		.select()
		.from(workspaceMembers)
		.where(and(eq(workspaceMembers.workspaceId, workspaceId), query.after ? gt(workspaceMembers.userId, query.after) : undefined))
		.orderBy(asc(workspaceMembers.userId))
		.limit(query.limit);
	const ids = rows.map((r) => r.userId);
	const [people, roleRows] = await Promise.all([
		usersById(services.db, ids),
		ids.length === 0
			? Promise.resolve([])
			: services.db
					.select()
					.from(memberRoles)
					.where(and(eq(memberRoles.workspaceId, workspaceId), inArray(memberRoles.userId, ids))),
	]);
	return rows.map((m) => ({
		user: people.get(m.userId),
		nickname: m.nickname,
		joinedAt: m.joinedAt,
		roles: roleRows.filter((r) => r.userId === m.userId).map((r) => r.roleId),
	}));
}

/** The workspace member signed in with this Roblox account (for DMs between teammates), or 404. */
export async function memberByRobloxId(services: Services, actor: Actor, workspaceId: bigint, robloxUserId: string) {
	await workspaceAccess(services.db, workspaceId, actor.userId);
	const [row] = await services.db
		.select({ user: users })
		.from(connectedAccounts)
		.innerJoin(users, eq(users.id, connectedAccounts.userId))
		.innerJoin(workspaceMembers, and(eq(workspaceMembers.userId, users.id), eq(workspaceMembers.workspaceId, workspaceId)))
		.where(and(eq(connectedAccounts.provider, "roblox"), eq(connectedAccounts.providerUserId, robloxUserId), eq(users.status, "active")));
	if (!row) throw notFound("Member");
	return publicUser(row.user);
}

export async function setNickname(services: Services, actor: Actor, workspaceId: bigint, nickname: string | null) {
	await workspaceAccess(services.db, workspaceId, actor.userId);
	await services.db
		.update(workspaceMembers)
		.set({ nickname })
		.where(and(eq(workspaceMembers.workspaceId, workspaceId), eq(workspaceMembers.userId, actor.userId)));
	publish(services, `workspace:${workspaceId}`, "member.update", { workspaceId, userId: actor.userId, nickname });
}

/** Removes a member's access to everything in the workspace. The caller has checked permission. */
async function removeMember(tx: Tx, workspaceId: bigint, userId: bigint) {
	const removed = await tx
		.delete(workspaceMembers)
		.where(and(eq(workspaceMembers.workspaceId, workspaceId), eq(workspaceMembers.userId, userId)))
		.returning();
	if (removed.length === 0) throw notFound("Member");
	// member_roles cascade from the membership; private channel memberships go too
	await tx.execute(sql`
		delete from channel_members cm using channels c
		where cm.channel_id = c.id and c.workspace_id = ${workspaceId} and cm.user_id = ${userId}`);
	const installs = await tx
		.delete(botInstallations)
		.where(and(eq(botInstallations.workspaceId, workspaceId), eq(botInstallations.botId, userId)))
		.returning();
	for (const install of installs) await tx.delete(roles).where(eq(roles.id, install.roleId));
}

/** Your own id: leave. Someone else's: kick them (KICK_MEMBERS, and you must outrank them). */
export async function leaveOrKick(services: Services, request: FastifyRequest, actor: Actor, workspaceId: bigint, userId: bigint) {
	await services.db.transaction(async (tx) => {
		const access = await workspaceAccess(tx, workspaceId, actor.userId);
		if (userId === actor.userId) {
			if (access.member.isOwner) throw badRequest("Transfer the workspace before leaving it");
			await removeMember(tx, workspaceId, userId);
			await audit(services, tx, request, { action: "member.leave", actorId: actor.userId, workspaceId, targetType: "user", targetId: userId });
			return;
		}
		if (!has(access.permissions, Permission.KICK_MEMBERS)) throw forbidden();
		const targetIsOwner = access.workspace.ownerId === userId;
		if (!outranks(access, await memberTopPosition(tx, workspaceId, userId), targetIsOwner)) {
			throw forbidden("You can only remove members below your highest role");
		}
		await removeMember(tx, workspaceId, userId);
		await audit(services, tx, request, { action: "member.kick", actorId: actor.userId, workspaceId, targetType: "user", targetId: userId });
	});
	publish(services, `workspace:${workspaceId}`, "member.remove", { workspaceId, userId });
	publish(services, `user:${userId}`, "workspace.leave", { id: workspaceId });
}

/** Account deletion: refused while the user owns a workspace (it'd be left without an owner). */
export async function ensureNotOwner(tx: Tx, userId: bigint) {
	const [owned] = await tx
		.select({ id: workspaces.id })
		.from(workspaces)
		.where(and(eq(workspaces.ownerId, userId), isNull(workspaces.deletedAt)))
		.limit(1);
	if (owned) throw conflict("Transfer or delete the workspaces you own first");
}

/** Account deletion: leaves every workspace. */
export async function leaveAllWorkspaces(tx: Tx, userId: bigint) {
	const memberships = await tx
		.select({ workspaceId: workspaceMembers.workspaceId })
		.from(workspaceMembers)
		.where(eq(workspaceMembers.userId, userId));
	for (const { workspaceId } of memberships) await removeMember(tx, workspaceId, userId);
	return memberships.map((m) => m.workspaceId);
}

// ── Invites ──────────────────────────────────────────────────────────────

export async function createInvite(
	services: Services,
	actor: Actor,
	workspaceId: bigint,
	input: { maxUses?: number; expiresInSeconds?: number },
) {
	await requireWorkspacePermission(services.db, workspaceId, actor.userId, Permission.CREATE_INVITE);
	const [invite] = await services.db
		.insert(invites)
		.values({
			code: randomToken(9),
			workspaceId,
			inviterId: actor.userId,
			maxUses: input.maxUses,
			expiresAt: input.expiresInSeconds ? new Date(Date.now() + input.expiresInSeconds * 1000) : null,
		})
		.returning();
	return invite;
}

export async function listInvites(services: Services, actor: Actor, workspaceId: bigint) {
	await requireWorkspacePermission(services.db, workspaceId, actor.userId, Permission.MANAGE_WORKSPACE);
	return services.db.select().from(invites).where(eq(invites.workspaceId, workspaceId));
}

export async function deleteInvite(services: Services, actor: Actor, code: string) {
	const [invite] = await services.db.select().from(invites).where(eq(invites.code, code));
	if (!invite) throw notFound("Invite");
	const access = await workspaceAccess(services.db, invite.workspaceId, actor.userId);
	if (invite.inviterId !== actor.userId && !has(access.permissions, Permission.MANAGE_WORKSPACE)) throw forbidden();
	await services.db.delete(invites).where(eq(invites.code, code));
}

export async function previewInvite(services: Services, code: string) {
	const [row] = await services.db
		.select({ invite: invites, workspace: workspaces })
		.from(invites)
		.innerJoin(workspaces, eq(workspaces.id, invites.workspaceId))
		.where(and(eq(invites.code, code), isNull(workspaces.deletedAt)));
	if (!row || (row.invite.expiresAt && row.invite.expiresAt < new Date())) throw notFound("Invite");
	return { code, workspace: { id: row.workspace.id, name: row.workspace.name, iconUrl: row.workspace.iconUrl } };
}

export async function acceptInvite(services: Services, request: FastifyRequest, actor: Actor, code: string) {
	const workspaceId = await services.db.transaction(async (tx) => {
		const [found] = await tx
			.select({ invite: invites })
			.from(invites)
			.innerJoin(workspaces, eq(workspaces.id, invites.workspaceId))
			.where(and(eq(invites.code, code), isNull(workspaces.deletedAt)));
		if (!found) throw notFound("Invite");
		const { workspaceId } = found.invite;
		const already = await tx
			.select({ userId: workspaceMembers.userId })
			.from(workspaceMembers)
			.where(and(eq(workspaceMembers.workspaceId, workspaceId), eq(workspaceMembers.userId, actor.userId)));
		if (already.length > 0) return workspaceId;

		// Counted atomically: a 1-use invite admits exactly one person
		const used = await tx
			.update(invites)
			.set({ uses: sql`${invites.uses} + 1` })
			.where(
				and(
					eq(invites.code, code),
					or(isNull(invites.maxUses), sql`${invites.uses} < ${invites.maxUses}`),
					or(isNull(invites.expiresAt), sql`${invites.expiresAt} > now()`),
				),
			)
			.returning();
		if (used.length === 0) throw new AppError(410, "expired", "This invite has expired or been used up");
		await tx.insert(workspaceMembers).values({ workspaceId, userId: actor.userId });
		await audit(services, tx, request, { action: "member.join", actorId: actor.userId, workspaceId, data: { invite: code } });
		return workspaceId;
	});
	publish(services, `workspace:${workspaceId}`, "member.add", { workspaceId, userId: actor.userId });
	publish(services, `user:${actor.userId}`, "workspace.join", { id: workspaceId });
	return getWorkspace(services, actor, workspaceId);
}

// ── Roles ────────────────────────────────────────────────────────────────

export async function listRoles(services: Services, actor: Actor, workspaceId: bigint) {
	await workspaceAccess(services.db, workspaceId, actor.userId);
	return services.db.select().from(roles).where(eq(roles.workspaceId, workspaceId)).orderBy(asc(roles.position), asc(roles.id));
}

/** Nobody hands out permissions they don't have, or touches roles at or above their own highest. */
function assertCanManageRole(access: WorkspaceAccess, role: { position: number; permissions: bigint }) {
	if (access.member.isOwner) return;
	if (role.position >= access.topPosition) throw forbidden("That role is at or above your highest role");
	if ((role.permissions & ~access.permissions) !== 0n) throw forbidden("You can't grant permissions you don't have");
}

interface RoleInput {
	name?: string;
	color?: number;
	permissions?: bigint;
	position?: number;
	mentionable?: boolean;
}

export async function createRole(services: Services, request: FastifyRequest, actor: Actor, workspaceId: bigint, input: RoleInput & { name: string }) {
	const role = await services.db.transaction(async (tx) => {
		const access = await requireWorkspacePermission(tx, workspaceId, actor.userId, Permission.MANAGE_ROLES);
		const permissions = input.permissions ?? 0n;
		if (!isValidRoleBits(permissions)) throw badRequest("Unknown permission bits");
		const position = input.position ?? 1;
		if (position < 1) throw badRequest("Position 0 belongs to @everyone");
		assertCanManageRole(access, { position, permissions });
		const [{ count }] = await tx.select({ count: sql<number>`count(*)::int` }).from(roles).where(eq(roles.workspaceId, workspaceId));
		if (count >= MAX_ROLES) throw badRequest(`A workspace can have at most ${MAX_ROLES} roles`);
		const [row] = await tx
			.insert(roles)
			.values({
				id: services.ids.next(),
				workspaceId,
				name: input.name,
				color: input.color ?? 0,
				permissions,
				position,
				mentionable: input.mentionable ?? false,
			})
			.returning();
		await audit(services, tx, request, {
			action: "role.create",
			actorId: actor.userId,
			workspaceId,
			targetType: "role",
			targetId: row.id,
			data: { permissions },
		});
		return row;
	});
	publish(services, `workspace:${workspaceId}`, "role.create", role);
	return role;
}

async function loadRole(tx: Tx, workspaceId: bigint, roleId: bigint) {
	const [role] = await tx
		.select()
		.from(roles)
		.where(and(eq(roles.id, roleId), eq(roles.workspaceId, workspaceId)));
	if (!role) throw notFound("Role");
	return role;
}

export async function updateRole(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	workspaceId: bigint,
	roleId: bigint,
	input: RoleInput,
) {
	const role = await services.db.transaction(async (tx) => {
		const access = await requireWorkspacePermission(tx, workspaceId, actor.userId, Permission.MANAGE_ROLES);
		const current = await loadRole(tx, workspaceId, roleId);
		if (current.managed) throw forbidden("Bot roles are managed by their installation");
		const isEveryone = roleId === workspaceId;
		if (isEveryone && (input.name !== undefined || input.position !== undefined)) throw badRequest("@everyone can't be renamed or moved");
		if (input.permissions !== undefined && !isValidRoleBits(input.permissions)) throw badRequest("Unknown permission bits");
		if (input.position !== undefined && input.position < 1) throw badRequest("Position 0 belongs to @everyone");
		if (!isEveryone) assertCanManageRole(access, { position: current.position, permissions: 0n });
		assertCanManageRole(access, {
			position: isEveryone ? -1 : (input.position ?? current.position),
			permissions: input.permissions ?? 0n,
		});
		const [row] = await tx.update(roles).set(input).where(eq(roles.id, roleId)).returning();
		await audit(services, tx, request, {
			action: "role.update",
			actorId: actor.userId,
			workspaceId,
			targetType: "role",
			targetId: roleId,
			data: { ...input },
		});
		return row;
	});
	publish(services, `workspace:${workspaceId}`, "role.update", role);
	return role;
}

export async function deleteRole(services: Services, request: FastifyRequest, actor: Actor, workspaceId: bigint, roleId: bigint) {
	await services.db.transaction(async (tx) => {
		const access = await requireWorkspacePermission(tx, workspaceId, actor.userId, Permission.MANAGE_ROLES);
		const role = await loadRole(tx, workspaceId, roleId);
		if (roleId === workspaceId) throw badRequest("@everyone can't be deleted");
		if (role.managed) throw forbidden("Remove the bot to remove its role");
		assertCanManageRole(access, { position: role.position, permissions: 0n });
		await tx.execute(sql`delete from permission_overwrites where target_type = 'role' and target_id = ${roleId}`);
		await tx.delete(roles).where(eq(roles.id, roleId));
		await audit(services, tx, request, {
			action: "role.delete",
			actorId: actor.userId,
			workspaceId,
			targetType: "role",
			targetId: roleId,
			data: { name: role.name },
		});
	});
	publish(services, `workspace:${workspaceId}`, "role.delete", { workspaceId, roleId });
}

export async function setMemberRole(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	workspaceId: bigint,
	userId: bigint,
	roleId: bigint,
	add: boolean,
) {
	await services.db.transaction(async (tx) => {
		const access = await requireWorkspacePermission(tx, workspaceId, actor.userId, Permission.MANAGE_ROLES);
		const role = await loadRole(tx, workspaceId, roleId);
		if (roleId === workspaceId) throw badRequest("Everyone has @everyone");
		if (role.managed) throw forbidden("Bot roles can't be given to members");
		assertCanManageRole(access, { position: role.position, permissions: 0n });
		const [member] = await tx
			.select()
			.from(workspaceMembers)
			.where(and(eq(workspaceMembers.workspaceId, workspaceId), eq(workspaceMembers.userId, userId)));
		if (!member) throw notFound("Member");
		if (add) {
			await tx.insert(memberRoles).values({ workspaceId, userId, roleId }).onConflictDoNothing();
		} else {
			await tx
				.delete(memberRoles)
				.where(and(eq(memberRoles.workspaceId, workspaceId), eq(memberRoles.userId, userId), eq(memberRoles.roleId, roleId)));
		}
		await audit(services, tx, request, {
			action: add ? "member.role_add" : "member.role_remove",
			actorId: actor.userId,
			workspaceId,
			targetType: "user",
			targetId: userId,
			data: { roleId },
		});
	});
	publish(services, `workspace:${workspaceId}`, "member.update", { workspaceId, userId });
}
