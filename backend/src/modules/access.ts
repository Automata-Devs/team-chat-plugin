/**
 * Who may do what. Every route that touches a workspace, channel or
 * conversation goes through here; nothing trusts ids or roles the client sends.
 *
 * Something the caller can't see answers 404, not 403, so its existence
 * doesn't leak.
 */
import { and, eq, inArray, isNotNull, isNull, or } from "drizzle-orm";
import type { Tx } from "../db/client.js";
import {
	channelMembers,
	channels,
	memberRoles,
	permissionOverwrites,
	roles,
	workspaceMembers,
	workspaces,
} from "../db/schema.js";
import { forbidden, notFound } from "../lib/errors.js";
import {
	CONVERSATION_PERMISSIONS,
	type MemberContext,
	type Overwrite,
	Permission,
	basePermissions,
	channelPermissions,
	has,
} from "../lib/permissions.js";

export type Channel = typeof channels.$inferSelect;
export type Workspace = typeof workspaces.$inferSelect;

export interface WorkspaceAccess {
	workspace: Workspace;
	member: MemberContext;
	permissions: bigint;
	/** The highest position among the member's roles (the owner: Infinity). */
	topPosition: number;
}

export interface ChannelAccess {
	channel: Channel;
	permissions: bigint;
	workspace?: WorkspaceAccess;
}

export const isConversation = (channel: Pick<Channel, "type">) => channel.type === "dm" || channel.type === "group_dm";

export async function workspaceAccess(tx: Tx, workspaceId: bigint, userId: bigint): Promise<WorkspaceAccess> {
	const [row] = await tx
		.select({ workspace: workspaces })
		.from(workspaces)
		.innerJoin(workspaceMembers, and(eq(workspaceMembers.workspaceId, workspaces.id), eq(workspaceMembers.userId, userId)))
		.where(and(eq(workspaces.id, workspaceId), isNull(workspaces.deletedAt)))
		.limit(1);
	if (!row) throw notFound("Workspace");

	// @everyone (id = workspace id) and every role the member has
	const roleRows = await tx
		.select({ id: roles.id, permissions: roles.permissions, position: roles.position })
		.from(roles)
		.leftJoin(
			memberRoles,
			and(eq(memberRoles.roleId, roles.id), eq(memberRoles.userId, userId), eq(memberRoles.workspaceId, workspaceId)),
		)
		.where(and(eq(roles.workspaceId, workspaceId), or(eq(roles.id, workspaceId), isNotNull(memberRoles.roleId))));

	const member: MemberContext = {
		userId,
		isOwner: row.workspace.ownerId === userId,
		everyoneRoleId: workspaceId,
		roles: new Map(roleRows.map((r) => [r.id, r.permissions])),
	};
	const topPosition = member.isOwner ? Infinity : Math.max(0, ...roleRows.map((r) => r.position));
	return { workspace: row.workspace, member, permissions: basePermissions(member), topPosition };
}

export async function requireWorkspacePermission(
	tx: Tx,
	workspaceId: bigint,
	userId: bigint,
	needed: bigint,
): Promise<WorkspaceAccess> {
	const access = await workspaceAccess(tx, workspaceId, userId);
	if (!has(access.permissions, needed)) throw forbidden();
	return access;
}

async function overwritesFor(tx: Tx, channelIds: bigint[]): Promise<Map<bigint, Overwrite[]>> {
	const map = new Map<bigint, Overwrite[]>();
	if (channelIds.length === 0) return map;
	const rows = await tx.select().from(permissionOverwrites).where(inArray(permissionOverwrites.channelId, channelIds));
	for (const row of rows) {
		const list = map.get(row.channelId) ?? [];
		list.push({ targetType: row.targetType, targetId: row.targetId, allow: row.allow, deny: row.deny });
		map.set(row.channelId, list);
	}
	return map;
}

async function membershipsOf(tx: Tx, channelIds: bigint[], userId: bigint): Promise<Set<bigint>> {
	if (channelIds.length === 0) return new Set();
	const rows = await tx
		.select({ channelId: channelMembers.channelId })
		.from(channelMembers)
		.where(and(inArray(channelMembers.channelId, channelIds), eq(channelMembers.userId, userId)));
	return new Set(rows.map((r) => r.channelId));
}

/** The caller's permissions in a channel or conversation; 404 when they can't see it. */
export async function channelAccess(tx: Tx, channelId: bigint, userId: bigint): Promise<ChannelAccess> {
	const [channel] = await tx
		.select()
		.from(channels)
		.where(and(eq(channels.id, channelId), isNull(channels.deletedAt)))
		.limit(1);
	if (!channel) throw notFound("Channel");

	if (isConversation(channel)) {
		if (!(await membershipsOf(tx, [channel.id], userId)).has(channel.id)) throw notFound("Channel");
		return { channel, permissions: CONVERSATION_PERMISSIONS };
	}

	let workspace: WorkspaceAccess;
	try {
		workspace = await workspaceAccess(tx, channel.workspaceId!, userId);
	} catch {
		throw notFound("Channel");
	}
	const [overwrites, memberships] = await Promise.all([
		overwritesFor(tx, [channel.id]),
		channel.isPrivate ? membershipsOf(tx, [channel.id], userId) : Promise.resolve(new Set<bigint>()),
	]);
	const permissions = channelPermissions(workspace.member, overwrites.get(channel.id) ?? [], {
		isPrivate: channel.isPrivate,
		isChannelMember: memberships.has(channel.id),
	});
	if (!has(permissions, Permission.VIEW_CHANNEL)) throw notFound("Channel");
	return { channel, permissions, workspace };
}

