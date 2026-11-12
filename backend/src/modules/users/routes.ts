import { z } from "zod";
import { actorOf, personOf, type Module } from "../../http/types.js";
import { httpsUrl, idParams, name, parse, username } from "../../lib/validation.js";
import { deleteMe, getMe, getUser, listRelationships, removeRelationship, setRelationship, updateMe } from "./service.js";

const UpdateMe = z
	.object({ username: username.optional(), displayName: name(64).nullable().optional(), avatarUrl: httpsUrl.nullable().optional() })
	.strict();
const DeleteMe = z.object({ password: z.string().max(256).optional() }).strict();
const Relationship = z.object({ type: z.enum(["block", "mute"]) }).strict();

export const usersModule: Module = (app, services) => {
	app.get("/users/@me", { config: { auth: "any" } }, async (request) => ({ user: await getMe(services, actorOf(request)) }));

	app.patch("/users/@me", async (request) => ({
		user: await updateMe(services, request, personOf(request), parse(UpdateMe, request.body)),
	}));

	app.delete("/users/@me", async (request, reply) => {
		await deleteMe(services, request, personOf(request), parse(DeleteMe, request.body ?? {}).password);
		return reply.status(204).send();
	});

	app.get("/users/@me/relationships", async (request) => ({ relationships: await listRelationships(services, actorOf(request)) }));

	app.put("/users/@me/relationships/:userId", async (request, reply) => {
		const { userId } = parse(idParams("userId"), request.params);
		await setRelationship(services, actorOf(request), userId, parse(Relationship, request.body).type);
		return reply.status(204).send();
	});

	app.delete("/users/@me/relationships/:userId", async (request, reply) => {
		const { userId } = parse(idParams("userId"), request.params);
		await removeRelationship(services, actorOf(request), userId, parse(Relationship, request.query).type);
		return reply.status(204).send();
	});

	app.get("/users/:userId", { config: { auth: "any" } }, async (request) => {
		const { userId } = parse(idParams("userId"), request.params);
		return { user: await getUser(services, userId) };
	});
};
