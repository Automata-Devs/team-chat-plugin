import { and, eq, isNull, sql } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import type { Actor, Services } from "../../context.js";
import type { Tx } from "../../db/client.js";
import { channelMembers, channels, permissionOverwrites, roles, workspaceMembers } from "../../db/schema.js";
import { enqueue } from "../../infra/jobs.js";
import { badRequest, forbidden, notFound } from "../../lib/errors.js";
import { ALL_PERMISSIONS, Permission, has, isValidOverwriteBits } from "../../lib/permissions.js";
import {
	type Channel,
	channelAccess,
	isConversation,
	requireChannelPermission,
	requireWorkspacePermission,
	visibleWorkspaceChannels,
	workspaceAccess,
} from "../access.js";
import { getConversation } from "../conversations/service.js";
import { audit, publish } from "../shared.js";

const MAX_CHANNELS = 500;

export function serializeChannel(channel: Channel, permissions?: bigint) {
	return {
		id: channel.id,
		type: channel.type,
		workspaceId: channel.workspaceId,
		parentId: channel.parentId,
		name: channel.name,
		topic: channel.topic,
		position: channel.position,
		isPrivate: channel.isPrivate,
		slowmodeSeconds: channel.slowmodeSeconds,
		lastMessageId: channel.lastMessageId,
		createdAt: channel.createdAt,
		...(permissions !== undefined ? { permissions: permissions.toString() } : {}),
	};
}

/** Text channel names look like Discord's: lowercase, dashes for spaces. */
export const channelName = (value: string, type: "text" | "category") =>
	type === "text" ? value.toLowerCase().replace(/\s+/g, "-").replace(/-+/g, "-") : value;

/** Events about a private channel only go to people who can see it; the workspace hears "something changed". */
function publishChannelEvent(services: Services, channel: Channel, type: string) {
	if (channel.isPrivate) {
		publish(services, `channel:${channel.id}`, type, serializeChannel(channel));
		publish(services, `workspace:${channel.workspaceId}`, "channels.changed", { workspaceId: channel.workspaceId });
	} else {
		publish(services, `workspace:${channel.workspaceId}`, type, serializeChannel(channel));
	}
}

async function assertCategory(tx: Tx, workspaceId: bigint, parentId: bigint | null | undefined) {
	if (parentId === null || parentId === undefined) return;
	const [parent] = await tx
		.select({ type: channels.type })
		.from(channels)
		.where(and(eq(channels.id, parentId), eq(channels.workspaceId, workspaceId), isNull(channels.deletedAt)));
	if (!parent || parent.type !== "category") throw badRequest("parentId must be a category in this workspace");
}

export interface ChannelInput {
	type: "text" | "category";
	name: string;
	topic?: string | null;
	parentId?: bigint | null;
	position?: number;
	isPrivate?: boolean;
	slowmodeSeconds?: number;
}

export async function createChannel(services: Services, request: FastifyRequest, actor: Actor, workspaceId: bigint, input: ChannelInput) {
	const channel = await services.db.transaction(async (tx) => {
		await requireWorkspacePermission(tx, workspaceId, actor.userId, Permission.MANAGE_CHANNELS);
		if (input.type === "category" && input.parentId) throw badRequest("Categories can't be nested");
		await assertCategory(tx, workspaceId, input.parentId);
		const [{ count }] = await tx
			.select({ count: sql<number>`count(*)::int` })
			.from(channels)
			.where(and(eq(channels.workspaceId, workspaceId), isNull(channels.deletedAt)));
		if (count >= MAX_CHANNELS) throw badRequest(`A workspace can have at most ${MAX_CHANNELS} channels`);

		const [row] = await tx
			.insert(channels)
			.values({
				id: services.ids.next(),
				type: input.type,
				workspaceId,
				parentId: input.parentId ?? null,
				name: channelName(input.name, input.type),
				topic: input.topic ?? null,
				position: input.position ?? 0,
				isPrivate: input.isPrivate ?? false,
				slowmodeSeconds: input.slowmodeSeconds ?? 0,
			})
			.returning();
		// Whoever makes a private channel is in it
		if (row.isPrivate) await tx.insert(channelMembers).values({ channelId: row.id, userId: actor.userId });
		await audit(services, tx, request, {
			action: "channel.create",
			actorId: actor.userId,
			workspaceId,
			targetType: "channel",
			targetId: row.id,
			data: { name: row.name, isPrivate: row.isPrivate },
		});
		return row;
	});
	publishChannelEvent(services, channel, "channel.create");
	return serializeChannel(channel, ALL_PERMISSIONS);
}

