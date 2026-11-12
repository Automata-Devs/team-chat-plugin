import { z } from "zod";
import { actorOf, type Module } from "../../http/types.js";
import { httpsUrl, idParams, limit, name, parse, snowflake } from "../../lib/validation.js";
import {
	addRecipient,
	getConversation,
	leaveOrRemove,
	listConversations,
	openConversation,
	updateChannelSettings,
	updateConversation,
} from "./service.js";

const Open = z.object({ recipients: z.array(snowflake).min(1).max(9), name: name(100).optional() }).strict();
const List = z.object({
	archived: z.enum(["true", "false"]).default("false").transform((v) => v === "true"),
	before: snowflake.optional(),
	limit: limit(50, 100),
});
const Update = z.object({ name: name(100).nullable().optional(), iconUrl: httpsUrl.nullable().optional() }).strict();
const ChannelSettings = z
	.object({
		muted: z.boolean().optional(),
		mutedUntil: z.coerce.date().nullable().optional(),
		notificationLevel: z.enum(["all", "mentions", "none"]).nullable().optional(),
		archived: z.boolean().optional(),
	})
	.strict();

export const conversationsModule: Module = (app, services) => {
	/** Opens a DM (one recipient; returns the existing one if there is one) or starts a group. */
	app.post("/conversations", async (request, reply) => {
		return reply.status(201).send({ conversation: await openConversation(services, actorOf(request), parse(Open, request.body)) });
	});

	app.get("/conversations", async (request) => ({
		conversations: await listConversations(services, actorOf(request), parse(List, request.query)),
	}));

	app.get("/conversations/:channelId", async (request) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		return { conversation: await getConversation(services, actorOf(request), channelId) };
	});

	app.patch("/conversations/:channelId", async (request) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		return { conversation: await updateConversation(services, actorOf(request), channelId, parse(Update, request.body)) };
	});

	app.put("/conversations/:channelId/recipients/:userId", async (request, reply) => {
		const { channelId, userId } = parse(idParams("channelId", "userId"), request.params);
		await addRecipient(services, actorOf(request), channelId, userId);
		return reply.status(204).send();
	});

	/** Your own id: leave. Someone else's: remove them (owner only). */
	app.delete("/conversations/:channelId/recipients/:userId", async (request, reply) => {
		const { channelId, userId } = parse(idParams("channelId", "userId"), request.params);
		await leaveOrRemove(services, actorOf(request), channelId, userId);
		return reply.status(204).send();
	});

	/** Your own mute, notification level and archive state for a channel or conversation. */
	app.patch("/channels/:channelId/settings", async (request) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		return { settings: await updateChannelSettings(services, actorOf(request), channelId, parse(ChannelSettings, request.body)) };
	});
};
