import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { call, createTestApp, register, send, type TestContext } from "./helpers.js";

let ctx: TestContext;
beforeAll(async () => {
	ctx = await createTestApp();
});
afterAll(() => ctx.close());

describe("direct messages", () => {
	test("opening a DM twice, or from both sides at once, gives one conversation", async () => {
		const ana = await register(ctx);
		const bo = await register(ctx);
		const [a, b] = await Promise.all([
			call(ctx, "POST", "/conversations", { recipients: [bo.id] }, ana.as),
			call(ctx, "POST", "/conversations", { recipients: [ana.id] }, bo.as),
		]);
		expect(a.status).toBe(201);
		expect(a.body.conversation.id).toBe(b.body.conversation.id);
		expect(a.body.conversation.type).toBe("dm");
		const again = await call(ctx, "POST", "/conversations", { recipients: [bo.id] }, ana.as);
		expect(again.body.conversation.id).toBe(a.body.conversation.id);
		expect(a.body.conversation.recipients.map((u: { id: string }) => u.id)).toEqual([bo.id]);
	});

	test("only the two people in it can read or write it", async () => {
		const ana = await register(ctx);
		const bo = await register(ctx);
		const eve = await register(ctx);
		const dm = (await call(ctx, "POST", "/conversations", { recipients: [bo.id] }, ana.as)).body.conversation.id;
		await send(ctx, ana, dm, "secret plans");
		expect((await call(ctx, "GET", `/channels/${dm}/messages`, undefined, bo.as)).body.messages).toHaveLength(1);
		expect((await call(ctx, "GET", `/channels/${dm}/messages`, undefined, eve.as)).status).toBe(404);
		expect((await call(ctx, "POST", `/channels/${dm}/messages`, { content: "hi" }, eve.as)).status).toBe(404);
		expect((await call(ctx, "GET", `/conversations/${dm}`, undefined, eve.as)).status).toBe(404);
		const search = await call(ctx, "GET", "/search/messages?q=secret", undefined, eve.as);
		expect(search.body.messages).toHaveLength(0);
	});

	test("blocking stops new DMs and messages in an existing one", async () => {
		const ana = await register(ctx);
		const bo = await register(ctx);
		const dm = (await call(ctx, "POST", "/conversations", { recipients: [bo.id] }, ana.as)).body.conversation.id;
		expect((await call(ctx, "PUT", `/users/@me/relationships/${ana.id}`, { type: "block" }, bo.as)).status).toBe(204);
		expect((await call(ctx, "POST", `/channels/${dm}/messages`, { content: "hello?" }, ana.as)).status).toBe(403);
		expect((await call(ctx, "POST", "/conversations", { recipients: [bo.id] }, ana.as)).status).toBe(403);
		expect((await call(ctx, "DELETE", `/users/@me/relationships/${ana.id}?type=block`, undefined, bo.as)).status).toBe(204);
		expect((await call(ctx, "POST", `/channels/${dm}/messages`, { content: "hello again" }, ana.as)).status).toBe(201);
	});

	test("a privacy setting can refuse DMs", async () => {
		const ana = await register(ctx);
		const shy = await register(ctx);
		await call(ctx, "PATCH", "/users/@me/settings", { privacy: { allowDirectMessages: "none" } }, shy.as);
		expect((await call(ctx, "POST", "/conversations", { recipients: [shy.id] }, ana.as)).status).toBe(403);
		await call(ctx, "PATCH", "/users/@me/settings", { privacy: { allowDirectMessages: "workspace_members" } }, shy.as);
		expect((await call(ctx, "POST", "/conversations", { recipients: [shy.id] }, ana.as)).status).toBe(403);
	});

	test("unread counts, archive and mute", async () => {
		const ana = await register(ctx);
		const bo = await register(ctx);
		const dm = (await call(ctx, "POST", "/conversations", { recipients: [bo.id] }, ana.as)).body.conversation.id;
		for (let i = 0; i < 3; i++) await send(ctx, ana, dm, `ping ${i}`);
		let list = await call(ctx, "GET", "/conversations", undefined, bo.as);
		expect(list.body.conversations[0]).toMatchObject({ id: dm, unreadCount: 3 });
		await call(ctx, "POST", `/channels/${dm}/ack`, {}, bo.as);
		list = await call(ctx, "GET", "/conversations", undefined, bo.as);
		expect(list.body.conversations[0].unreadCount).toBe(0);

		await call(ctx, "PATCH", `/channels/${dm}/settings`, { archived: true, muted: true }, bo.as);
		expect((await call(ctx, "GET", "/conversations", undefined, bo.as)).body.conversations).toHaveLength(0);
		const archived = await call(ctx, "GET", "/conversations?archived=true", undefined, bo.as);
		expect(archived.body.conversations[0].settings).toMatchObject({ archived: true, muted: true });
		// Only Bo's view changed
		expect((await call(ctx, "GET", "/conversations", undefined, ana.as)).body.conversations).toHaveLength(1);
	});
});

