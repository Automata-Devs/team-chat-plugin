import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { call, createTestApp, register, send, type TestContext } from "./helpers.js";

let ctx: TestContext;
beforeAll(async () => {
	ctx = await createTestApp();
});
afterAll(() => ctx.close());

const SECRET = "s".repeat(40);
const place = (key: string, user: { as: { token?: string } }, secret = SECRET) =>
	call(ctx, "POST", `/places/${encodeURIComponent(key)}/workspace`, { secret, name: "Obby" }, user.as);

describe("one workspace per place, made automatically", () => {
	test("the first person makes it; the next ones join with the place's secret", async () => {
		const [ana, bo] = await Promise.all([register(ctx), register(ctx)]);
		const first = await place("place:1001", ana);
		expect(first.status).toBe(200);
		expect(first.body.created).toBe(true);
		expect(first.body.workspace).toMatchObject({ name: "Obby", placeKey: "place:1001" });
		const teamChat = first.body.teamChatChannelId;
		const channels = await call(ctx, "GET", `/workspaces/${first.body.workspace.id}/channels`, undefined, ana.as);
		expect(channels.body.channels.find((c: { id: string }) => c.id === teamChat).name).toBe("team-chat");

		const second = await place("place:1001", bo);
		expect(second.body).toMatchObject({ created: false, teamChatChannelId: teamChat });
		expect(second.body.workspace.id).toBe(first.body.workspace.id);
		await send(ctx, bo, teamChat, "hi from Bo");
		expect((await place("place:1001", bo)).body.created).toBe(false); // every start is fine
	});

	test("without the place's secret there's no way in", async () => {
		const [ana, eve] = await Promise.all([register(ctx), register(ctx)]);
		const made = await place("place:1002", ana);
		expect((await place("place:1002", eve, "x".repeat(40))).status).toBe(403);
		expect((await call(ctx, "GET", `/channels/${made.body.teamChatChannelId}/messages`, undefined, eve.as)).status).toBe(404);
		expect((await place("place:not-a-number", eve)).status).toBe(400);
		expect((await place("place:1003", eve, "short")).status).toBe(400);
	});

	test("people opening a new place at the same moment end up in one workspace", async () => {
		const people = await Promise.all(Array.from({ length: 5 }, () => register(ctx)));
		const results = await Promise.all(people.map((p) => place("local:3f2504e0-4f89-11d3-9a0c-0305e82c3301", p)));
		expect(results.every((r) => r.status === 200)).toBe(true);
		expect(new Set(results.map((r) => r.body.workspace.id)).size).toBe(1);
		expect(results.filter((r) => r.body.created)).toHaveLength(1);
		const members = await call(ctx, "GET", `/workspaces/${results[0].body.workspace.id}/members`, undefined, people[0].as);
		expect(members.body.members).toHaveLength(5);
	});
});

describe("a place's DMs and groups live in its workspace", () => {
	test("the same two people have a separate DM in every place", async () => {
		const [ana, bo] = await Promise.all([register(ctx), register(ctx)]);
		const a = (await place("place:2001", ana)).body.workspace.id;
		await place("place:2001", bo);
		const b = (await place("place:2002", ana)).body.workspace.id;
		await place("place:2002", bo);

		const inA = await call(ctx, "POST", "/conversations", { recipients: [bo.id], workspaceId: a }, ana.as);
		const inB = await call(ctx, "POST", "/conversations", { recipients: [bo.id], workspaceId: b }, ana.as);
		const again = await call(ctx, "POST", "/conversations", { recipients: [ana.id], workspaceId: a }, bo.as);
		expect(inA.body.conversation.id).not.toBe(inB.body.conversation.id);
		expect(again.body.conversation.id).toBe(inA.body.conversation.id);
		expect(inA.body.conversation.workspaceId).toBe(a);

		await send(ctx, ana, inA.body.conversation.id, "about place A");
		await send(ctx, ana, inB.body.conversation.id, "about place B");
		const listA = await call(ctx, "GET", `/conversations?workspaceId=${a}`, undefined, bo.as);
		expect(listA.body.conversations.map((c: { id: string }) => c.id)).toEqual([inA.body.conversation.id]);
		const searchA = await call(ctx, "GET", `/search/messages?q=place&workspaceId=${a}`, undefined, bo.as);
		expect(searchA.body.messages.map((m: { content: string }) => m.content)).toEqual(["about place A"]);
	});

	test("only the people in a place DM see it, even other members of the place", async () => {
		const [ana, bo, cy] = await Promise.all([register(ctx), register(ctx), register(ctx)]);
		const ws = (await place("place:2003", ana)).body.workspace.id;
		await place("place:2003", bo);
		await place("place:2003", cy);
		const dm = (await call(ctx, "POST", "/conversations", { recipients: [bo.id], workspaceId: ws }, ana.as)).body.conversation.id;
		await send(ctx, ana, dm, "just us");
		expect((await call(ctx, "GET", `/channels/${dm}/messages`, undefined, cy.as)).status).toBe(404);
		const channels = await call(ctx, "GET", `/workspaces/${ws}/channels`, undefined, cy.as);
		expect(channels.body.channels.map((c: { id: string }) => c.id)).not.toContain(dm);
		expect((await call(ctx, "GET", `/search/messages?q=just&workspaceId=${ws}`, undefined, cy.as)).body.messages).toHaveLength(0);
	});

	test("people outside the place can't be added, and leaving the place leaves its DMs", async () => {
		const [ana, bo, outsider] = await Promise.all([register(ctx), register(ctx), register(ctx)]);
		const ws = (await place("place:2004", ana)).body.workspace.id;
		await place("place:2004", bo);
		expect((await call(ctx, "POST", "/conversations", { recipients: [outsider.id], workspaceId: ws }, ana.as)).status).toBe(404);
		expect((await call(ctx, "POST", "/conversations", { recipients: [bo.id], workspaceId: ws }, outsider.as)).status).toBe(404);
		const group = await call(ctx, "POST", "/conversations", { recipients: [bo.id], name: "Builders", workspaceId: ws }, ana.as);
		expect(group.body.conversation).toMatchObject({ type: "group_dm", workspaceId: ws });
		expect((await call(ctx, "DELETE", `/workspaces/${ws}/members/${bo.id}`, undefined, bo.as)).status).toBe(204);
		expect((await call(ctx, "GET", `/channels/${group.body.conversation.id}/messages`, undefined, bo.as)).status).toBe(404);
	});

	test("deleting the place's workspace purges its DMs too, and nothing else", async () => {
		const [ana, bo] = await Promise.all([register(ctx), register(ctx)]);
		const ws = (await place("place:2005", ana)).body.workspace.id;
		await place("place:2005", bo);
		const placeDm = (await call(ctx, "POST", "/conversations", { recipients: [bo.id], workspaceId: ws }, ana.as)).body.conversation.id;
		const globalDm = (await call(ctx, "POST", "/conversations", { recipients: [bo.id] }, ana.as)).body.conversation.id;
		await send(ctx, ana, placeDm, "in the place");
		await send(ctx, ana, globalDm, "outside any place");
		expect((await call(ctx, "DELETE", `/workspaces/${ws}`, undefined, ana.as)).status).toBe(204);
		await ctx.services.jobs.drain();
		const left = await ctx.services.db.execute<{ channel_id: string }>(
			sql`select channel_id from messages where channel_id in (${BigInt(placeDm)}, ${BigInt(globalDm)})`,
		);
		expect(left.rows.map((r) => r.channel_id)).toEqual([globalDm]);
	});
});
