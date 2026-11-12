import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { Permission } from "../src/lib/permissions.js";
import { call, createTestApp, register, send, type TestContext, workspaceWith } from "./helpers.js";

let ctx: TestContext;
beforeAll(async () => {
	ctx = await createTestApp();
});
afterAll(() => ctx.close());

const bits = (...names: (keyof typeof Permission)[]) => names.reduce((all, n) => all | Permission[n], 0n).toString();

describe("workspaces", () => {
	test("a new workspace has @everyone, a category and #general", async () => {
		const owner = await register(ctx);
		const { workspaceId, generalId } = await workspaceWith(ctx, owner);
		const roles = await call(ctx, "GET", `/workspaces/${workspaceId}/roles`, undefined, owner.as);
		expect(roles.body.roles[0]).toMatchObject({ id: workspaceId, name: "@everyone" });
		const channels = await call(ctx, "GET", `/workspaces/${workspaceId}/channels`, undefined, owner.as);
		expect(channels.body.channels.map((c: { type: string }) => c.type).sort()).toEqual(["category", "text"]);
		expect(generalId).toBeTruthy();
	});

	test("a one-use invite admits exactly one person, even when used at once", async () => {
		const owner = await register(ctx);
		const { workspaceId } = await workspaceWith(ctx, owner);
		const invite = await call(ctx, "POST", `/workspaces/${workspaceId}/invites`, { maxUses: 1 }, owner.as);
		const people = await Promise.all(Array.from({ length: 5 }, () => register(ctx)));
		const results = await Promise.all(people.map((p) => call(ctx, "POST", `/invites/${invite.body.invite.code}`, undefined, p.as)));
		expect(results.filter((r) => r.status === 200)).toHaveLength(1);
		expect(results.filter((r) => r.status === 410)).toHaveLength(4);
	});

	test("roles: nobody hands out what they don't have, or edits roles above them", async () => {
		const owner = await register(ctx);
		const mod = await register(ctx);
		const { workspaceId } = await workspaceWith(ctx, owner, mod);
		const modRole = await call(ctx, "POST", `/workspaces/${workspaceId}/roles`, { name: "Mod", position: 5, permissions: bits("MANAGE_ROLES", "KICK_MEMBERS", "MANAGE_MESSAGES") }, owner.as);
		await call(ctx, "PUT", `/workspaces/${workspaceId}/members/${mod.id}/roles/${modRole.body.role.id}`, undefined, owner.as);

		const tooStrong = await call(ctx, "POST", `/workspaces/${workspaceId}/roles`, { name: "Admin", position: 1, permissions: bits("ADMINISTRATOR") }, mod.as);
		expect(tooStrong.status).toBe(403);
		const above = await call(ctx, "POST", `/workspaces/${workspaceId}/roles`, { name: "Higher", position: 6 }, mod.as);
		expect(above.status).toBe(403);
		const fine = await call(ctx, "POST", `/workspaces/${workspaceId}/roles`, { name: "Helper", position: 2, permissions: bits("MANAGE_MESSAGES") }, mod.as);
		expect(fine.status).toBe(201);
		expect((await call(ctx, "PATCH", `/workspaces/${workspaceId}/roles/${modRole.body.role.id}`, { name: "Boss" }, mod.as)).status).toBe(403);
		expect((await call(ctx, "DELETE", `/workspaces/${workspaceId}/roles/${workspaceId}`, undefined, owner.as)).status).toBe(400);
	});

	test("kicking needs the permission and a higher role; the owner can't be kicked", async () => {
		const owner = await register(ctx);
		const mod = await register(ctx);
		const member = await register(ctx);
		const { workspaceId, generalId } = await workspaceWith(ctx, owner, mod, member);
		expect((await call(ctx, "DELETE", `/workspaces/${workspaceId}/members/${member.id}`, undefined, mod.as)).status).toBe(403);
		const role = await call(ctx, "POST", `/workspaces/${workspaceId}/roles`, { name: "Mod", position: 3, permissions: bits("KICK_MEMBERS") }, owner.as);
		await call(ctx, "PUT", `/workspaces/${workspaceId}/members/${mod.id}/roles/${role.body.role.id}`, undefined, owner.as);
		expect((await call(ctx, "DELETE", `/workspaces/${workspaceId}/members/${owner.id}`, undefined, mod.as)).status).toBe(403);
		expect((await call(ctx, "DELETE", `/workspaces/${workspaceId}/members/${member.id}`, undefined, mod.as)).status).toBe(204);
		expect((await call(ctx, "GET", `/channels/${generalId}/messages`, undefined, member.as)).status).toBe(404);
		expect((await call(ctx, "DELETE", `/workspaces/${workspaceId}/members/${owner.id}`, undefined, owner.as)).status).toBe(400);
	});

	test("private channels and overwrites decide who sees what", async () => {
		const owner = await register(ctx);
		const member = await register(ctx);
		const { workspaceId, generalId } = await workspaceWith(ctx, owner, member);
		const secret = await call(ctx, "POST", `/workspaces/${workspaceId}/channels`, { name: "Leads Only", isPrivate: true }, owner.as);
		expect(secret.body.channel.name).toBe("leads-only");
		const secretId = secret.body.channel.id;
		await send(ctx, owner, secretId, "budget talk");

		const visible = await call(ctx, "GET", `/workspaces/${workspaceId}/channels`, undefined, member.as);
		expect(visible.body.channels.map((c: { id: string }) => c.id)).not.toContain(secretId);
		expect((await call(ctx, "GET", `/channels/${secretId}/messages`, undefined, member.as)).status).toBe(404);
		expect((await call(ctx, "GET", "/search/messages?q=budget", undefined, member.as)).body.messages).toHaveLength(0);

		await call(ctx, "PUT", `/channels/${secretId}/members/${member.id}`, undefined, owner.as);
		expect((await call(ctx, "GET", `/channels/${secretId}/messages`, undefined, member.as)).status).toBe(200);

		// Read-only #general for @everyone
		const deny = await call(ctx, "PUT", `/channels/${generalId}/permissions/role/${workspaceId}`, { deny: bits("SEND_MESSAGES") }, owner.as);
		expect(deny.status).toBe(204);
		expect((await call(ctx, "POST", `/channels/${generalId}/messages`, { content: "x" }, member.as)).status).toBe(403);
		expect((await call(ctx, "GET", `/channels/${generalId}/messages`, undefined, member.as)).status).toBe(200);
		// Overwrites can't hold workspace-wide permissions
		const bad = await call(ctx, "PUT", `/channels/${generalId}/permissions/member/${member.id}`, { allow: bits("ADMINISTRATOR") }, owner.as);
		expect(bad.status).toBe(400);
	});

	test("deleting a channel purges only that channel's messages", async () => {
		const owner = await register(ctx);
		const { workspaceId, generalId } = await workspaceWith(ctx, owner);
		const doomed = (await call(ctx, "POST", `/workspaces/${workspaceId}/channels`, { name: "doomed" }, owner.as)).body.channel.id;
		for (let i = 0; i < 5; i++) {
			await send(ctx, owner, doomed, `bye ${i}`);
			await send(ctx, owner, generalId, `stay ${i}`);
		}
		const other = await register(ctx);
		const otherSpace = await workspaceWith(ctx, other);
		await send(ctx, other, otherSpace.generalId, "unrelated");

		expect((await call(ctx, "DELETE", `/channels/${doomed}`, undefined, owner.as)).status).toBe(204);
		expect((await call(ctx, "GET", `/channels/${doomed}/messages`, undefined, owner.as)).status).toBe(404);
		await ctx.services.jobs.drain();
		const count = async (channel: string) =>
			(await ctx.services.db.execute<{ n: number }>(sql`select count(*)::int as n from messages where channel_id = ${BigInt(channel)}`)).rows[0].n;
		expect(await count(doomed)).toBe(0);
		expect(await count(generalId)).toBe(5);
		expect(await count(otherSpace.generalId)).toBe(1);
	});

	test("deleting a workspace: only the owner; its channels are purged, others untouched", async () => {
		const owner = await register(ctx);
		const member = await register(ctx);
		const { workspaceId, generalId } = await workspaceWith(ctx, owner, member);
		await send(ctx, member, generalId, "hello");
		const keep = await workspaceWith(ctx, member);
		await send(ctx, member, keep.generalId, "mine");
		expect((await call(ctx, "DELETE", `/workspaces/${workspaceId}`, undefined, member.as)).status).toBe(403);
		expect((await call(ctx, "DELETE", `/workspaces/${workspaceId}`, undefined, owner.as)).status).toBe(204);
		await ctx.services.jobs.drain();
		const rows = await ctx.services.db.execute<{ channel_id: string }>(
			sql`select channel_id from messages where channel_id in (${BigInt(generalId)}, ${BigInt(keep.generalId)})`,
		);
		expect(rows.rows.map((r) => r.channel_id)).toEqual([keep.generalId]);
		expect((await call(ctx, "GET", "/workspaces", undefined, member.as)).body.workspaces.map((w: { id: string }) => w.id)).toEqual([keep.workspaceId]);
	});

	test("ownership transfer, and the audit log needs its permission", async () => {
		const owner = await register(ctx);
		const member = await register(ctx);
		const { workspaceId } = await workspaceWith(ctx, owner, member);
		expect((await call(ctx, "GET", `/workspaces/${workspaceId}/audit-log`, undefined, member.as)).status).toBe(403);
		expect((await call(ctx, "POST", `/workspaces/${workspaceId}/transfer`, { userId: member.id }, owner.as)).status).toBe(204);
		const log = await call(ctx, "GET", `/workspaces/${workspaceId}/audit-log`, undefined, member.as);
		expect(log.body.entries.map((e: { action: string }) => e.action)).toEqual(
			expect.arrayContaining(["workspace.create", "member.join", "workspace.transfer"]),
		);
		expect(log.body.entries[0].ip).toBeUndefined();
	});
});
