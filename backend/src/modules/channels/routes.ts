import { z } from "zod";
import { actorOf, type Module } from "../../http/types.js";
import { idParams, name, parse, permissionBits, snowflake, text } from "../../lib/validation.js";
import {
	createChannel,
	deleteChannel,
	deleteOverwrite,
	getChannel,
	listChannels,
	listOverwrites,
	setOverwrite,
	setPrivateMember,
	updateChannel,
} from "./service.js";

const fields = {
	name: name(100),
	topic: text(1024).nullable().optional(),
	parentId: snowflake.nullable().optional(),
	position: z.number().int().min(0).max(10_000).optional(),
	isPrivate: z.boolean().optional(),
	slowmodeSeconds: z.number().int().min(0).max(21_600).optional(),
};
const CreateChannel = z.object({ type: z.enum(["text", "category"]).default("text"), ...fields }).strict();
const UpdateChannel = z.object({ ...fields, name: fields.name.optional() }).strict();
const OverwriteParams = z.object({ channelId: snowflake, targetType: z.enum(["role", "member"]), targetId: snowflake });
const Overwrite = z.object({ allow: permissionBits.default("0"), deny: permissionBits.default("0") }).strict();

export const channelsModule: Module = (app, services) => {
	app.get("/workspaces/:workspaceId/channels", { config: { auth: "any" } }, async (request) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return { channels: await listChannels(services, actorOf(request), workspaceId) };
	});

	app.post("/workspaces/:workspaceId/channels", async (request, reply) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		const channel = await createChannel(services, request, actorOf(request), workspaceId, parse(CreateChannel, request.body));
		return reply.status(201).send({ channel });
	});

	app.get("/channels/:channelId", { config: { auth: "any" } }, async (request) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		return { channel: await getChannel(services, actorOf(request), channelId) };
	});

	app.patch("/channels/:channelId", async (request) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		return { channel: await updateChannel(services, request, actorOf(request), channelId, parse(UpdateChannel, request.body)) };
	});

	app.delete("/channels/:channelId", async (request, reply) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		await deleteChannel(services, request, actorOf(request), channelId);
		return reply.status(204).send();
	});

	app.get("/channels/:channelId/permissions", async (request) => {
		const { channelId } = parse(idParams("channelId"), request.params);
		return { overwrites: await listOverwrites(services, actorOf(request), channelId) };
	});

	app.put("/channels/:channelId/permissions/:targetType/:targetId", async (request, reply) => {
		const params = parse(OverwriteParams, request.params);
		await setOverwrite(
			services,
			request,
			actorOf(request),
			params.channelId,
			{ type: params.targetType, id: params.targetId },
			parse(Overwrite, request.body),
		);
		return reply.status(204).send();
	});

	app.delete("/channels/:channelId/permissions/:targetType/:targetId", async (request, reply) => {
		const params = parse(OverwriteParams, request.params);
		await deleteOverwrite(services, request, actorOf(request), params.channelId, { type: params.targetType, id: params.targetId });
		return reply.status(204).send();
	});

	app.put("/channels/:channelId/members/:userId", async (request, reply) => {
		const { channelId, userId } = parse(idParams("channelId", "userId"), request.params);
		await setPrivateMember(services, request, actorOf(request), channelId, userId, true);
		return reply.status(204).send();
	});

	app.delete("/channels/:channelId/members/:userId", async (request, reply) => {
		const { channelId, userId } = parse(idParams("channelId", "userId"), request.params);
		await setPrivateMember(services, request, actorOf(request), channelId, userId, false);
		return reply.status(204).send();
	});
};