export async function listChannels(services: Services, actor: Actor, workspaceId: bigint) {
	const access = await workspaceAccess(services.db, workspaceId, actor.userId);
	const visible = await visibleWorkspaceChannels(services.db, access);
	return visible
		.sort((a, b) => a.channel.position - b.channel.position || (a.channel.id < b.channel.id ? -1 : 1))
		.map((v) => serializeChannel(v.channel, v.permissions));
}

export async function getChannel(services: Services, actor: Actor, channelId: bigint) {
	const access = await channelAccess(services.db, channelId, actor.userId);
	if (isConversation(access.channel)) return getConversation(services, actor, channelId);
	return serializeChannel(access.channel, access.permissions);
}

export async function updateChannel(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	channelId: bigint,
	input: Partial<Omit<ChannelInput, "type">>,
) {
	const channel = await services.db.transaction(async (tx) => {
		const access = await requireChannelPermission(tx, channelId, actor.userId, Permission.MANAGE_CHANNELS);
		if (isConversation(access.channel)) throw badRequest("Use PATCH /conversations/:id for conversations");
		const current = access.channel;
		if (input.parentId !== undefined) {
			if (current.type === "category" && input.parentId !== null) throw badRequest("Categories can't be nested");
			if (input.parentId === current.id) throw badRequest("A channel can't be its own parent");
			await assertCategory(tx, current.workspaceId!, input.parentId);
		}
		const [row] = await tx
			.update(channels)
			.set({
				...input,
				name: input.name === undefined ? undefined : channelName(input.name, current.type as "text" | "category"),
			})
			.where(eq(channels.id, channelId))
			.returning();
		// Making a channel private keeps the person who did it in it
		if (row.isPrivate && !current.isPrivate) {
			await tx.insert(channelMembers).values({ channelId, userId: actor.userId }).onConflictDoNothing();
		}
		await audit(services, tx, request, {
			action: "channel.update",
			actorId: actor.userId,
			workspaceId: current.workspaceId,
			targetType: "channel",
			targetId: channelId,
			data: { ...input },
		});
		return row;
	});
	publishChannelEvent(services, channel, "channel.update");
	return serializeChannel(channel);
}

/**
 * Deletes one workspace channel: hidden at once, then a job deletes its
 * messages and files. Only rows with this channel's id are ever touched.
 */
export async function deleteChannel(services: Services, request: FastifyRequest, actor: Actor, channelId: bigint) {
	const channel = await services.db.transaction(async (tx) => {
		const access = await requireChannelPermission(tx, channelId, actor.userId, Permission.MANAGE_CHANNELS);
		if (isConversation(access.channel)) throw badRequest("Leave a conversation instead of deleting it");
		await tx.update(channels).set({ deletedAt: new Date() }).where(eq(channels.id, channelId));
		// Channels in a deleted category move to the top level
		await tx.update(channels).set({ parentId: null }).where(eq(channels.parentId, channelId));
		await enqueue(tx, "channel.purge", { channelId });
		await audit(services, tx, request, {
			action: "channel.delete",
			actorId: actor.userId,
			workspaceId: access.channel.workspaceId,
			targetType: "channel",
			targetId: channelId,
			data: { name: access.channel.name },
		});
		return access.channel;
	});
	publishChannelEvent(services, channel, "channel.delete");
}

type OverwriteTarget = { type: "role" | "member"; id: bigint };

