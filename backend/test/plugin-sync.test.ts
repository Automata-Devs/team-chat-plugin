import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { call, createTestApp, register, send, type TestContext, type TestUser, workspaceWith } from "./helpers.js";

// What the Studio plugin uses to mirror its chat (src/Services/Backend)
let ctx: TestContext;
let owner: TestUser;
let member: TestUser;
let workspaceId: string;
let generalId: string;

beforeAll(async () => {
	ctx = await createTestApp();
	owner = await register(ctx);
	member = await register(ctx);
	({ workspaceId, generalId } = await workspaceWith(ctx, owner, member));
});
afterAll(() => ctx.close());

const entry = (name: string, content: string, extra: object = {}) => ({
	content,
	nonce: name,
	clientData: { sender: "Ana", senderId: 156, timestamp: 1_700_000_000, messageType: "Text", ...extra },
});

describe("batch uploads", () => {
	test("stores the sender's messages with their client data, in order", async () => {
		const sent = await call(
			ctx,
			"POST",
			`/channels/${generalId}/messages/batch`,
			{ messages: [entry("msg_1_1", "first"), entry("poll_2_2", "", { messageType: "Poll", question: "Lunch?" }), entry("msg_3_3", "third")] },
			member.as,
		);
		expect(sent.status).toBe(200);
		expect(sent.body.messages.map((m: { created: boolean }) => m.created)).toEqual([true, true, true]);
		const history = await call(ctx, "GET", `/channels/${generalId}/messages?limit=3`, undefined, owner.as);
		const [third, poll, first] = history.body.messages;
		expect([first.content, third.content]).toEqual(["first", "third"]);
		expect(poll.metadata.client).toMatchObject({ messageType: "Poll", question: "Lunch?" });
		expect(first.author.id).toBe(member.id);
		expect(first.nonce).toBe("msg_1_1");
	});

	test("a retried batch stores nothing twice, also when sent at the same moment", async () => {
		const body = { messages: [entry("msg_10_1", "a"), entry("msg_10_2", "b")] };
		const [one, two] = await Promise.all([
			call(ctx, "POST", `/channels/${generalId}/messages/batch`, body, member.as),
			call(ctx, "POST", `/channels/${generalId}/messages/batch`, body, member.as),
		]);
		const ids = (r: typeof one) => r.body.messages.map((m: { id: string }) => m.id);
		expect(ids(one)).toEqual(ids(two));
		const again = await call(ctx, "POST", `/channels/${generalId}/messages/batch`, body, member.as);
		expect(again.body.messages.every((m: { created: boolean }) => !m.created)).toBe(true);
		const rows = await ctx.services.db.execute<{ n: number }>(
			sql`select count(*)::int as n from messages where nonce in ('msg_10_1', 'msg_10_2')`,
		);
		expect(rows.rows[0].n).toBe(2);
	});

	test("nonces are per author and checked; outsiders and bad batches are refused", async () => {
		const same = await call(ctx, "POST", `/channels/${generalId}/messages/batch`, { messages: [entry("msg_1_1", "owner's own")] }, owner.as);
		expect(same.body.messages[0].created).toBe(true);
		const outsider = await register(ctx);
		expect((await call(ctx, "POST", `/channels/${generalId}/messages/batch`, { messages: [entry("x", "hi")] }, outsider.as)).status).toBe(404);
		const duplicate = { messages: [entry("d", "1"), entry("d", "2")] };
		expect((await call(ctx, "POST", `/channels/${generalId}/messages/batch`, duplicate, member.as)).status).toBe(400);
		const empty = { messages: [{ content: "", nonce: "e" }] };
		expect((await call(ctx, "POST", `/channels/${generalId}/messages/batch`, empty, member.as)).status).toBe(400);
		const tooBig = { messages: [entry("big", "x", { blob: "y".repeat(17000) })] };
		expect((await call(ctx, "POST", `/channels/${generalId}/messages/batch`, tooBig, member.as)).status).toBe(400);
	});

	test("edits can update the client data", async () => {
		const message = await send(ctx, member, generalId, "before", { nonce: "msg_20_1", clientData: { senderId: 156 } });
		const edited = await call(
			ctx,
			"PATCH",
			`/channels/${generalId}/messages/${message.id}`,
			{ content: "after", clientData: { senderId: 156, editedAt: 5 } },
			member.as,
		);
		expect(edited.body.message.metadata.client).toEqual({ senderId: 156, editedAt: 5 });
	});
});

