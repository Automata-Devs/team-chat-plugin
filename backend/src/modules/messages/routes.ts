import { z } from "zod";
import { LIMITS } from "../../http/rateLimit.js";
import { actorOf, type Module } from "../../http/types.js";
import { idParams, parse, snowflake } from "../../lib/validation.js";
import {
	acknowledge,
	createMessage,
	deleteMessage,
	editMessage,
	getMessage,
	listMessages,
	listPins,
	pinMessage,
	unpinMessage,
} from "./service.js";
import { CreateMessage, EditMessage, ListMessages } from "./shapes.js";

const Ack = z.object({ messageId: snowflake.optional() }).strict();

export const messagesModule: Module = (app, services) => {
	const any = { auth: "any" as const };

	app.get("/channels/:channelId/messages", { config: any }, async (request) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		return { messages: await listMessages(services, actorOf(request), channelId, parse(ListMessages, request.query)) };
	});

	app.post("/channels/:channelId/messages", { config: { ...any, limit: LIMITS.sendMessage } }, async (request, reply) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		const message = await createMessage(services, actorOf(request), channelId, parse(CreateMessage, request.body));
		return reply.status(201).send({ message });
	});

	app.get("/channels/:channelId/messages/:messageId", { config: any }, async (request) => {
		const { channelId, messageId } = parse(idParams("channelId", "messageId"), request.params);
		return { message: await getMessage(services, actorOf(request), channelId, messageId) };
	});

	app.patch("/channels/:channelId/messages/:messageId", { config: any }, async (request) => {
		const { channelId, messageId } = parse(idParams("channelId", "messageId"), request.params);
		return { message: await editMessage(services, actorOf(request), channelId, messageId, parse(EditMessage, request.body)) };
	});

	app.delete("/channels/:channelId/messages/:messageId", { config: any }, async (request, reply) => {
		const { channelId, messageId } = parse(idParams("channelId", "messageId"), request.params);
		await deleteMessage(services, request, actorOf(request), channelId, messageId);
		return reply.status(204).send();
	});

	app.get("/channels/:channelId/pins", { config: any }, async (request) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		return { messages: await listPins(services, actorOf(request), channelId) };
	});

	app.put("/channels/:channelId/pins/:messageId", { config: any }, async (request, reply) => {
		const { channelId, messageId } = parse(idParams("channelId", "messageId"), request.params);
		await pinMessage(services, actorOf(request), channelId, messageId);
		return reply.status(204).send();
	});

	app.delete("/channels/:channelId/pins/:messageId", { config: any }, async (request, reply) => {
		const { channelId, messageId } = parse(idParams("channelId", "messageId"), request.params);
		await unpinMessage(services, actorOf(request), channelId, messageId);
		return reply.status(204).send();
	});

	app.post("/channels/:channelId/ack", async (request) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		const body = parse(Ack, request.body ?? {});
		return { readState: await acknowledge(services, actorOf(request), channelId, body.messageId) };
	});
};
