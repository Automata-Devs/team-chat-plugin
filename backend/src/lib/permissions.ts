/**
 * Permission bits, like Discord's. A member's permissions in a channel are:
 *   1. the @everyone role, OR every role they have
 *   2. ADMINISTRATOR (or owning the workspace) => everything
 *   3. the channel's overwrites: @everyone, then all their roles together, then the member
 *   4. private channels also need channel membership to be seen
 */
export const Permission = {
	VIEW_CHANNEL: 1n << 0n,
	SEND_MESSAGES: 1n << 1n,
	READ_MESSAGE_HISTORY: 1n << 2n,
	ADD_REACTIONS: 1n << 3n,
	ATTACH_FILES: 1n << 4n,
	EMBED_LINKS: 1n << 5n,
	MENTION_EVERYONE: 1n << 6n,
	MANAGE_MESSAGES: 1n << 7n,
	MANAGE_CHANNELS: 1n << 8n,
	MANAGE_ROLES: 1n << 9n,
	MANAGE_WORKSPACE: 1n << 10n,
	KICK_MEMBERS: 1n << 11n,
	CREATE_INVITE: 1n << 12n,
	MANAGE_BOTS: 1n << 13n,
	VIEW_AUDIT_LOG: 1n << 14n,
	USE_COMMANDS: 1n << 15n,
	ADMINISTRATOR: 1n << 30n,
} as const;

export type PermissionName = keyof typeof Permission;

export const ALL_PERMISSIONS = Object.values(Permission).reduce((all, bit) => all | bit, 0n);

export const DEFAULT_EVERYONE_PERMISSIONS =
	Permission.VIEW_CHANNEL |
	Permission.SEND_MESSAGES |
	Permission.READ_MESSAGE_HISTORY |
	Permission.ADD_REACTIONS |
	Permission.ATTACH_FILES |
	Permission.EMBED_LINKS |
	Permission.CREATE_INVITE |
	Permission.USE_COMMANDS;

/** What every participant of a DM or group DM may do. */
export const CONVERSATION_PERMISSIONS =
	Permission.VIEW_CHANNEL |
	Permission.SEND_MESSAGES |
	Permission.READ_MESSAGE_HISTORY |
	Permission.ADD_REACTIONS |
	Permission.ATTACH_FILES |
	Permission.EMBED_LINKS |
	Permission.USE_COMMANDS;

/** Permissions that only mean something for the whole workspace, never in a channel overwrite. */
const WORKSPACE_ONLY =
	Permission.ADMINISTRATOR |
	Permission.MANAGE_WORKSPACE |
	Permission.MANAGE_ROLES |
	Permission.KICK_MEMBERS |
	Permission.MANAGE_BOTS |
	Permission.VIEW_AUDIT_LOG;

export interface Overwrite {
	targetType: "role" | "member";
	targetId: bigint;
	allow: bigint;
	deny: bigint;
}

export interface MemberContext {
	userId: bigint;
	isOwner: boolean;
	/** The workspace's @everyone role id (same as the workspace id). */
	everyoneRoleId: bigint;
	/** role id => permissions, for @everyone and every role the member has. */
	roles: Map<bigint, bigint>;
}

export function basePermissions(member: MemberContext): bigint {
	if (member.isOwner) return ALL_PERMISSIONS;
	let permissions = 0n;
	for (const bits of member.roles.values()) permissions |= bits;
	return permissions & Permission.ADMINISTRATOR ? ALL_PERMISSIONS : permissions;
}

export function channelPermissions(
	member: MemberContext,
	overwrites: Overwrite[],
	channel: { isPrivate: boolean; isChannelMember: boolean },
): bigint {
	const base = basePermissions(member);
	if (base & Permission.ADMINISTRATOR) return ALL_PERMISSIONS;
	let permissions = base;

	const everyone = overwrites.find((o) => o.targetType === "role" && o.targetId === member.everyoneRoleId);
	if (everyone) permissions = (permissions & ~everyone.deny) | everyone.allow;

	let allow = 0n;
	let deny = 0n;
	for (const o of overwrites) {
		if (o.targetType === "role" && o.targetId !== member.everyoneRoleId && member.roles.has(o.targetId)) {
			allow |= o.allow;
			deny |= o.deny;
		}
	}
	permissions = (permissions & ~deny) | allow;

	const own = overwrites.find((o) => o.targetType === "member" && o.targetId === member.userId);
	if (own) permissions = (permissions & ~own.deny) | own.allow;

	if (channel.isPrivate && !channel.isChannelMember && !(base & Permission.MANAGE_CHANNELS)) {
		permissions &= ~Permission.VIEW_CHANNEL;
	}
	// Without seeing a channel nothing else in it is possible
	if (!(permissions & Permission.VIEW_CHANNEL)) return 0n;
	return permissions;
}

export function has(permissions: bigint, needed: bigint): boolean {
	return (permissions & needed) === needed;
}

export function isValidOverwriteBits(bits: bigint): boolean {
	return (bits & ~ALL_PERMISSIONS) === 0n && (bits & WORKSPACE_ONLY) === 0n;
}

export function isValidRoleBits(bits: bigint): boolean {
	return bits >= 0n && (bits & ~ALL_PERMISSIONS) === 0n;
}