describe("group conversations", () => {
	test("create, rename, add, remove, leave: ownership passes on, the last one out deletes it", async () => {
		const [owner, a, b, c] = await Promise.all([register(ctx), register(ctx), register(ctx), register(ctx)]);
		const created = await call(ctx, "POST", "/conversations", { recipients: [a.id, b.id], name: "Map team" }, owner.as);
		expect(created.body.conversation).toMatchObject({ type: "group_dm", name: "Map team", ownerId: owner.id });
		const id = created.body.conversation.id;

		expect((await call(ctx, "PUT", `/conversations/${id}/recipients/${c.id}`, undefined, a.as)).status).toBe(204);
		expect((await call(ctx, "GET", `/channels/${id}/messages`, undefined, c.as)).status).toBe(200);

		// Only the owner removes others
		expect((await call(ctx, "DELETE", `/conversations/${id}/recipients/${b.id}`, undefined, a.as)).status).toBe(403);
		expect((await call(ctx, "DELETE", `/conversations/${id}/recipients/${b.id}`, undefined, owner.as)).status).toBe(204);
		expect((await call(ctx, "GET", `/channels/${id}/messages`, undefined, b.as)).status).toBe(404);

		await call(ctx, "PATCH", `/conversations/${id}`, { name: "Map crew" }, a.as);
		const history = await call(ctx, "GET", `/channels/${id}/messages`, undefined, a.as);
		expect(history.body.messages.map((m: { type: string }) => m.type)).toEqual(["channel_name_change", "recipient_remove", "recipient_add"]);

		expect((await call(ctx, "DELETE", `/conversations/${id}/recipients/${owner.id}`, undefined, owner.as)).status).toBe(204);
		const afterLeave = await call(ctx, "GET", `/conversations/${id}`, undefined, a.as);
		expect(afterLeave.body.conversation.ownerId).toBe(a.id);

		await send(ctx, a, id, "anyone?");
		await call(ctx, "DELETE", `/conversations/${id}/recipients/${c.id}`, undefined, c.as);
		await call(ctx, "DELETE", `/conversations/${id}/recipients/${a.id}`, undefined, a.as);
		await ctx.services.jobs.drain();
		const left = await ctx.services.db.execute<{ n: number }>(sql`select count(*)::int as n from messages where channel_id = ${BigInt(id)}`);
		expect(left.rows[0].n).toBe(0);
	});

	test("groups hold at most 10 people, also with adds racing", async () => {
		const people = await Promise.all(Array.from({ length: 12 }, () => register(ctx)));
		const [owner, ...rest] = people;
		expect((await call(ctx, "POST", "/conversations", { recipients: rest.map((p) => p.id) }, owner.as)).status).toBe(400);
		const group = await call(ctx, "POST", "/conversations", { recipients: rest.slice(0, 8).map((p) => p.id) }, owner.as);
		const id = group.body.conversation.id;
		const adds = await Promise.all(rest.slice(8).map((p) => call(ctx, "PUT", `/conversations/${id}/recipients/${p.id}`, undefined, owner.as)));
		expect(adds.filter((r) => r.status === 204)).toHaveLength(1);
		const members = await ctx.services.db.execute<{ n: number }>(sql`select count(*)::int as n from channel_members where channel_id = ${BigInt(id)}`);
		expect(members.rows[0].n).toBe(10);
	});

	test("a DM can't be left, only archived", async () => {
		const [a, b] = await Promise.all([register(ctx), register(ctx)]);
		const dm = (await call(ctx, "POST", "/conversations", { recipients: [b.id] }, a.as)).body.conversation.id;
		expect((await call(ctx, "DELETE", `/conversations/${dm}/recipients/${a.id}`, undefined, a.as)).status).toBe(400);
	});
});
