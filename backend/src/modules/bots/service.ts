import { and, eq, isNull, or, sql } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import type { Actor, Services } from "../../context.js";
import { pgCode, type Tx, UNIQUE_VIOLATION } from "../../db/client.js";
import { botCommands, botInstallations, bots, channels, memberRoles, roles, users, workspaceMembers } from "../../db/schema.js";
import { forgetToken } from "../../http/auth.js";
import { enqueue } from "../../infra/jobs.js";
import { hmacSha256Hex, randomToken, sha256 } from "../../lib/crypto.js";
import { badRequest, conflict, forbidden, notFound } from "../../lib/errors.js";
import { Permission, has, isValidRoleBits } from "../../lib/permissions.js";
import { assertPublicUrl } from "../../lib/urls.js";
import { readersOf, requireChannelPermission, requireWorkspacePermission, workspaceAccess } from "../access.js";
import { audit, publicUser, publish } from "../shared.js";
import { removeBotEverywhere } from "../users/service.js";

export const BOT_EVENTS = ["message.create", "message.update", "message.delete", "reaction.add", "member.add"] as const;
const MAX_BOTS_PER_OWNER = 25;
const INTERACTION_SECONDS = 15 * 60;
const DEFAULT_BOT_PERMISSIONS = Permission.VIEW_CHANNEL | Permission.SEND_MESSAGES | Permission.READ_MESSAGE_HISTORY;

type BotRow = typeof bots.$inferSelect;
type UserRow = typeof users.$inferSelect;

/** The owner's view; never includes the token or the signing secret. */
function ownerView(bot: BotRow, user: UserRow) {
	return {
		...publicUser(user),
		ownerId: bot.ownerId,
		description: bot.description,
		isPublic: bot.isPublic,
		status: bot.status,
		eventsUrl: bot.eventsUrl,
		events: bot.events,
		permissions: bot.permissions.toString(),
		config: bot.config,
		tokenCreatedAt: bot.tokenCreatedAt,
		lastActiveAt: bot.lastActiveAt,
	};
}

/** "<bot id, base64url>.<secret>": the first part shows which bot a leaked token belongs to. */
function newToken(botId: bigint) {
	const token = `${Buffer.from(botId.toString()).toString("base64url")}.${randomToken(32)}`;
	return { token, hash: sha256(token) };
}

async function checkEventsUrl(services: Services, url: string | null | undefined) {
	if (url) await assertPublicUrl(url, { allowInsecure: services.config.ALLOW_INSECURE_BOT_URLS, resolveHost: services.resolveHost });
}

export interface BotInput {
	username: string;
	displayName?: string | null;
	description?: string | null;
	avatarUrl?: string | null;
	isPublic?: boolean;
	eventsUrl?: string | null;
	events?: string[];
	permissions?: bigint;
	config?: Record<string, unknown>;
}

export async function createBot(services: Services, request: FastifyRequest, actor: Actor, input: BotInput) {
	await checkEventsUrl(services, input.eventsUrl);
	if (input.permissions !== undefined && !isValidRoleBits(input.permissions)) throw badRequest("Unknown permission bits");
	try {
		return await services.db.transaction(async (tx) => {
			const [{ count }] = await tx
				.select({ count: sql<number>`count(*)::int` })
				.from(bots)
				.innerJoin(users, eq(users.id, bots.userId))
				.where(and(eq(bots.ownerId, actor.userId), eq(users.status, "active")));
			if (count >= MAX_BOTS_PER_OWNER) throw badRequest(`You can have at most ${MAX_BOTS_PER_OWNER} bots`);

			const id = services.ids.next();
			const { token, hash } = newToken(id);
			const signingSecret = randomToken(32);
			const [user] = await tx
				.insert(users)
				.values({ id, username: input.username, displayName: input.displayName ?? null, avatarUrl: input.avatarUrl ?? null, isBot: true })
				.returning();
			const [bot] = await tx
				.insert(bots)
				.values({
					userId: id,
					ownerId: actor.userId,
					description: input.description ?? null,
					isPublic: input.isPublic ?? false,
					tokenHash: hash,
					eventsUrl: input.eventsUrl ?? null,
					events: input.events ?? [],
					signingSecret: services.secrets.encrypt(signingSecret),
					permissions: input.permissions ?? DEFAULT_BOT_PERMISSIONS,
					config: input.config ?? {},
				})
				.returning();
			await audit(services, tx, request, { action: "bot.create", actorId: actor.userId, targetType: "bot", targetId: id });
			// Shown once: only the token's hash and the secret's ciphertext are kept
			return { bot: ownerView(bot, user), token, signingSecret };
		});
	} catch (error) {
		if (pgCode(error) === UNIQUE_VIOLATION) throw conflict("That username is taken");
		throw error;
	}
}

