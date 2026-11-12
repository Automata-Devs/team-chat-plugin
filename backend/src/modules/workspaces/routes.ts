import { z } from "zod";
import { actorOf, personOf, type Module } from "../../http/types.js";
import { httpsUrl, idParams, limit, name, parse, permissionBits, snowflake, text } from "../../lib/validation.js";
import {
	acceptInvite,
	createInvite,
	createRole,
	createWorkspace,
	deleteInvite,
	deleteRole,
	deleteWorkspace,
	getWorkspace,
	leaveOrKick,
	listInvites,
	listMembers,
	listMyWorkspaces,
	listRoles,
	previewInvite,
	setMemberRole,
	setNickname,
	transferOwnership,
	updateRole,
	updateWorkspace,
} from "./service.js";

const CreateWorkspace = z
	.object({ name: name(100, 2), description: text(1000).optional(), iconUrl: httpsUrl.optional() })
	.strict();
const UpdateWorkspace = z
	.object({ name: name(100, 2).optional(), description: text(1000).nullable().optional(), iconUrl: httpsUrl.nullable().optional() })
	.strict();
const Transfer = z.object({ userId: snowflake }).strict();
const Members = z.object({ after: snowflake.optional(), limit: limit(100, 1000) });
const Nickname = z.object({ nickname: name(32).nullable() }).strict();
const Invite = z
	.object({
		maxUses: z.number().int().min(1).max(1000).optional(),
		expiresInSeconds: z.number().int().min(60).max(30 * 86_400).optional(),
	})
	.strict();
const InviteCode = z.object({ code: z.string().regex(/^[A-Za-z0-9_-]{6,32}$/) });
const Role = z
	.object({
		name: name(100),
		color: z.number().int().min(0).max(0xffffff).optional(),
		permissions: permissionBits.optional(),
		position: z.number().int().min(1).max(10_000).optional(),
		mentionable: z.boolean().optional(),
	})
	.strict();

export const workspacesModule: Module = (app, services) => {
	app.post("/workspaces", async (request, reply) => {
		const workspace = await createWorkspace(services, request, actorOf(request), parse(CreateWorkspace, request.body));
		return reply.status(201).send({ workspace });
	});

	app.get("/workspaces", { config: { auth: "any" } }, async (request) => ({
		workspaces: await listMyWorkspaces(services, actorOf(request)),
	}));

	app.get("/workspaces/:workspaceId", { config: { auth: "any" } }, async (request) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return { workspace: await getWorkspace(services, actorOf(request), workspaceId) };
	});

	app.patch("/workspaces/:workspaceId", async (request) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return { workspace: await updateWorkspace(services, request, actorOf(request), workspaceId, parse(UpdateWorkspace, request.body)) };
	});

	app.delete("/workspaces/:workspaceId", async (request, reply) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		await deleteWorkspace(services, request, actorOf(request), workspaceId);
		return reply.status(204).send();
	});

	app.post("/workspaces/:workspaceId/transfer", async (request, reply) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		await transferOwnership(services, request, actorOf(request), workspaceId, parse(Transfer, request.body).userId);
		return reply.status(204).send();
	});

	app.get("/workspaces/:workspaceId/members", { config: { auth: "any" } }, async (request) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return { members: await listMembers(services, actorOf(request), workspaceId, parse(Members, request.query)) };
	});

	app.patch("/workspaces/:workspaceId/members/@me", async (request, reply) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		await setNickname(services, actorOf(request), workspaceId, parse(Nickname, request.body).nickname);
		return reply.status(204).send();
	});

	app.delete("/workspaces/:workspaceId/members/:userId", async (request, reply) => {
		const { workspaceId, userId } = parse(idParams("workspaceId", "userId"), request.params);
		await leaveOrKick(services, request, actorOf(request), workspaceId, userId);
		return reply.status(204).send();
	});

	app.put("/workspaces/:workspaceId/members/:userId/roles/:roleId", async (request, reply) => {
		const { workspaceId, userId, roleId } = parse(idParams("workspaceId", "userId", "roleId"), request.params);
		await setMemberRole(services, request, actorOf(request), workspaceId, userId, roleId, true);
		return reply.status(204).send();
	});

	app.delete("/workspaces/:workspaceId/members/:userId/roles/:roleId", async (request, reply) => {
		const { workspaceId, userId, roleId } = parse(idParams("workspaceId", "userId", "roleId"), request.params);
		await setMemberRole(services, request, actorOf(request), workspaceId, userId, roleId, false);
		return reply.status(204).send();
	});

	app.get("/workspaces/:workspaceId/roles", { config: { auth: "any" } }, async (request) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return { roles: await listRoles(services, actorOf(request), workspaceId) };
	});

	app.post("/workspaces/:workspaceId/roles", async (request, reply) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return reply.status(201).send({ role: await createRole(services, request, actorOf(request), workspaceId, parse(Role, request.body)) });
	});

	app.patch("/workspaces/:workspaceId/roles/:roleId", async (request) => {
		const { workspaceId, roleId } = parse(idParams("workspaceId", "roleId"), request.params);
		return { role: await updateRole(services, request, actorOf(request), workspaceId, roleId, parse(Role.partial(), request.body)) };
	});

	app.delete("/workspaces/:workspaceId/roles/:roleId", async (request, reply) => {
		const { workspaceId, roleId } = parse(idParams("workspaceId", "roleId"), request.params);
		await deleteRole(services, request, actorOf(request), workspaceId, roleId);
		return reply.status(204).send();
	});

	app.post("/workspaces/:workspaceId/invites", async (request, reply) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return reply.status(201).send({ invite: await createInvite(services, actorOf(request), workspaceId, parse(Invite, request.body ?? {})) });
	});

	app.get("/workspaces/:workspaceId/invites", async (request) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		return { invites: await listInvites(services, actorOf(request), workspaceId) };
	});

	app.get("/invites/:code", async (request) => previewInvite(services, parse(InviteCode, request.params).code));

	app.post("/invites/:code", async (request) => ({
		workspace: await acceptInvite(services, request, personOf(request), parse(InviteCode, request.params).code),
	}));

	app.delete("/invites/:code", async (request, reply) => {
		await deleteInvite(services, actorOf(request), parse(InviteCode, request.params).code);
		return reply.status(204).send();
	});
};