export async function requireChannelPermission(
	tx: Tx,
	channelId: bigint,
	userId: bigint,
	needed: bigint,
): Promise<ChannelAccess> {
	const access = await channelAccess(tx, channelId, userId);
	if (!has(access.permissions, needed)) throw forbidden();
	return access;
}

/** Every channel of a workspace the member can see, with their permissions: 3 queries for any number. */
export async function visibleWorkspaceChannels(
	tx: Tx,
	access: WorkspaceAccess,
): Promise<Array<{ channel: Channel; permissions: bigint }>> {
	const all = await tx
		.select()
		.from(channels)
		.where(and(eq(channels.workspaceId, access.workspace.id), isNull(channels.deletedAt)));
	const [overwrites, memberships] = await Promise.all([
		overwritesFor(
			tx,
			all.map((c) => c.id),
		),
		membershipsOf(
			tx,
			all.filter((c) => c.isPrivate).map((c) => c.id),
			access.member.userId,
		),
	]);
	const visible: Array<{ channel: Channel; permissions: bigint }> = [];
	for (const channel of all) {
		const permissions = channelPermissions(access.member, overwrites.get(channel.id) ?? [], {
			isPrivate: channel.isPrivate,
			isChannelMember: memberships.has(channel.id),
		});
		if (has(permissions, Permission.VIEW_CHANNEL)) visible.push({ channel, permissions });
	}
	return visible;
}

/** Whether `userId` can see a channel: for deciding who gets a notification or an event. */
export async function canView(tx: Tx, channelId: bigint, userId: bigint): Promise<boolean> {
	try {
		await channelAccess(tx, channelId, userId);
		return true;
	} catch {
		return false;
	}
}

/**
 * Of `userIds`, those who can read `channel`. Batched (5 queries for any
 * number of people), for notifications and bot events.
 */
export async function readersOf(tx: Tx, channel: Channel, userIds: bigint[]): Promise<Set<bigint>> {
	const ids = [...new Set(userIds)];
	if (ids.length === 0) return new Set();
	if (isConversation(channel)) {
		const members = await tx
			.select({ userId: channelMembers.userId })
			.from(channelMembers)
			.where(and(eq(channelMembers.channelId, channel.id), inArray(channelMembers.userId, ids)));
		return new Set(members.map((m) => m.userId));
	}
	const workspaceId = channel.workspaceId!;
	const [[workspace], members, workspaceRoles, assigned, overwrites, privateMembers] = await Promise.all([
		tx.select().from(workspaces).where(and(eq(workspaces.id, workspaceId), isNull(workspaces.deletedAt))),
		tx
			.select({ userId: workspaceMembers.userId })
			.from(workspaceMembers)
			.where(and(eq(workspaceMembers.workspaceId, workspaceId), inArray(workspaceMembers.userId, ids))),
		tx.select({ id: roles.id, permissions: roles.permissions }).from(roles).where(eq(roles.workspaceId, workspaceId)),
		tx
			.select({ userId: memberRoles.userId, roleId: memberRoles.roleId })
			.from(memberRoles)
			.where(and(eq(memberRoles.workspaceId, workspaceId), inArray(memberRoles.userId, ids))),
		overwritesFor(tx, [channel.id]),
		channel.isPrivate
			? tx
					.select({ userId: channelMembers.userId })
					.from(channelMembers)
					.where(and(eq(channelMembers.channelId, channel.id), inArray(channelMembers.userId, ids)))
			: Promise.resolve([]),
	]);
	if (!workspace) return new Set();
	const rolePermissions = new Map(workspaceRoles.map((r) => [r.id, r.permissions]));
	const inPrivate = new Set(privateMembers.map((m) => m.userId));
	const readers = new Set<bigint>();
	for (const { userId } of members) {
		const memberRoleMap = new Map<bigint, bigint>([[workspaceId, rolePermissions.get(workspaceId) ?? 0n]]);
		for (const a of assigned) if (a.userId === userId) memberRoleMap.set(a.roleId, rolePermissions.get(a.roleId) ?? 0n);
		const permissions = channelPermissions(
			{ userId, isOwner: workspace.ownerId === userId, everyoneRoleId: workspaceId, roles: memberRoleMap },
			overwrites.get(channel.id) ?? [],
			{ isPrivate: channel.isPrivate, isChannelMember: inPrivate.has(userId) },
		);
		if (has(permissions, Permission.VIEW_CHANNEL | Permission.READ_MESSAGE_HISTORY)) readers.add(userId);
	}
	return readers;
}

/** Members of a workspace may act on each other only downwards in the role order. */
export function outranks(actor: WorkspaceAccess, targetTopPosition: number, targetIsOwner: boolean): boolean {
	if (targetIsOwner) return false;
	return actor.member.isOwner || actor.topPosition > targetTopPosition;
}