/** A bot its owner (or the bot itself) may manage. */
async function manageableBot(tx: Tx, botId: bigint, actor: Actor) {
	const [row] = await tx
		.select({ bot: bots, user: users })
		.from(bots)
		.innerJoin(users, eq(users.id, bots.userId))
		.where(and(eq(bots.userId, botId), eq(users.status, "active")));
	const allowed = row && (row.bot.ownerId === actor.userId || (actor.kind === "bot" && actor.userId === botId));
	if (!allowed) throw notFound("Bot");
	return row;
}

async function ownersBot(tx: Tx, botId: bigint, actor: Actor) {
	const row = await manageableBot(tx, botId, actor);
	if (row.bot.ownerId !== actor.userId) throw forbidden("Only the bot's owner can do that");
	return row;
}

export async function listMyBots(services: Services, actor: Actor) {
	const rows = await services.db
		.select({ bot: bots, user: users })
		.from(bots)
		.innerJoin(users, eq(users.id, bots.userId))
		.where(and(eq(bots.ownerId, actor.userId), eq(users.status, "active")));
	return rows.map((r) => ownerView(r.bot, r.user));
}

export async function getBot(services: Services, actor: Actor, botId: bigint) {
	const [row] = await services.db
		.select({ bot: bots, user: users })
		.from(bots)
		.innerJoin(users, eq(users.id, bots.userId))
		.where(and(eq(bots.userId, botId), eq(users.status, "active")));
	if (!row) throw notFound("Bot");
	if (row.bot.ownerId === actor.userId || actor.userId === botId) return ownerView(row.bot, row.user);
	if (!row.bot.isPublic) throw notFound("Bot");
	return { ...publicUser(row.user), description: row.bot.description, isPublic: true, permissions: row.bot.permissions.toString() };
}

export async function updateBot(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	botId: bigint,
	input: Partial<BotInput> & { status?: "active" | "disabled" },
) {
	await checkEventsUrl(services, input.eventsUrl);
	if (input.permissions !== undefined && !isValidRoleBits(input.permissions)) throw badRequest("Unknown permission bits");
	let result: { view: ReturnType<typeof ownerView>; tokenHash: Buffer };
	try {
		result = await services.db.transaction(async (tx) => {
			await ownersBot(tx, botId, actor);
			const userChanges = { username: input.username, displayName: input.displayName, avatarUrl: input.avatarUrl };
			if (Object.values(userChanges).some((v) => v !== undefined)) await tx.update(users).set(userChanges).where(eq(users.id, botId));
			const [updated] = await tx
				.update(bots)
				.set({
					description: input.description,
					isPublic: input.isPublic,
					eventsUrl: input.eventsUrl,
					events: input.events,
					permissions: input.permissions,
					config: input.config,
					status: input.status,
				})
				.where(eq(bots.userId, botId))
				.returning();
			const [user] = await tx.select().from(users).where(eq(users.id, botId));
			await audit(services, tx, request, { action: "bot.update", actorId: actor.userId, targetType: "bot", targetId: botId, data: { status: input.status } });
			return { view: ownerView(updated, user), tokenHash: updated.tokenHash };
		});
	} catch (error) {
		if (pgCode(error) === UNIQUE_VIOLATION) throw conflict("That username is taken");
		throw error;
	}
	// A disabled bot's token stops working at once
	await forgetToken(services, result.tokenHash, "bot");
	return result.view;
}

export async function resetToken(services: Services, request: FastifyRequest, actor: Actor, botId: bigint) {
	const { token, oldHash } = await services.db.transaction(async (tx) => {
		const { bot } = await ownersBot(tx, botId, actor);
		const fresh = newToken(botId);
		await tx.update(bots).set({ tokenHash: fresh.hash, tokenCreatedAt: new Date() }).where(eq(bots.userId, botId));
		await audit(services, tx, request, { action: "bot.token_reset", actorId: actor.userId, targetType: "bot", targetId: botId });
		return { token: fresh.token, oldHash: bot.tokenHash };
	});
	await forgetToken(services, oldHash, "bot");
	return { token };
}

