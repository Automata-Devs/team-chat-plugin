import { createHmac } from "node:crypto";
import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { Permission } from "../src/lib/permissions.js";
import { call, createTestApp, register, send, type TestContext, type TestUser, workspaceWith } from "./helpers.js";

let ctx: TestContext;
let owner: TestUser;
let workspaceId: string;
let generalId: string;

beforeAll(async () => {
	ctx = await createTestApp();
	owner = await register(ctx);
	({ workspaceId, generalId } = await workspaceWith(ctx, owner));
});
afterAll(() => ctx.close());

async function makeBot(name: string, extra: object = {}) {
	const created = await call(ctx, "POST", "/bots", { username: name, eventsUrl: "https://bot.example.com/events", events: ["message.create"], ...extra }, owner.as);
	expect(created.status).toBe(201);
	return created.body as { bot: { id: string }; token: string; signingSecret: string };
}

describe("bots", () => {
	test("registration shows the token and secret once; only a hash and ciphertext are stored", async () => {
		const { bot, token, signingSecret } = await makeBot("weather_bot");
		expect(token.split(".")).toHaveLength(2);
		const stored = await ctx.services.db.execute<{ token_hash: Buffer; signing_secret: string }>(
			sql`select token_hash, signing_secret from bots where user_id = ${BigInt(bot.id)}`,
		);
		expect(stored.rows[0].token_hash.toString("hex")).not.toContain(Buffer.from(token).toString("hex"));
		expect(stored.rows[0].signing_secret).not.toContain(signingSecret);
		expect(stored.rows[0].signing_secret.startsWith("v1.")).toBe(true);
		const view = await call(ctx, "GET", `/bots/${bot.id}`, undefined, owner.as);
		expect(JSON.stringify(view.body)).not.toContain(token);
	});

	test("a bot authenticates with its token, but not on person-only routes", async () => {
		const { bot, token } = await makeBot("auth_bot");
		const me = await call(ctx, "GET", "/users/@me", undefined, { bot: token });
		expect(me.body.user).toMatchObject({ id: bot.id, isBot: true });
		expect((await call(ctx, "GET", "/users/@me/settings", undefined, { bot: token })).status).toBe(403);
		expect((await call(ctx, "POST", "/workspaces", { name: "nope" }, { bot: token })).status).toBe(403);
		expect((await call(ctx, "GET", "/users/@me", undefined, { bot: `${token}x` })).status).toBe(401);
	});

	test("it sees nothing until installed, then only what its role allows", async () => {
		const { bot, token } = await makeBot("install_bot");
		expect((await call(ctx, "GET", `/channels/${generalId}/messages`, undefined, { bot: token })).status).toBe(404);

		const member = await register(ctx);
		const invite = await call(ctx, "POST", `/workspaces/${workspaceId}/invites`, {}, owner.as);
		await call(ctx, "POST", `/invites/${invite.body.invite.code}`, undefined, member.as);
		// Members without MANAGE_BOTS can't install
		expect((await call(ctx, "POST", `/workspaces/${workspaceId}/bots`, { botId: bot.id }, member.as)).status).toBe(403);

		expect((await call(ctx, "POST", `/workspaces/${workspaceId}/bots`, { botId: bot.id }, owner.as)).status).toBe(204);
		const message = await send(ctx, { bot: token }, generalId, "Hello from a bot");
		expect(message.author).toMatchObject({ id: bot.id, isBot: true });
		// Its managed role can't be edited or given away
		const roles = await call(ctx, "GET", `/workspaces/${workspaceId}/roles`, undefined, owner.as);
		const managed = roles.body.roles.find((r: { managed: boolean }) => r.managed);
		expect((await call(ctx, "PATCH", `/workspaces/${workspaceId}/roles/${managed.id}`, { name: "x" }, owner.as)).status).toBe(403);
		// Can't delete what others wrote (no MANAGE_MESSAGES)
		const human = await send(ctx, owner, generalId, "mine");
		expect((await call(ctx, "DELETE", `/channels/${generalId}/messages/${human.id}`, undefined, { bot: token })).status).toBe(403);

		expect((await call(ctx, "DELETE", `/workspaces/${workspaceId}/bots/${bot.id}`, undefined, owner.as)).status).toBe(204);
		expect((await call(ctx, "GET", `/channels/${generalId}/messages`, undefined, { bot: token })).status).toBe(404);
	});

	test("resetting the token or disabling the bot stops the old token at once", async () => {
		const { bot, token } = await makeBot("rotate_bot");
		const reset = await call(ctx, "POST", `/bots/${bot.id}/token`, undefined, owner.as);
		expect((await call(ctx, "GET", "/users/@me", undefined, { bot: token })).status).toBe(401);
		expect((await call(ctx, "GET", "/users/@me", undefined, { bot: reset.body.token })).status).toBe(200);
		await call(ctx, "PATCH", `/bots/${bot.id}`, { status: "disabled" }, owner.as);
		expect((await call(ctx, "GET", "/users/@me", undefined, { bot: reset.body.token })).status).toBe(403);
		const stranger = await register(ctx);
		expect((await call(ctx, "POST", `/bots/${bot.id}/token`, undefined, stranger.as)).status).toBe(404);
	});

	test("bot events are signed and only go to bots that can see the channel", async () => {
		const { bot, token, signingSecret } = await makeBot("events_bot");
		await call(ctx, "POST", `/workspaces/${workspaceId}/bots`, { botId: bot.id }, owner.as);
		const hidden = await call(ctx, "POST", `/workspaces/${workspaceId}/channels`, { name: "hidden", isPrivate: true }, owner.as);

		await ctx.services.jobs.drain(); // events of earlier tests' messages
		ctx.fetched.length = 0;
		ctx.respond = () => new Response(null, { status: 204 });
		await send(ctx, owner, generalId, "visible to the bot");
		await send(ctx, owner, hidden.body.channel.id, "not for bots");
		await ctx.services.jobs.drain();

		const deliveries = ctx.fetched.filter((f) => f.url === "https://bot.example.com/events");
		expect(deliveries).toHaveLength(1);
		const headers = deliveries[0].init.headers as Record<string, string>;
		const body = String(deliveries[0].init.body);
		const expected = createHmac("sha256", signingSecret).update(`${headers["X-TeamChat-Timestamp"]}.${body}`).digest("hex");
		expect(headers["X-TeamChat-Signature"]).toBe(expected);
		expect(JSON.parse(body)).toMatchObject({ type: "message.create", data: { message: { content: "visible to the bot" } } });

		// Its own messages don't echo back to it
		ctx.fetched.length = 0;
		await send(ctx, { bot: token }, generalId, "from the bot");
		await ctx.services.jobs.drain();
		expect(ctx.fetched.filter((f) => f.url === "https://bot.example.com/events")).toHaveLength(0);
	});

	test("failed deliveries are retried by the job queue", async () => {
		const { bot } = await makeBot("flaky_bot");
		await call(ctx, "POST", `/workspaces/${workspaceId}/bots`, { botId: bot.id }, owner.as);
		ctx.respond = () => new Response("down", { status: 503 });
		await send(ctx, owner, generalId, "will fail first");
		await ctx.services.jobs.drain();
		const waiting = await ctx.services.db.execute<{ attempts: number; last_error: string }>(
			sql`select attempts, last_error from jobs where type = 'bot.deliver' and payload->>'botId' = ${bot.id}`,
		);
		expect(waiting.rows[0].attempts).toBe(1);
		expect(waiting.rows[0].last_error).toContain("503");
		await call(ctx, "DELETE", `/workspaces/${workspaceId}/bots/${bot.id}`, undefined, owner.as);
	});

	test("commands: registered by the bot, run by members, answered with the interaction id", async () => {
		const { bot, token } = await makeBot("cmd_bot");
		await call(ctx, "POST", `/workspaces/${workspaceId}/bots`, { botId: bot.id }, owner.as);
		const commands = [{ name: "forecast", description: "The weather", options: [{ name: "city", type: "string", required: true }] }];
		expect((await call(ctx, "PUT", `/bots/${bot.id}/commands`, commands, { bot: token })).status).toBe(204);
		const listed = await call(ctx, "GET", `/workspaces/${workspaceId}/commands`, undefined, owner.as);
		expect(listed.body.commands.map((c: { name: string }) => c.name)).toContain("forecast");

		ctx.fetched.length = 0;
		ctx.respond = () => new Response(null, { status: 204 });
		const run = await call(ctx, "POST", `/channels/${generalId}/interactions`, { botId: bot.id, command: "forecast", options: { city: "Amsterdam" } }, owner.as);
		expect(run.status).toBe(202);
		await ctx.services.jobs.drain();
		const event = JSON.parse(String(ctx.fetched.find((f) => f.url.includes("bot.example.com"))!.init.body));
		expect(event).toMatchObject({ type: "interaction.create", data: { command: "forecast", options: { city: "Amsterdam" }, user: { id: owner.id } } });

		const answer = await send(ctx, { bot: token }, generalId, "Sunny", { interactionId: run.body.interactionId });
		expect(answer.type).toBe("command");
		expect(answer.metadata.interaction).toMatchObject({ command: "forecast", userId: owner.id });
		// An interaction is answered once, and only by its own bot
		expect((await call(ctx, "POST", `/channels/${generalId}/messages`, { content: "again", interactionId: run.body.interactionId }, { bot: token })).status).toBe(400);
		expect((await call(ctx, "POST", `/channels/${generalId}/interactions`, { botId: bot.id, command: "nope" }, owner.as)).status).toBe(404);
	});

	test("event URLs inside the network are refused (SSRF)", async () => {
		for (const eventsUrl of ["https://127.0.0.1/x", "https://localhost/x", "http://bot.example.com/x", "https://internal-api.corp/x", "https://[::1]/x"]) {
			const response = await call(ctx, "POST", "/bots", { username: `ssrf_${Math.random().toString(36).slice(2, 8)}`, eventsUrl }, owner.as);
			expect(response.status, eventsUrl).toBe(400);
		}
	});

	test("installers can't give a bot more than they have", async () => {
		const { bot } = await makeBot("greedy_bot", { isPublic: true });
		const mod = await register(ctx);
		const invite = await call(ctx, "POST", `/workspaces/${workspaceId}/invites`, {}, owner.as);
		await call(ctx, "POST", `/invites/${invite.body.invite.code}`, undefined, mod.as);
		const role = await call(ctx, "POST", `/workspaces/${workspaceId}/roles`, { name: "Bot manager", position: 2, permissions: Permission.MANAGE_BOTS.toString() }, owner.as);
		await call(ctx, "PUT", `/workspaces/${workspaceId}/members/${mod.id}/roles/${role.body.role.id}`, undefined, owner.as);
		const greedy = await call(ctx, "POST", `/workspaces/${workspaceId}/bots`, { botId: bot.id, permissions: Permission.ADMINISTRATOR.toString() }, mod.as);
		expect(greedy.status).toBe(403);
	});
});
