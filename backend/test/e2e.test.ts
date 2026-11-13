import { readFileSync } from "node:fs";
import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { call, createTestApp, register, send, type TestContext, type TestUser } from "./helpers.js";
import { open, proofOf, seal } from "./sealing.js";

let ctx: TestContext;
beforeAll(async () => {
	ctx = await createTestApp();
});
afterAll(() => ctx.close());

const SECRET = "0123456789abcdef".repeat(4);
let placeNumber = 9000;

async function newPlace(...people: TestUser[]) {
	const key = `place:${placeNumber++}`;
	let joined: { workspace: { id: string }; teamChatChannelId: string } | undefined;
	for (const person of people) {
		const response = await call(ctx, "POST", `/places/${key}/workspace`, { proof: proofOf(SECRET), name: "Obby" }, person.as);
		expect(response.status).toBe(200);
		joined = response.body;
	}
	return joined!;
}

const batch = (channelId: string, user: TestUser, messages: object[]) =>
	call(ctx, "POST", `/channels/${channelId}/messages/batch`, { messages }, user.as);

describe("a place's messages are end-to-end encrypted", () => {
	test("the plugin and this reference seal the same way", () => {
		// Sealed in Studio by src/Services/Backend/Seal.luau with SECRET
		const fromLuau = "e2e1:9NSPLKkRcA3YY9FJ1jef8hrBVdkb1LPmWr24y8/DS7hpNE1rZ5w15HdvT0XtcNZmXWRd8qvXDhcl";
		expect(open(SECRET, fromLuau)).toBe('Hello from Luau 🐉 "quoted"');
		expect(proofOf(SECRET)).toBe("a8ae6e6ee929abea3afcfc5258c8ccd6f85273e0d4626d26c7279f3250f77c8e");
	});

	test("sealed messages are stored as they are, and only the place's key opens them", async () => {
		const ana = await register(ctx);
		const { teamChatChannelId: channel } = await newPlace(ana);
		const content = seal(SECRET, "the boss fight is on floor 3 🐉");
		const clientData = { e2e: seal(SECRET, JSON.stringify({ sender: "Ana", messageType: "Text" })) };
		expect((await batch(channel, ana, [{ content, nonce: "msg_1", clientData }])).status).toBe(200);

		const [row] = (
			await ctx.services.db.execute<{ content: string; metadata: { client: { e2e: string } } }>(
				sql`select content, metadata from messages where channel_id = ${BigInt(channel)} and nonce = 'msg_1'`,
			)
		).rows;
		expect(row.content).toBe(content);
		expect(JSON.stringify(row)).not.toContain("boss");
		expect(open(SECRET, row.content)).toBe("the boss fight is on floor 3 🐉");
		expect(JSON.parse(open(SECRET, row.metadata.client.e2e)!)).toEqual({ sender: "Ana", messageType: "Text" });
		expect(open("another place's secret".padEnd(64, "!"), row.content)).toBeNull();
	});

	test("readable text is refused everywhere in a place: team chat, DMs, edits", async () => {
		const [ana, bo] = await Promise.all([register(ctx), register(ctx)]);
		const { workspace, teamChatChannelId: channel } = await newPlace(ana, bo);
		const dm = (await call(ctx, "POST", "/conversations", { recipients: [bo.id], workspaceId: workspace.id }, ana.as)).body
			.conversation.id;
		const refused = (response: { status: number; body: { error?: { code: string } } }) => {
			expect(response.status).toBe(400);
			expect(response.body.error?.code).toBe("encryption_required");
		};

		refused(await batch(channel, ana, [{ content: "hello", nonce: "p1" }]));
		refused(await batch(dm, ana, [{ content: seal(SECRET, "hi"), nonce: "p2", clientData: { sender: "Ana" } }]));
		refused(await batch(dm, ana, [{ content: seal(SECRET, "hi"), nonce: "p3", clientData: { e2e: seal(SECRET, "{}"), sender: "Ana" } }]));
		refused(await call(ctx, "POST", `/channels/${channel}/messages`, { content: "hello" }, ana.as));

		const stored = await batch(dm, ana, [{ content: seal(SECRET, "hi"), nonce: "p4" }]);
		expect(stored.status).toBe(200);
		const id = stored.body.messages[0].id;
		refused(await call(ctx, "PATCH", `/channels/${dm}/messages/${id}`, { content: "readable again" }, ana.as));
		const edited = await call(ctx, "PATCH", `/channels/${dm}/messages/${id}`, { content: seal(SECRET, "hey") }, ana.as);
		expect(edited.status).toBe(200);
		expect(open(SECRET, edited.body.message.content)).toBe("hey");
	});

	test("long messages fit once sealed, but readable text keeps its limit", async () => {
		const ana = await register(ctx);
		const { teamChatChannelId: channel } = await newPlace(ana);
		const long = "é".repeat(4000); // 8000 bytes: more than 4000 characters once sealed
		expect((await batch(channel, ana, [{ content: seal(SECRET, long), nonce: "long" }])).status).toBe(200);
		expect((await batch(channel, ana, [{ content: "e2e1:not base64!", nonce: "bad" }])).status).toBe(400);
	});

	test("workspaces that aren't a place still take readable text", async () => {
		const ana = await register(ctx);
		const ws = await call(ctx, "POST", "/workspaces", { name: "Studio crew" }, ana.as);
		const channels = await call(ctx, "GET", `/workspaces/${ws.body.workspace.id}/channels`, undefined, ana.as);
		const text = channels.body.channels.find((c: { type: string }) => c.type === "text").id;
		expect((await send(ctx, ana, text, "plain is fine here")).content).toBe("plain is fine here");
	});
});

