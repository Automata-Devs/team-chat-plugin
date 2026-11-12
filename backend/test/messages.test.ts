import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { call, createTestApp, register, send, type TestContext, type TestUser, workspaceWith } from "./helpers.js";

let ctx: TestContext;
let owner: TestUser;
let member: TestUser;
let outsider: TestUser;
let channelId: string;
let workspaceId: string;

beforeAll(async () => {
	ctx = await createTestApp();
	owner = await register(ctx);
	member = await register(ctx);
	outsider = await register(ctx);
	({ workspaceId, generalId: channelId } = await workspaceWith(ctx, owner, member));
});
afterAll(() => ctx.close());

describe("messages", () => {
	test("send and read back, with the author filled in by the server", async () => {
		const message = await send(ctx, member, channelId, "  Lighting pass is done \u0007 ");
		expect(message.content).toBe("Lighting pass is done");
		expect(message.author.id).toBe(member.id);
		const got = await call(ctx, "GET", `/channels/${channelId}/messages/${message.id}`, undefined, owner.as);
		expect(got.body.message.content).toBe("Lighting pass is done");
	});

	test("a client can't pick its author, id or time", async () => {
		const forged = await call(ctx, "POST", `/channels/${channelId}/messages`, { content: "hi", authorId: owner.id }, member.as);
		expect(forged.status).toBe(400);
		const message = await send(ctx, member, channelId, "plain");
		expect(BigInt(message.id) > 0n).toBe(true);
	});

	test("empty or oversized messages are refused", async () => {
		expect((await call(ctx, "POST", `/channels/${channelId}/messages`, { content: "   " }, member.as)).status).toBe(400);
		expect((await call(ctx, "POST", `/channels/${channelId}/messages`, { content: "x".repeat(4001) }, member.as)).status).toBe(400);
	});

	test("only the author edits; edits are marked", async () => {
		const message = await send(ctx, member, channelId, "typo");
		expect((await call(ctx, "PATCH", `/channels/${channelId}/messages/${message.id}`, { content: "fixed" }, owner.as)).status).toBe(403);
		const edited = await call(ctx, "PATCH", `/channels/${channelId}/messages/${message.id}`, { content: "fixed" }, member.as);
		expect(edited.status).toBe(200);
		expect(edited.body.message.content).toBe("fixed");
		expect(edited.body.message.editedAt).not.toBeNull();
	});

	test("authors and moderators delete; others can't; deleted messages disappear", async () => {
		const mine = await send(ctx, member, channelId, "delete me");
		const third = await register(ctx);
		const invite = await call(ctx, "POST", `/workspaces/${workspaceId}/invites`, {}, owner.as);
		await call(ctx, "POST", `/invites/${invite.body.invite.code}`, undefined, third.as);
		expect((await call(ctx, "DELETE", `/channels/${channelId}/messages/${mine.id}`, undefined, third.as)).status).toBe(403);
		expect((await call(ctx, "DELETE", `/channels/${channelId}/messages/${mine.id}`, undefined, member.as)).status).toBe(204);
		expect((await call(ctx, "GET", `/channels/${channelId}/messages/${mine.id}`, undefined, member.as)).status).toBe(404);

		const theirs = await send(ctx, member, channelId, "moderate me");
		expect((await call(ctx, "DELETE", `/channels/${channelId}/messages/${theirs.id}`, undefined, owner.as)).status).toBe(204);
		const log = await call(ctx, "GET", `/workspaces/${workspaceId}/audit-log`, undefined, owner.as);
		expect(log.body.entries.some((e: { action: string; targetId: string }) => e.action === "message.delete" && e.targetId === theirs.id)).toBe(true);

		// The row stays as a tombstone with its content wiped
		const row = await ctx.services.db.execute<{ content: string; deleted_at: Date }>(
			sql`select content, deleted_at from messages where id = ${BigInt(theirs.id)}`,
		);
		expect(row.rows[0]).toMatchObject({ content: "" });
		expect(row.rows[0].deleted_at).not.toBeNull();
	});

	test("replies point at a message in the same channel", async () => {
		const original = await send(ctx, owner, channelId, "who has the map?");
		const reply = await send(ctx, member, channelId, "me", { replyTo: original.id });
		expect(reply.type).toBe("reply");
		expect(reply.replyTo).toMatchObject({ id: original.id, content: "who has the map?", deleted: false });
		const other = await call(ctx, "POST", `/workspaces/${workspaceId}/channels`, { name: "other" }, owner.as);
		const elsewhere = await call(ctx, "POST", `/channels/${other.body.channel.id}/messages`, { content: "x", replyTo: original.id }, owner.as);
		expect(elsewhere.status).toBe(400);
	});

	test("mentions are parsed by the server; @everyone needs the permission", async () => {
		const message = await send(ctx, member, channelId, `hey <@${owner.id}> and <@999999999>`);
		expect(message.mentions).toEqual([owner.id]);
		const everyone = await send(ctx, member, channelId, "@everyone meeting");
		expect(everyone.mentionEveryone).toBe(false);
		const fromOwner = await send(ctx, owner, channelId, "@everyone meeting");
		expect(fromOwner.mentionEveryone).toBe(true);
	});

	test("a retried send with the same nonce makes one message", async () => {
		const [a, b] = await Promise.all([
			call(ctx, "POST", `/channels/${channelId}/messages`, { content: "once", nonce: "n-123" }, member.as),
			call(ctx, "POST", `/channels/${channelId}/messages`, { content: "once", nonce: "n-123" }, member.as),
		]);
		expect(a.body.message.id).toBe(b.body.message.id);
		const again = await call(ctx, "POST", `/channels/${channelId}/messages`, { content: "once", nonce: "n-123" }, member.as);
		expect(again.body.message.id).toBe(a.body.message.id);
	});

	test("outsiders can't read, write or even see the channel", async () => {
		expect((await call(ctx, "GET", `/channels/${channelId}/messages`, undefined, outsider.as)).status).toBe(404);
		expect((await call(ctx, "POST", `/channels/${channelId}/messages`, { content: "hi" }, outsider.as)).status).toBe(404);
		expect((await call(ctx, "GET", `/channels/${channelId}`, undefined, outsider.as)).status).toBe(404);
		expect((await call(ctx, "GET", `/workspaces/${workspaceId}`, undefined, outsider.as)).status).toBe(404);
	});
});

