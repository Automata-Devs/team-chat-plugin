import { z } from "zod";
import { LIMITS } from "../../http/rateLimit.js";
import { actorOf, personOf, type Module } from "../../http/types.js";
import { httpsUrl, idParams, name, parse, permissionBits, snowflake, text, username } from "../../lib/validation.js";
import {
	BOT_EVENTS,
	createBot,
	deleteBot,
	getBot,
	installBot,
	invokeCommand,
	listBotCommands,
	listInstalledBots,
	listMyBots,
	resetSigningSecret,
	resetToken,
	setCommands,
	uninstallBot,
	updateBot,
	workspaceCommands,
} from "./service.js";

const eventsUrl = z.string().url().max(2048);
const config = z.record(z.unknown()).refine((value) => JSON.stringify(value).length <= 16_384, "config is too large");

const CreateBot = z
	.object({
		username,
		displayName: name(64).optional(),
		description: text(1000).optional(),
		avatarUrl: httpsUrl.optional(),
		isPublic: z.boolean().optional(),
		eventsUrl: eventsUrl.optional(),
		events: z.array(z.enum(BOT_EVENTS)).max(BOT_EVENTS.length).optional(),
		permissions: permissionBits.optional(),
		config: config.optional(),
	})
	.strict();
const UpdateBot = z
	.object({
		username: username.optional(),
		displayName: name(64).nullable().optional(),
		description: text(1000).nullable().optional(),
		avatarUrl: httpsUrl.nullable().optional(),
		isPublic: z.boolean().optional(),
		eventsUrl: eventsUrl.nullable().optional(),
		events: z.array(z.enum(BOT_EVENTS)).max(BOT_EVENTS.length).optional(),
		permissions: permissionBits.optional(),
		config: config.optional(),
		status: z.enum(["active", "disabled"]).optional(),
	})
	.strict();
const commandName = z.string().regex(/^[a-z0-9_-]{1,32}$/, "Lowercase letters, digits, _ and -");
const Commands = z
	.array(
		z
			.object({
				name: commandName,
				description: text(100).default(""),
				options: z
					.array(
						z
							.object({
								name: commandName,
								description: text(100).optional(),
								type: z.enum(["string", "number", "boolean", "user", "channel"]),
								required: z.boolean().optional(),
							})
							.strict(),
					)
					.max(25)
					.default([]),
			})
			.strict(),
	)
	.max(100);
const Install = z.object({ botId: snowflake, permissions: permissionBits.optional() }).strict();
const Invoke = z
	.object({
		botId: snowflake,
		command: commandName,
		options: z.record(z.union([z.string().max(4000), z.number(), z.boolean()])).default({}),
	})
	.strict();

export const botsModule: Module = (app, services) => {
	const admin = { limit: LIMITS.botAdmin };

	/** Returns the token and signing secret once; only their hash and ciphertext are kept. */
	app.post("/bots", { config: admin }, async (request, reply) => {
		return reply.status(201).send(await createBot(services, request, personOf(request), parse(CreateBot, request.body)));
	});

	app.get("/bots", async (request) => ({ bots: await listMyBots(services, actorOf(request)) }));

	app.get("/bots/:botId", { config: { auth: "any" } }, async (request) => {
		const { botId } = parse(idParams("botId"), request.params);
		return { bot: await getBot(services, actorOf(request), botId) };
	});

	app.patch("/bots/:botId", async (request) => {
		const { botId } = parse(idParams("botId"), request.params);
		return { bot: await updateBot(services, request, actorOf(request), botId, parse(UpdateBot, request.body)) };
	});

	app.delete("/bots/:botId", async (request, reply) => {
		const { botId } = parse(idParams("botId"), request.params);
		await deleteBot(services, request, actorOf(request), botId);
		return reply.status(204).send();
	});

	app.post("/bots/:botId/token", { config: admin }, async (request) => {
		const { botId } = parse(idParams("botId"), request.params);
		return resetToken(services, request, actorOf(request), botId);
	});

	app.post("/bots/:botId/signing-secret", { config: admin }, async (request) => {
		const { botId } = parse(idParams("botId"), request.params);
		return resetSigningSecret(services, request, actorOf(request), botId);
	});

	// Commands can be set by the owner or by the bot itself (with its token)
	app.get("/bots/:botId/commands", { config: { auth: "any" } }, async (request) => {
		const { botId } = parse(idParams("botId"), request.params);
		return { commands: await listBotCommands(services, actorOf(request), botId) };
	});

	app.put("/bots/:botId/commands", { config: { auth: "any" } }, async (request, reply) => {
		const { botId } = parse(idParams("botId"), request.params);
		await setCommands(services, actorOf(request), botId, null, parse(Commands, request.body));
		return reply.status(204).send();
	});

	app.put("/bots/:botId/workspaces/:workspaceId/commands", { config: { auth: "any" } }, async (request, reply) => {
		const { botId, workspaceId } = parse(idParams("botId", "workspaceId"), request.params);
		await setCommands(services, actorOf(request), botId, workspaceId, parse(Commands, request.body));
		return reply.status(204).send();
	});

	app.get("/workspaces/:workspaceId/commands", { config: { auth: "any" } }, async (request) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return { commands: await workspaceCommands(services, actorOf(request), workspaceId) };
	});

	app.get("/workspaces/:workspaceId/bots", { config: { auth: "any" } }, async (request) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return { bots: await listInstalledBots(services, actorOf(request), workspaceId) };
	});

	app.post("/workspaces/:workspaceId/bots", async (request, reply) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		const body = parse(Install, request.body);
		await installBot(services, request, actorOf(request), workspaceId, body.botId, body.permissions);
		return reply.status(204).send();
	});

	app.delete("/workspaces/:workspaceId/bots/:botId", async (request, reply) => {
		const { workspaceId, botId } = parse(idParams("workspaceId", "botId"), request.params);
		await uninstallBot(services, request, actorOf(request), workspaceId, botId);
		return reply.status(204).send();
	});

	/** Runs a bot's command in a channel; the bot answers with a message carrying the interactionId. */
	app.post("/channels/:channelId/interactions", { config: { limit: LIMITS.sendMessage } }, async (request, reply) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		return reply.status(202).send(await invokeCommand(services, actorOf(request), channelId, parse(Invoke, request.body)));
	});
};