describe("the place's secret never reaches the server", () => {
	test("joining takes a proof of the secret; an old plugin sending the secret is told to update", async () => {
		const ana = await register(ctx);
		const old = await call(ctx, "POST", "/places/place:9500/workspace", { secret: SECRET, name: "Obby" }, ana.as);
		expect(old.status).toBe(426);
		expect((await call(ctx, "POST", "/places/place:9500/workspace", { proof: "short" }, ana.as)).status).toBe(400);
		expect((await call(ctx, "POST", "/places/place:9500/workspace", { proof: proofOf(SECRET) }, ana.as)).status).toBe(200);
		const [row] = (
			await ctx.services.db.execute<{ hash: string }>(
				sql`select encode(place_secret_hash, 'hex') as hash from workspaces where place_key = 'place:9500'`,
			)
		).rows;
		expect(row.hash).not.toContain(proofOf(SECRET));
	});

	test("the migration turns a stored sha256(secret) into sha256(proof), so places made before keep working", async () => {
		const ana = await register(ctx);
		const { workspace } = await newPlace(ana);
		// As 1.32 stored it: sha256 of the secret itself
		await ctx.services.db.execute(
			sql`update workspaces set place_secret_hash = sha256(convert_to(${SECRET}, 'UTF8')) where id = ${BigInt(workspace.id)}`,
		);
		const migration = readFileSync(new URL("../migrations/0002_end_to_end.sql", import.meta.url), "utf8");
		const rehash = migration.split("\n").find((line) => line.startsWith('UPDATE "workspaces"'))!;
		await ctx.services.db.execute(sql.raw(rehash));
		const bo = await register(ctx);
		const key = (
			await ctx.services.db.execute<{ place_key: string }>(sql`select place_key from workspaces where id = ${BigInt(workspace.id)}`)
		).rows[0].place_key;
		const joined = await call(ctx, "POST", `/places/${key}/workspace`, { proof: proofOf(SECRET) }, bo.as);
		expect(joined.status).toBe(200);
		expect(joined.body.created).toBe(false);
	});
});