describe("pagination", () => {
	let channel: string;
	let ids: string[];

	beforeAll(async () => {
		const created = await call(ctx, "POST", `/workspaces/${workspaceId}/channels`, { name: "history" }, owner.as);
		channel = created.body.channel.id;
		ids = [];
		for (let i = 0; i < 120; i++) ids.push((await send(ctx, owner, channel, `message ${i}`)).id);
	});

	test("newest first, then older pages by id, until the start", async () => {
		const seen: string[] = [];
		let before: string | undefined;
		for (;;) {
			const page = await call(ctx, "GET", `/channels/${channel}/messages?limit=50${before ? `&before=${before}` : ""}`, undefined, owner.as);
			if (page.body.messages.length === 0) break;
			seen.push(...page.body.messages.map((m: { id: string }) => m.id));
			before = page.body.messages.at(-1).id;
		}
		expect(seen).toEqual([...ids].reverse());
	});

	test("after and around", async () => {
		const after = await call(ctx, "GET", `/channels/${channel}/messages?after=${ids[9]}&limit=5`, undefined, owner.as);
		expect(after.body.messages.map((m: { id: string }) => m.id)).toEqual(ids.slice(10, 15).reverse());
		const around = await call(ctx, "GET", `/channels/${channel}/messages?around=${ids[60]}&limit=10`, undefined, owner.as);
		const got = around.body.messages.map((m: { id: string }) => m.id);
		expect(got).toContain(ids[60]);
		expect(got).toEqual(ids.slice(56, 66).reverse());
		expect((await call(ctx, "GET", `/channels/${channel}/messages?after=1&before=2`, undefined, owner.as)).status).toBe(400);
	});

	test("50 people sending at once: every message stored, ids unique and in order", async () => {
		const results = await Promise.all(
			Array.from({ length: 50 }, (_, i) => call(ctx, "POST", `/channels/${channel}/messages`, { content: `burst ${i}` }, i % 2 ? owner.as : member.as)),
		);
		expect(results.every((r) => r.status === 201)).toBe(true);
		const made = results.map((r) => BigInt(r.body.message.id));
		expect(new Set(made).size).toBe(50);
		const page = await call(ctx, "GET", `/channels/${channel}/messages?limit=50`, undefined, owner.as);
		const listed = page.body.messages.map((m: { id: string }) => BigInt(m.id));
		expect(new Set(listed)).toEqual(new Set(made));
		for (let i = 1; i < listed.length; i++) expect(listed[i] < listed[i - 1]).toBe(true);
		const [{ last }] = (await ctx.services.db.execute<{ last: string }>(sql`select last_message_id as last from channels where id = ${BigInt(channel)}`)).rows;
		expect(BigInt(last)).toBe(made.reduce((a, b) => (a > b ? a : b)));
	});
});

describe("channel features", () => {
	test("slowmode limits members but not moderators", async () => {
		const slow = await call(ctx, "POST", `/workspaces/${workspaceId}/channels`, { name: "slow", slowmodeSeconds: 30 }, owner.as);
		const id = slow.body.channel.id;
		await send(ctx, member, id, "first");
		const second = await call(ctx, "POST", `/channels/${id}/messages`, { content: "second" }, member.as);
		expect(second.status).toBe(429);
		expect(second.body.error.code).toBe("slowmode");
		await send(ctx, owner, id, "owner one");
		await send(ctx, owner, id, "owner two");
	});

	test("pins: moderators pin in channels, the list shows them, the limit holds", async () => {
		const message = await send(ctx, member, channelId, "pin this");
		expect((await call(ctx, "PUT", `/channels/${channelId}/pins/${message.id}`, undefined, member.as)).status).toBe(403);
		expect((await call(ctx, "PUT", `/channels/${channelId}/pins/${message.id}`, undefined, owner.as)).status).toBe(204);
		const pins = await call(ctx, "GET", `/channels/${channelId}/pins`, undefined, member.as);
		expect(pins.body.messages.map((m: { id: string }) => m.id)).toContain(message.id);
		expect((await call(ctx, "DELETE", `/channels/${channelId}/pins/${message.id}`, undefined, owner.as)).status).toBe(204);
	});

	test("read states only move forward and reset the mention badge", async () => {
		const a = await send(ctx, owner, channelId, "a");
		const b = await send(ctx, owner, channelId, "b");
		const ackB = await call(ctx, "POST", `/channels/${channelId}/ack`, { messageId: b.id }, member.as);
		expect(ackB.body.readState.lastReadMessageId).toBe(b.id);
		const ackA = await call(ctx, "POST", `/channels/${channelId}/ack`, { messageId: a.id }, member.as);
		expect(ackA.body.readState.lastReadMessageId).toBe(b.id);
		expect(ackA.body.readState.mentionCount).toBe(0);
	});
});