export async function setOverwrite(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	channelId: bigint,
	target: OverwriteTarget,
	bits: { allow: bigint; deny: bigint },
) {
	const workspaceId = await services.db.transaction(async (tx) => {
		const access = await requireChannelPermission(tx, channelId, actor.userId, Permission.MANAGE_ROLES);
		if (isConversation(access.channel)) throw badRequest("Conversations have no permission overwrites");
		if (!isValidOverwriteBits(bits.allow) || !isValidOverwriteBits(bits.deny)) throw badRequest("Invalid permission bits");
		if ((bits.allow & bits.deny) !== 0n) throw badRequest("A permission can't be both allowed and denied");
		// Nobody grants or takes away what they don't have themselves
		const workspace = access.workspace!;
		if (!workspace.member.isOwner && !has(workspace.permissions, Permission.ADMINISTRATOR)) {
			if (((bits.allow | bits.deny) & ~access.permissions) !== 0n) throw forbidden("You can't change permissions you don't have");
		}
		const workspaceId = access.channel.workspaceId!;
		if (target.type === "role") {
			const [role] = await tx
				.select({ id: roles.id })
				.from(roles)
				.where(and(eq(roles.id, target.id), eq(roles.workspaceId, workspaceId)));
			if (!role) throw notFound("Role");
		} else {
			const [member] = await tx
				.select({ userId: workspaceMembers.userId })
				.from(workspaceMembers)
				.where(and(eq(workspaceMembers.workspaceId, workspaceId), eq(workspaceMembers.userId, target.id)));
			if (!member) throw notFound("Member");
		}
		await tx
			.insert(permissionOverwrites)
			.values({ channelId, targetType: target.type, targetId: target.id, allow: bits.allow, deny: bits.deny })
			.onConflictDoUpdate({
				target: [permissionOverwrites.channelId, permissionOverwrites.targetType, permissionOverwrites.targetId],
				set: { allow: bits.allow, deny: bits.deny },
			});
		await audit(services, tx, request, {
			action: "channel.overwrite_set",
			actorId: actor.userId,
			workspaceId,
			targetType: "channel",
			targetId: channelId,
			data: { target: target.type, targetId: target.id, allow: bits.allow, deny: bits.deny },
		});
		return workspaceId;
	});
	publish(services, `workspace:${workspaceId}`, "channels.changed", { workspaceId, channelId });
}

export async function deleteOverwrite(services: Services, request: FastifyRequest, actor: Actor, channelId: bigint, target: OverwriteTarget) {
	const workspaceId = await services.db.transaction(async (tx) => {
		const access = await requireChannelPermission(tx, channelId, actor.userId, Permission.MANAGE_ROLES);
		const removed = await tx
			.delete(permissionOverwrites)
			.where(
				and(
					eq(permissionOverwrites.channelId, channelId),
					eq(permissionOverwrites.targetType, target.type),
					eq(permissionOverwrites.targetId, target.id),
				),
			)
			.returning();
		if (removed.length === 0) throw notFound("Overwrite");
		await audit(services, tx, request, {
			action: "channel.overwrite_delete",
			actorId: actor.userId,
			workspaceId: access.channel.workspaceId,
			targetType: "channel",
			targetId: channelId,
			data: { target: target.type, targetId: target.id },
		});
		return access.channel.workspaceId;
	});
	publish(services, `workspace:${workspaceId}`, "channels.changed", { workspaceId, channelId });
}

export async function listOverwrites(services: Services, actor: Actor, channelId: bigint) {
	await requireChannelPermission(services.db, channelId, actor.userId, Permission.MANAGE_ROLES);
	return services.db.select().from(permissionOverwrites).where(eq(permissionOverwrites.channelId, channelId));
}

/** Who's in a private channel. */
export async function setPrivateMember(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	channelId: bigint,
	userId: bigint,
	add: boolean,
) {
	await services.db.transaction(async (tx) => {
		const access = await requireChannelPermission(tx, channelId, actor.userId, Permission.MANAGE_CHANNELS);
		if (isConversation(access.channel) || !access.channel.isPrivate) throw badRequest("Only private channels have members");
		if (add) {
			const [member] = await tx
				.select({ userId: workspaceMembers.userId })
				.from(workspaceMembers)
				.where(and(eq(workspaceMembers.workspaceId, access.channel.workspaceId!), eq(workspaceMembers.userId, userId)));
			if (!member) throw notFound("Member");
			await tx.insert(channelMembers).values({ channelId, userId }).onConflictDoNothing();
		} else {
			await tx.delete(channelMembers).where(and(eq(channelMembers.channelId, channelId), eq(channelMembers.userId, userId)));
		}
		await audit(services, tx, request, {
			action: add ? "channel.member_add" : "channel.member_remove",
			actorId: actor.userId,
			workspaceId: access.channel.workspaceId,
			targetType: "channel",
			targetId: channelId,
			data: { userId },
		});
	});
	publish(services, `user:${userId}`, "channels.changed", { channelId });
}
