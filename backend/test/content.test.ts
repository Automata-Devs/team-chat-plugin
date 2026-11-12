import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { call, createTestApp, register, send, type TestContext, type TestUser, workspaceWith } from "./helpers.js";

let ctx: TestContext;
let owner: TestUser;
let member: TestUser;
let outsider: TestUser;
let workspaceId: string;
let generalId: string;

beforeAll(async () => {
	ctx = await createTestApp({ MAX_UPLOAD_BYTES: "1000000" });
	owner = await register(ctx);
	member = await register(ctx);
	outsider = await register(ctx);
	({ workspaceId, generalId } = await workspaceWith(ctx, owner, member));
});
afterAll(() => ctx.close());

async function upload(user: TestUser, channelId: string, size = 1234, contentType = "image/png") {
	const started = await call(ctx, "POST", `/channels/${channelId}/attachments`, { filename: "../map preview.png", contentType, size }, user.as);
	expect(started.status).toBe(201);
	const key = decodeURIComponent(started.body.upload.url.replace("memory://upload/", ""));
	return { id: started.body.attachment.id as string, key, filename: started.body.attachment.filename as string };
}

describe("attachments", () => {
	test("metadata in Postgres, bytes in storage; the upload is checked before use", async () => {
		const file = await upload(member, generalId);
		expect(file.filename).toBe("map preview.png");
		// Not uploaded yet: can't complete, can't attach
		expect((await call(ctx, "POST", `/attachments/${file.id}/complete`, undefined, member.as)).status).toBe(400);
		expect((await call(ctx, "POST", `/channels/${generalId}/messages`, { attachments: [file.id] }, member.as)).status).toBe(400);
		// A different size than declared is refused and removed
		ctx.storage.put(file.key, 9999, "image/png");
		expect((await call(ctx, "POST", `/attachments/${file.id}/complete`, undefined, member.as)).status).toBe(400);
		expect(ctx.storage.objects.has(file.key)).toBe(false);

		ctx.storage.put(file.key, 1234, "image/png");
		const done = await call(ctx, "POST", `/attachments/${file.id}/complete`, undefined, member.as);
		expect(done.body.attachment.status).toBe("uploaded");
		const message = await send(ctx, member, generalId, "", { attachments: [file.id] });
		expect(message.attachments).toEqual([expect.objectContaining({ id: file.id, contentType: "image/png", size: 1234 })]);
		// Used once only, and only by its uploader
		expect((await call(ctx, "POST", `/channels/${generalId}/messages`, { attachments: [file.id] }, member.as)).status).toBe(400);

		const link = await call(ctx, "GET", `/attachments/${file.id}`, undefined, owner.as);
		expect(link.body.url).toContain("memory://download/");
		expect((await call(ctx, "GET", `/attachments/${file.id}`, undefined, outsider.as)).status).toBe(404);

		// Deleting the message removes the file from storage too
		await call(ctx, "DELETE", `/channels/${generalId}/messages/${message.id}`, undefined, member.as);
		await ctx.services.jobs.drain();
		expect(ctx.storage.objects.has(file.key)).toBe(false);
		expect((await call(ctx, "GET", `/attachments/${file.id}`, undefined, owner.as)).status).toBe(404);
	});

	test("size limit, MIME check and the ATTACH_FILES permission", async () => {
		expect((await call(ctx, "POST", `/channels/${generalId}/attachments`, { filename: "big.bin", contentType: "application/octet-stream", size: 2_000_000 }, member.as)).status).toBe(413);
		expect((await call(ctx, "POST", `/channels/${generalId}/attachments`, { filename: "x", contentType: "not a type", size: 10 }, member.as)).status).toBe(400);
		expect((await call(ctx, "POST", `/channels/${generalId}/attachments`, { filename: "x.png", contentType: "image/png", size: 10 }, outsider.as)).status).toBe(404);
		const noFiles = await call(ctx, "POST", `/workspaces/${workspaceId}/channels`, { name: "no-files" }, owner.as);
		await call(ctx, "PUT", `/channels/${noFiles.body.channel.id}/permissions/role/${workspaceId}`, { deny: String(1n << 4n) }, owner.as);
		expect((await call(ctx, "POST", `/channels/${noFiles.body.channel.id}/attachments`, { filename: "x.png", contentType: "image/png", size: 10 }, member.as)).status).toBe(403);
	});

	test("abandoned uploads are cleaned up", async () => {
		const file = await upload(member, generalId, 50);
		ctx.storage.put(file.key, 50, "image/png");
		await ctx.services.db.execute(sql`update attachments set created_at = now() - interval '2 days' where id = ${BigInt(file.id)}`);
		await ctx.services.db.execute(sql`insert into jobs (type, payload) values ('attachments.cleanup', '{}')`);
		await ctx.services.jobs.drain();
		expect(ctx.storage.objects.has(file.key)).toBe(false);
		const left = await ctx.services.db.execute(sql`select 1 from attachments where id = ${BigInt(file.id)}`);
		expect(left.rows).toHaveLength(0);
	});
});