describe("the plugin's own sequence of requests (src/Services/Backend)", () => {
	// Studio's HttpService sends Content-Type: application/json on every request, also without a body
	const plugin = (method: string, path: string, body: unknown, token?: string) =>
		ctx.app.inject({
			method: method as "GET",
			url: `/api/v1${path}`,
			headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
			payload: body === undefined ? "" : JSON.stringify(body),
		});

	test("admin sets the place up, a teammate joins, DMs and groups, store, edit, react, delete, restore", async () => {
		const admin = await register(ctx);
		const mate = await register(ctx);
		const third = await register(ctx);
		// Backend.join, admin: workspace, its first text channel, an invite
		const made = JSON.parse((await plugin("POST", "/workspaces", { name: "My Place" }, admin.token)).body);
		const workspace = made.workspace.id;
		const channels = JSON.parse((await plugin("GET", `/workspaces/${workspace}/channels`, undefined, admin.token)).body);
		const channelId = channels.channels.find((c: { type: string }) => c.type === "text").id;
		const invite = JSON.parse((await plugin("POST", `/workspaces/${workspace}/invites`, {}, admin.token)).body).invite.code;
		// Backend.join, teammates: the invite, with an empty JSON body; joining twice is fine
		for (const user of [mate, third, mate]) {
			expect((await plugin("POST", `/invites/${encodeURIComponent(invite)}`, undefined, user.token)).statusCode).toBe(200);
		}

		// Mirror.flush: a poll and a file with their client data, flagged as older messages
		const batch = await plugin(
			"POST",
			`/channels/${channelId}/messages/batch`,
			{
				messages: [
					{ content: "📊 Lunch?", nonce: "poll_1_1", flags: 4096, clientData: { messageType: "Poll", pollData: { question: "Lunch?", options: ["A", "B"], votes: [[1], []] } } },
					{ content: "📎 map.rbxl", nonce: "file_1_2", flags: 0, clientData: { messageType: "File", fileName: "map.rbxl", fileUrl: "rbxassetid://1" } },
				],
			},
			mate.token,
		);
		expect(batch.statusCode).toBe(200);
		const [poll, file] = JSON.parse(batch.body).messages;

		// Channels.resolve: a DM (no name) and a group (named), then a late member added
		await ctx.services.db.execute(
			sql`insert into connected_accounts (id, user_id, provider, provider_user_id) values (${ctx.services.ids.next()}, ${BigInt(third.id)}, 'roblox', '777')`,
		);
		const found = JSON.parse((await plugin("GET", `/workspaces/${workspace}/members/roblox/777`, undefined, mate.token)).body);
		const dm = JSON.parse((await plugin("POST", "/conversations", { recipients: [found.user.id] }, mate.token)).body).conversation;
		expect(dm.type).toBe("dm");
		const group = JSON.parse((await plugin("POST", "/conversations", { recipients: [found.user.id], name: "Group" }, mate.token)).body).conversation;
		expect(group.type).toBe("group_dm");
		expect((await plugin("PUT", `/conversations/${group.id}/recipients/${admin.id}`, undefined, mate.token)).statusCode).toBe(204);

		// Outbox: edit, react with an encoded emoji, unreact, delete
		const edited = await plugin("PATCH", `/channels/${channelId}/messages/${file.id}`, { content: "📎 map v2.rbxl", clientData: { fileName: "map v2.rbxl" } }, mate.token);
		expect(edited.statusCode).toBe(200);
		const emoji = encodeURIComponent("👍");
		expect((await plugin("PUT", `/channels/${channelId}/messages/${poll.id}/reactions/${emoji}/@me`, undefined, mate.token)).statusCode).toBe(204);
		expect((await plugin("DELETE", `/channels/${channelId}/messages/${poll.id}/reactions/${emoji}/@me`, undefined, mate.token)).statusCode).toBe(204);

		// Restore.teamChat: pages of 100, nonces and client data back
		const page = JSON.parse((await plugin("GET", `/channels/${channelId}/messages?limit=100`, undefined, admin.token)).body).messages;
		const restoredPoll = page.find((m: { nonce: string }) => m.nonce === "poll_1_1");
		expect(restoredPoll.metadata.client.pollData.options).toEqual(["A", "B"]);
		expect(page.find((m: { nonce: string }) => m.nonce === "file_1_2").metadata.client.fileName).toBe("map v2.rbxl");

		expect((await plugin("DELETE", `/channels/${channelId}/messages/${file.id}`, undefined, mate.token)).statusCode).toBe(204);
		// A second delete (an outbox replay) is a 404, which the plugin drops
		expect((await plugin("DELETE", `/channels/${channelId}/messages/${file.id}`, undefined, mate.token)).statusCode).toBe(404);
	});
});

describe("finding teammates by Roblox account", () => {
	test("members are found by their Roblox id; others aren't", async () => {
		await ctx.services.db.execute(
			sql`insert into connected_accounts (id, user_id, provider, provider_user_id) values (${ctx.services.ids.next()}, ${BigInt(member.id)}, 'roblox', '424242')`,
		);
		const found = await call(ctx, "GET", `/workspaces/${workspaceId}/members/roblox/424242`, undefined, owner.as);
		expect(found.body.user.id).toBe(member.id);
		expect((await call(ctx, "GET", `/workspaces/${workspaceId}/members/roblox/999`, undefined, owner.as)).status).toBe(404);
		const outsider = await register(ctx);
		expect((await call(ctx, "GET", `/workspaces/${workspaceId}/members/roblox/424242`, undefined, outsider.as)).status).toBe(404);
	});
});
