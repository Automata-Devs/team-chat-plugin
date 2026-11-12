import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { call, createTestApp, register, type TestContext } from "./helpers.js";

let ctx: TestContext;
beforeAll(async () => {
	ctx = await createTestApp();
});
afterAll(() => ctx.close());

describe("accounts and sessions", () => {
	test("register, use the token, read yourself", async () => {
		const user = await register(ctx, "Builderman");
		const me = await call(ctx, "GET", "/users/@me", undefined, user.as);
		expect(me.status).toBe(200);
		expect(me.body.user).toMatchObject({ id: user.id, username: "Builderman", isBot: false });
		expect(typeof me.body.user.id).toBe("string");
	});

	test("usernames are unique regardless of case, and validated", async () => {
		await register(ctx, "Taken_Name");
		expect((await call(ctx, "POST", "/auth/register", { username: "taken_name", password: "long enough pw" })).status).toBe(409);
		expect((await call(ctx, "POST", "/auth/register", { username: "no spaces!", password: "long enough pw" })).status).toBe(400);
		expect((await call(ctx, "POST", "/auth/register", { username: "shortpw", password: "short" })).status).toBe(400);
	});

	test("passwords are stored hashed, tokens only as hashes", async () => {
		const user = await register(ctx);
		const rows = await ctx.services.db.execute<{ password_hash: string }>(
			sql`select password_hash from user_credentials where user_id = ${BigInt(user.id)}`,
		);
		expect(rows.rows[0].password_hash.startsWith("scrypt$")).toBe(true);
		expect(rows.rows[0].password_hash).not.toContain("correct horse");
		const sessions = await ctx.services.db.execute(sql`select token_hash from sessions where user_id = ${BigInt(user.id)}`);
		expect(JSON.stringify(sessions.rows)).not.toContain(user.token);
	});

	test("login: right password works, wrong one and unknown user fail the same way", async () => {
		const user = await register(ctx, "loginperson");
		const ok = await call(ctx, "POST", "/auth/login", { username: "LOGINPERSON", password: "correct horse battery" });
		expect(ok.status).toBe(200);
		expect(ok.body.user.id).toBe(user.id);
		const wrong = await call(ctx, "POST", "/auth/login", { username: "loginperson", password: "nope nope nope" });
		const unknown = await call(ctx, "POST", "/auth/login", { username: "nobody_here", password: "nope nope nope" });
		expect(wrong.status).toBe(401);
		expect(unknown.status).toBe(401);
		expect(wrong.body.error.message).toBe(unknown.body.error.message);
		const audit = await call(ctx, "GET", "/users/@me/audit-log", undefined, user.as);
		expect(audit.body.entries.map((e: { action: string }) => e.action)).toContain("auth.login_failed");
	});

	test("logging out stops the token at once", async () => {
		const user = await register(ctx);
		expect((await call(ctx, "GET", "/users/@me", undefined, user.as)).status).toBe(200);
		expect((await call(ctx, "POST", "/auth/logout", undefined, user.as)).status).toBe(204);
		expect((await call(ctx, "GET", "/users/@me", undefined, user.as)).status).toBe(401);
	});

	test("sessions can be listed and revoked; a password change signs out the others", async () => {
		const user = await register(ctx, "multi_device");
		const second = await call(ctx, "POST", "/auth/login", { username: "multi_device", password: "correct horse battery" });
		const list = await call(ctx, "GET", "/auth/sessions", undefined, user.as);
		expect(list.body.sessions).toHaveLength(2);
		expect(list.body.sessions.filter((s: { current: boolean }) => s.current)).toHaveLength(1);

		const wrongCurrent = await call(ctx, "POST", "/auth/password", { currentPassword: "bad bad bad", newPassword: "another long pw" }, user.as);
		expect(wrongCurrent.status).toBe(403);
		const changed = await call(ctx, "POST", "/auth/password", { currentPassword: "correct horse battery", newPassword: "another long pw" }, user.as);
		expect(changed.status).toBe(204);
		expect((await call(ctx, "GET", "/users/@me", undefined, { token: second.body.token })).status).toBe(401);
		expect((await call(ctx, "GET", "/users/@me", undefined, user.as)).status).toBe(200);
		expect((await call(ctx, "POST", "/auth/login", { username: "multi_device", password: "another long pw" })).status).toBe(200);
	});

	test("no token, a bad token, or a made-up scheme is refused", async () => {
		expect((await call(ctx, "GET", "/users/@me")).status).toBe(401);
		expect((await call(ctx, "GET", "/users/@me", undefined, { token: "made-up" })).status).toBe(401);
		const weird = await ctx.app.inject({ method: "GET", url: "/api/v1/users/@me", headers: { authorization: "Basic abc" } });
		expect(weird.statusCode).toBe(401);
	});
});