describe("reactions", () => {
	test("add, count, remove; one per person per emoji; validated emoji", async () => {
		const message = await send(ctx, owner, generalId, "react to me");
		const path = (emoji: string) => `/channels/${generalId}/messages/${message.id}/reactions/${encodeURIComponent(emoji)}/@me`;
		expect((await call(ctx, "PUT", path("👍"), undefined, member.as)).status).toBe(204);
		expect((await call(ctx, "PUT", path("👍"), undefined, member.as)).status).toBe(204);
		expect((await call(ctx, "PUT", path("👍"), undefined, owner.as)).status).toBe(204);
		expect((await call(ctx, "PUT", path("not-emoji"), undefined, owner.as)).status).toBe(400);
		expect((await call(ctx, "PUT", path("👍"), undefined, outsider.as)).status).toBe(404);

		const got = await call(ctx, "GET", `/channels/${generalId}/messages/${message.id}`, undefined, member.as);
		expect(got.body.message.reactions).toEqual([{ emoji: "👍", count: 2, me: true }]);
		const who = await call(ctx, "GET", `/channels/${generalId}/messages/${message.id}/reactions/${encodeURIComponent("👍")}`, undefined, member.as);
		expect(who.body.users).toHaveLength(2);

		await call(ctx, "DELETE", path("👍"), undefined, member.as);
		const after = await call(ctx, "GET", `/channels/${generalId}/messages/${message.id}`, undefined, member.as);
		expect(after.body.message.reactions).toEqual([{ emoji: "👍", count: 1, me: false }]);
	});

	test("at most 20 different emoji on a message, also when added at once", async () => {
		const message = await send(ctx, owner, generalId, "so many");
		const emojis = ["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚", "😋", "😛", "😝", "😜"];
		const results = await Promise.all(
			emojis.map((e) => call(ctx, "PUT", `/channels/${generalId}/messages/${message.id}/reactions/${encodeURIComponent(e)}/@me`, undefined, owner.as)),
		);
		expect(results.filter((r) => r.status === 204)).toHaveLength(20);
	});
});