export async function resetSigningSecret(services: Services, request: FastifyRequest, actor: Actor, botId: bigint) {
	return services.db.transaction(async (tx) => {
		await ownersBot(tx, botId, actor);
		const signingSecret = randomToken(32);
		await tx.update(bots).set({ signingSecret: services.secrets.encrypt(signingSecret) }).where(eq(bots.userId, botId));
		await audit(services, tx, request, { action: "bot.secret_reset", actorId: actor.userId, targetType: "bot", targetId: botId });
		return { signingSecret };
	});
}

/** Deletes a bot: uninstalled everywhere, its token stops working, its messages stay (from a deleted user). */
export async function deleteBot(services: Services, request: FastifyRequest, actor: Actor, botId: bigint) {
	const hash = await services.db.transaction(async (tx) => {
		const { bot } = await ownersBot(tx, botId, actor);
		await removeBotEverywhere(tx, botId);
		await tx.delete(bots).where(eq(bots.userId, botId));
		await tx
			.update(users)
			.set({ status: "deleted", username: `deleted-${botId}`, displayName: null, avatarUrl: null, deletedAt: new Date() })
			.where(eq(users.id, botId));
		await audit(services, tx, request, { action: "bot.delete", actorId: actor.userId, targetType: "bot", targetId: botId });
		return bot.tokenHash;
	});
	await forgetToken(services, hash, "bot");
}

// ── Commands ─────────────────────────────────────────────────────────────

export interface CommandInput {
	name: string;
	description: string;
	options: Array<{ name: string; description?: string; type: "string" | "number" | "boolean" | "user" | "channel"; required?: boolean }>;
}

/** Replaces a bot's commands: global ones (workspaceId null) or one workspace's. */
export async function setCommands(services: Services, actor: Actor, botId: bigint, workspaceId: bigint | null, commands: CommandInput[]) {
	if (new Set(commands.map((c) => c.name)).size !== commands.length) throw badRequest("Command names must be unique");
	await services.db.transaction(async (tx) => {
		await manageableBot(tx, botId, actor);
		if (workspaceId !== null) {
			const [installed] = await tx
				.select()
				.from(botInstallations)
				.where(and(eq(botInstallations.workspaceId, workspaceId), eq(botInstallations.botId, botId)));
			if (!installed) throw notFound("Installation");
		}
		await tx
			.delete(botCommands)
			.where(and(eq(botCommands.botId, botId), workspaceId === null ? isNull(botCommands.workspaceId) : eq(botCommands.workspaceId, workspaceId)));
		if (commands.length > 0) {
			await tx.insert(botCommands).values(
				commands.map((c) => ({ id: services.ids.next(), botId, workspaceId, name: c.name, description: c.description, options: c.options })),
			);
		}
	});
	if (workspaceId !== null) publish(services, `workspace:${workspaceId}`, "commands.update", { workspaceId, botId });
}

export async function listBotCommands(services: Services, actor: Actor, botId: bigint) {
	await manageableBot(services.db, botId, actor);
	return services.db.select().from(botCommands).where(eq(botCommands.botId, botId));
}

/** Every command members can use in a workspace: installed bots' global ones and the workspace's own. */
export async function workspaceCommands(services: Services, actor: Actor, workspaceId: bigint) {
	await workspaceAccess(services.db, workspaceId, actor.userId);
	const rows = await services.db
		.select({ command: botCommands })
		.from(botCommands)
		.innerJoin(botInstallations, and(eq(botInstallations.botId, botCommands.botId), eq(botInstallations.workspaceId, workspaceId)))
		.where(or(isNull(botCommands.workspaceId), eq(botCommands.workspaceId, workspaceId)));
	return rows.map((r) => r.command);
}

// ── Installation ─────────────────────────────────────────────────────────