describe("sign in with Roblox", () => {
	function fakeRoblox(sub: string, name: string) {
		ctx.respond = ({ url }) => {
			if (url.endsWith("/v1/token")) return Response.json({ access_token: "roblox-access", token_type: "Bearer" });
			if (url.endsWith("/v1/userinfo")) return Response.json({ sub, preferred_username: name, name: `${name} Display` });
			return new Response("not found", { status: 404 });
		};
	}

	async function start(token?: string) {
		const started = await call(ctx, "POST", "/auth/roblox/start", undefined, token ? { token } : {});
		expect(started.status).toBe(200);
		const state = new URL(started.body.url).searchParams.get("state")!;
		expect(new URL(started.body.url).searchParams.get("code_challenge_method")).toBe("S256");
		return { ...started.body, state };
	}

	test("the plugin polls, the browser finishes, the plugin gets a session", async () => {
		fakeRoblox("156", "rbx_maker");
		const flow = await start();
		const pending = await call(ctx, "POST", "/auth/roblox/poll", { loginId: flow.loginId, pollSecret: flow.pollSecret });
		expect(pending.status).toBe(202);

		const callback = await ctx.app.inject({ method: "GET", url: `/api/v1/auth/roblox/callback?code=abc&state=${flow.state}` });
		expect(callback.statusCode).toBe(200);
		expect(callback.body).toContain("signed in");
		const tokenCall = ctx.fetched.find((f) => f.url.endsWith("/v1/token"))!;
		expect(String(tokenCall.init.body)).toContain("code_verifier=");

		const done = await call(ctx, "POST", "/auth/roblox/poll", { loginId: flow.loginId, pollSecret: flow.pollSecret });
		expect(done.status).toBe(200);
		expect(done.body.user.username).toBe("rbx_maker");
		const connections = await call(ctx, "GET", "/auth/connections", undefined, { token: done.body.token });
		expect(connections.body.connections[0]).toMatchObject({ provider: "roblox", providerUserId: "156" });

		// The result is handed out once, and the state can't be replayed
		expect((await call(ctx, "POST", "/auth/roblox/poll", { loginId: flow.loginId, pollSecret: flow.pollSecret })).status).toBe(410);
		const replay = await ctx.app.inject({ method: "GET", url: `/api/v1/auth/roblox/callback?code=abc&state=${flow.state}` });
		expect(replay.statusCode).toBe(400);
	});

	test("signing in again finds the same account; a wrong poll secret is refused", async () => {
		fakeRoblox("777", "returning");
		const first = await start();
		await ctx.app.inject({ method: "GET", url: `/api/v1/auth/roblox/callback?code=a&state=${first.state}` });
		expect((await call(ctx, "POST", "/auth/roblox/poll", { loginId: first.loginId, pollSecret: "x".repeat(32) })).status).toBe(403);
		const one = await call(ctx, "POST", "/auth/roblox/poll", { loginId: first.loginId, pollSecret: first.pollSecret });

		const second = await start();
		await ctx.app.inject({ method: "GET", url: `/api/v1/auth/roblox/callback?code=b&state=${second.state}` });
		const two = await call(ctx, "POST", "/auth/roblox/poll", { loginId: second.loginId, pollSecret: second.pollSecret });
		expect(two.body.user.id).toBe(one.body.user.id);
	});

	test("a signed-in user links Roblox; another account can't take it", async () => {
		const user = await register(ctx);
		fakeRoblox("4242", "linker");
		const flow = await start(user.token);
		const page = await ctx.app.inject({ method: "GET", url: `/api/v1/auth/roblox/callback?code=c&state=${flow.state}` });
		expect(page.body).toContain("linked");
		const connections = await call(ctx, "GET", "/auth/connections", undefined, user.as);
		expect(connections.body.connections).toHaveLength(1);

		const other = await register(ctx);
		const steal = await start(other.token);
		const refused = await ctx.app.inject({ method: "GET", url: `/api/v1/auth/roblox/callback?code=d&state=${steal.state}` });
		expect(refused.statusCode).toBe(409);
	});

	test("Roblox refusing the code fails the sign-in", async () => {
		ctx.respond = () => new Response("bad", { status: 400 });
		const flow = await start();
		const page = await ctx.app.inject({ method: "GET", url: `/api/v1/auth/roblox/callback?code=bad&state=${flow.state}` });
		expect(page.statusCode).toBe(400);
		const poll = await call(ctx, "POST", "/auth/roblox/poll", { loginId: flow.loginId, pollSecret: flow.pollSecret });
		expect(poll.body.status).toBe("failed");
	});
});