describe("search", () => {
	test("full text with prefixes, author and date filters, newest first, with a cursor", async () => {
		const searcher = await register(ctx);
		const space = await workspaceWith(ctx, searcher, member);
		await send(ctx, searcher, space.generalId, "The lighting pass is finished");
		await send(ctx, member, space.generalId, "Lighting looks great");
		await send(ctx, member, space.generalId, "Terrain needs work");

		const prefix = await call(ctx, "GET", `/search/messages?q=light&workspaceId=${space.workspaceId}`, undefined, searcher.as);
		expect(prefix.body.messages.map((m: { content: string }) => m.content)).toEqual(["Lighting looks great", "The lighting pass is finished"]);
		const byAuthor = await call(ctx, "GET", `/search/messages?q=lighting&authorId=${member.id}&workspaceId=${space.workspaceId}`, undefined, searcher.as);
		expect(byAuthor.body.messages).toHaveLength(1);
		const future = await call(ctx, "GET", `/search/messages?q=lighting&after=${encodeURIComponent(new Date(Date.now() + 60_000).toISOString())}`, undefined, searcher.as);
		expect(future.body.messages).toHaveLength(0);
		const page = await call(ctx, "GET", `/search/messages?q=lighting&limit=1&workspaceId=${space.workspaceId}`, undefined, searcher.as);
		const next = await call(ctx, "GET", `/search/messages?q=lighting&limit=1&workspaceId=${space.workspaceId}&cursor=${page.body.nextCursor}`, undefined, searcher.as);
		expect(next.body.messages[0].content).toBe("The lighting pass is finished");
		// Tsquery syntax in the text is just text
		expect((await call(ctx, "GET", "/search/messages?q=" + encodeURIComponent("a & | ! :* ("), undefined, searcher.as)).status).toBe(200);
	});

	test("never returns messages the searcher can't read", async () => {
		const stranger = await register(ctx);
		await send(ctx, owner, generalId, "confidential roadmap");
		expect((await call(ctx, "GET", "/search/messages?q=confidential", undefined, stranger.as)).body.messages).toHaveLength(0);
		expect((await call(ctx, "GET", `/search/messages?q=confidential&workspaceId=${workspaceId}`, undefined, stranger.as)).status).toBe(404);
		expect((await call(ctx, "GET", `/search/messages?q=confidential&channelId=${generalId}`, undefined, stranger.as)).status).toBe(404);
		expect((await call(ctx, "GET", "/search/messages?q=confidential", undefined, member.as)).body.messages).toHaveLength(1);
	});
});

describe("notifications", () => {
	test("mentions and replies reach the inbox and the badge; blocks and settings are respected", async () => {
		const target = await register(ctx);
		const space = await workspaceWith(ctx, owner, target, member);
		const original = await send(ctx, target, space.generalId, "my question");
		await send(ctx, member, space.generalId, `hey <@${target.id}>`);
		await send(ctx, owner, space.generalId, "answer", { replyTo: original.id });
		await ctx.services.jobs.drain();

		const inbox = await call(ctx, "GET", "/notifications", undefined, target.as);
		expect(inbox.body.notifications.map((n: { type: string }) => n.type).sort()).toEqual(["mention", "reply"]);
		const states = await call(ctx, "GET", "/users/@me/read-states", undefined, target.as);
		expect(states.body.readStates.find((s: { channelId: string }) => s.channelId === space.generalId).mentionCount).toBe(2);

		await call(ctx, "PUT", `/users/@me/relationships/${member.id}`, { type: "block" }, target.as);
		await call(ctx, "PATCH", "/users/@me/settings", { notifications: { replies: false } }, target.as);
		await send(ctx, member, space.generalId, `again <@${target.id}>`);
		await send(ctx, owner, space.generalId, "another answer", { replyTo: original.id });
		await ctx.services.jobs.drain();
		expect((await call(ctx, "GET", "/notifications", undefined, target.as)).body.notifications).toHaveLength(2);

		await call(ctx, "POST", "/notifications/read", { upTo: inbox.body.notifications[0].id }, target.as);
		expect((await call(ctx, "GET", "/notifications?unread=true", undefined, target.as)).body.notifications).toHaveLength(0);
	});

	test("a mention in a channel the person can't see notifies nobody", async () => {
		const target = await register(ctx);
		const space = await workspaceWith(ctx, owner, target);
		const hidden = await call(ctx, "POST", `/workspaces/${space.workspaceId}/channels`, { name: "hidden", isPrivate: true }, owner.as);
		await send(ctx, owner, hidden.body.channel.id, `<@${target.id}> secret`);
		await ctx.services.jobs.drain();
		expect((await call(ctx, "GET", "/notifications", undefined, target.as)).body.notifications).toHaveLength(0);
	});
});