export async function installBot(
	services: Services,
	request: FastifyRequest,
	actor: Actor,
	workspaceId: bigint,
	botId: bigint,
	permissions?: bigint,
) {
	await services.db.transaction(async (tx) => {
		const access = await requireWorkspacePermission(tx, workspaceId, actor.userId, Permission.MANAGE_BOTS);
		const [row] = await tx
			.select({ bot: bots, user: users })
			.from(bots)
			.innerJoin(users, eq(users.id, bots.userId))
			.where(and(eq(bots.userId, botId), eq(users.status, "active")));
		if (!row || (!row.bot.isPublic && row.bot.ownerId !== actor.userId)) throw notFound("Bot");
		if (row.bot.status !== "active") throw badRequest("This bot is disabled");
		const granted = permissions ?? row.bot.permissions;
		if (!isValidRoleBits(granted)) throw badRequest("Unknown permission bits");
		if (!access.member.isOwner && (granted & ~access.permissions) !== 0n) throw forbidden("You can't give a bot permissions you don't have");
		if (has(granted, Permission.ADMINISTRATOR) && !access.member.isOwner) throw forbidden("Only the owner can make a bot an administrator");

		const [already] = await tx
			.select()
			.from(botInstallations)
			.where(and(eq(botInstallations.workspaceId, workspaceId), eq(botInstallations.botId, botId)));
		if (already) throw conflict("This bot is already in the workspace");

		// Its permissions live on a managed role, so channel overwrites apply to bots like to anyone
		const roleId = services.ids.next();
		await tx.insert(roles).values({ id: roleId, workspaceId, name: row.user.username, permissions: granted, position: 1, managed: true });
		await tx.insert(workspaceMembers).values({ workspaceId, userId: botId }).onConflictDoNothing();
		await tx.insert(memberRoles).values({ workspaceId, userId: botId, roleId });
		await tx.insert(botInstallations).values({ workspaceId, botId, roleId, installedBy: actor.userId });
		await audit(services, tx, request, {
			action: "bot.install",
			actorId: actor.userId,
			workspaceId,
			targetType: "bot",
			targetId: botId,
			data: { permissions: granted },
		});
		await enqueue(tx, "bot.event", { workspaceId, channelId: null, type: "member.add", data: { workspaceId, userId: botId } });
	});
	publish(services, `workspace:${workspaceId}`, "member.add", { workspaceId, userId: botId });
}

export async function uninstallBot(services: Services, request: FastifyRequest, actor: Actor, workspaceId: bigint, botId: bigint) {
	await services.db.transaction(async (tx) => {
		await requireWorkspacePermission(tx, workspaceId, actor.userId, Permission.MANAGE_BOTS);
		const [install] = await tx
			.delete(botInstallations)
			.where(and(eq(botInstallations.workspaceId, workspaceId), eq(botInstallations.botId, botId)))
			.returning();
		if (!install) throw notFound("Installation");
		await tx.delete(workspaceMembers).where(and(eq(workspaceMembers.workspaceId, workspaceId), eq(workspaceMembers.userId, botId)));
		await tx.delete(roles).where(eq(roles.id, install.roleId));
		await tx.delete(botCommands).where(and(eq(botCommands.botId, botId), eq(botCommands.workspaceId, workspaceId)));
		await audit(services, tx, request, { action: "bot.uninstall", actorId: actor.userId, workspaceId, targetType: "bot", targetId: botId });
	});
	publish(services, `workspace:${workspaceId}`, "member.remove", { workspaceId, userId: botId });
}

export async function listInstalledBots(services: Services, actor: Actor, workspaceId: bigint) {
	await workspaceAccess(services.db, workspaceId, actor.userId);
	const rows = await services.db
		.select({ install: botInstallations, user: users, bot: bots })
		.from(botInstallations)
		.innerJoin(users, eq(users.id, botInstallations.botId))
		.innerJoin(bots, eq(bots.userId, botInstallations.botId))
		.where(eq(botInstallations.workspaceId, workspaceId));
	return rows.map((r) => ({ ...publicUser(r.user), description: r.bot.description, roleId: r.install.roleId, installedAt: r.install.createdAt }));
}

// ── Commands being used, and events ──────────────────────────────────────

/** Someone runs a bot's command: the bot gets an interaction.create event and answers with a message. */
export async function invokeCommand(
	services: Services,
	actor: Actor,
	channelId: bigint,
	input: { botId: bigint; command: string; options: Record<string, unknown> },
) {
	const access = await requireChannelPermission(services.db, channelId, actor.userId, Permission.USE_COMMANDS | Permission.SEND_MESSAGES);
	const workspaceId = access.channel.workspaceId;
	if (!workspaceId) throw badRequest("Bots only work in workspace channels");
	const [found] = await services.db
		.select({ bot: bots })
		.from(botCommands)
		.innerJoin(botInstallations, and(eq(botInstallations.botId, botCommands.botId), eq(botInstallations.workspaceId, workspaceId)))
		.innerJoin(bots, eq(bots.userId, botCommands.botId))
		.where(
			and(
				eq(botCommands.botId, input.botId),
				eq(botCommands.name, input.command),
				or(isNull(botCommands.workspaceId), eq(botCommands.workspaceId, workspaceId)),
			),
		)
		.limit(1);
	if (!found || found.bot.status !== "active") throw notFound("Command");
	if (!found.bot.eventsUrl) throw badRequest("That bot has no events URL to receive commands");
	if (!(await readersOf(services.db, access.channel, [input.botId])).has(input.botId)) throw forbidden("That bot can't see this channel");

	const interactionId = services.ids.next().toString();
	await services.cache.set(
		`interaction:${interactionId}`,
		JSON.stringify({ botId: String(input.botId), channelId: String(channelId), userId: String(actor.userId), command: input.command }),
		INTERACTION_SECONDS,
	);
	const [user] = await services.db.select().from(users).where(eq(users.id, actor.userId));
	await enqueue(
		services.db,
		"bot.deliver",
		{
			botId: input.botId,
			event: {
				type: "interaction.create",
				workspaceId,
				channelId,
				data: { id: interactionId, channelId, workspaceId, user: publicUser(user), command: input.command, options: input.options },
			},
		},
		{ maxAttempts: 2 },
	);
	return { interactionId };
}

/** POSTs one event to a bot, signed: X-TeamChat-Signature = hex HMAC-SHA256(secret, "<timestamp>.<body>"). */
export async function deliverToBot(services: Services, botId: bigint, event: { type: string; [key: string]: unknown }) {
	const [bot] = await services.db.select().from(bots).where(eq(bots.userId, botId));
	if (!bot || bot.status !== "active" || !bot.eventsUrl) return;
	if (event.type !== "interaction.create" && !bot.events.includes(event.type)) return;
	// Checked again at send time: the name may resolve somewhere else now
	const url = await assertPublicUrl(bot.eventsUrl, { allowInsecure: services.config.ALLOW_INSECURE_BOT_URLS, resolveHost: services.resolveHost });

	const timestamp = Math.floor(Date.now() / 1000).toString();
	const body = JSON.stringify({ id: services.ids.next(), ...event, sentAt: new Date() }, (_k, v) => (typeof v === "bigint" ? v.toString() : v));
	const signature = hmacSha256Hex(services.secrets.decrypt(bot.signingSecret), `${timestamp}.${body}`);
	const response = await services.fetch(url, {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			"User-Agent": "TeamChat-Bot-Events/1",
			"X-TeamChat-Timestamp": timestamp,
			"X-TeamChat-Signature": signature,
		},
		body,
		redirect: "error",
		signal: AbortSignal.timeout(10_000),
	});
	if (!response.ok) throw new Error(`Bot ${botId} answered ${response.status}`);
}

/** Fans an event out to every installed bot subscribed to it that can see the channel. */
export async function queueBotEvent(
	services: Services,
	payload: { workspaceId: string | null; channelId: string | null; type: string; data: Record<string, unknown>; authorId?: string },
) {
	if (!payload.workspaceId) return;
	const subscribed = await services.db
		.select({ botId: bots.userId })
		.from(botInstallations)
		.innerJoin(bots, eq(bots.userId, botInstallations.botId))
		.where(
			and(
				eq(botInstallations.workspaceId, BigInt(payload.workspaceId)),
				eq(bots.status, "active"),
				sql`${bots.eventsUrl} is not null`,
				sql`${payload.type} = any(${bots.events})`,
			),
		);
	let botIds = subscribed.map((b) => b.botId).filter((id) => String(id) !== payload.authorId);
	if (botIds.length === 0) return;
	if (payload.channelId) {
		const [channel] = await services.db.select().from(channels).where(eq(channels.id, BigInt(payload.channelId)));
		if (!channel || channel.deletedAt) return;
		const readers = await readersOf(services.db, channel, botIds);
		botIds = botIds.filter((id) => readers.has(id));
	}
	if (botIds.length === 0) return;
	await services.db.transaction(async (tx) => {
		for (const botId of botIds) {
			await enqueue(tx, "bot.deliver", {
				botId,
				event: { type: payload.type, workspaceId: payload.workspaceId, channelId: payload.channelId, data: payload.data },
			});
		}
	});
}
