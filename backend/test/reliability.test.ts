import { mkdtempSync, rmSync } from "node:fs";
import { connect } from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import EmbeddedPostgres from "embedded-postgres";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { connectDatabase } from "../src/db/client.js";
import { runMigrations } from "../src/db/migrate.js";
import { call, createTestApp, register, send, type TestContext, workspaceWith } from "./helpers.js";

/** True while something still listens on the port. */
const portOpen = (port: number) =>
	new Promise<boolean>((resolve) => {
		const socket = connect(port, "127.0.0.1");
		socket.once("connect", () => (socket.destroy(), resolve(true)));
		socket.once("error", () => resolve(false));
	});

/**
 * On Windows embedded-postgres stops with taskkill, and reports "stopped" before
 * every child process has let go of the port: wait for it, and retry the start.
 */
async function restart(server: EmbeddedPostgres, port: number) {
	for (let attempt = 0; attempt < 20; attempt++) {
		while (await portOpen(port)) await new Promise((r) => setTimeout(r, 250));
		try {
			await server.start();
			return;
		} catch {
			await new Promise((r) => setTimeout(r, 1000));
		}
	}
	throw new Error("PostgreSQL didn't come back");
}

describe("database failure and recovery", () => {
	// Its own PostgreSQL, so it can be stopped without disturbing other test files
	let server: EmbeddedPostgres;
	let dir: string;
	let ctx: TestContext;
	const port = 55_000 + Math.floor(Math.random() * 900);

	beforeAll(async () => {
		dir = mkdtempSync(path.join(tmpdir(), "teamchat-pg-fail-"));
		server = new EmbeddedPostgres({ databaseDir: dir, user: "postgres", password: "postgres", port, persistent: true, initdbFlags: ["--encoding=UTF8", "--locale=C"], postgresFlags: ["-c", "io_method=sync"], onLog: () => {} });
		await server.initialise();
		await server.start();
		await server.createDatabase("app");
		const url = `postgres://postgres:postgres@127.0.0.1:${port}/app`;
		const handle = connectDatabase({ url, poolMax: 1 });
		await runMigrations(handle.db);
		await runMigrations(handle.db); // a second run is a no-op
		await handle.close();
		ctx = await createTestApp({}, { databaseUrl: url });
	});

	afterAll(async () => {
		await ctx?.close().catch(() => undefined);
		await server?.stop().catch(() => undefined);
		rmSync(dir, { recursive: true, force: true });
	});

	test("answers 503 while the database is down, then recovers by itself with no data lost", async () => {
		const user = await register(ctx);
		const { generalId } = await workspaceWith(ctx, user);
		const before = await send(ctx, user, generalId, "before the outage");
		expect((await call(ctx, "GET", "/health/ready")).status).toBe(200);

		// Cut every connection, then stop: like the database host going away
		const admin = new pg.Client({ connectionString: `postgres://postgres:postgres@127.0.0.1:${port}/postgres` });
		await admin.connect();
		await admin.query("select pg_terminate_backend(pid) from pg_stat_activity where datname = 'app'");
		await admin.end();
		await server.stop();
		const down = await call(ctx, "GET", `/channels/${generalId}/messages`, undefined, { token: "anything-not-cached" });
		expect([401, 503]).toContain(down.status); // auth lookup itself needs the database
		const failedSend = await call(ctx, "POST", `/channels/${generalId}/messages`, { content: "during" }, user.as);
		expect(failedSend.status).toBe(503);
		expect(failedSend.body.error.code).toBe("unavailable");
		expect(failedSend.headers["retry-after"]).toBe("5");
		const health = await call(ctx, "GET", "/health/ready");
		expect(health.status).toBe(503);
		expect(health.body).toMatchObject({ ok: false, database: false });

		await restart(server, port);
		let recovered = false;
		for (let i = 0; i < 50 && !recovered; i++) {
			recovered = (await call(ctx, "GET", "/health/ready")).status === 200;
			if (!recovered) await new Promise((r) => setTimeout(r, 200));
		}
		expect(recovered).toBe(true);
		const after = await send(ctx, user, generalId, "after the outage");
		const history = await call(ctx, "GET", `/channels/${generalId}/messages`, undefined, user.as);
		expect(history.body.messages.map((m: { id: string }) => m.id)).toEqual([after.id, before.id]);
	}, 120_000);

	test("a failed transaction leaves nothing half-written", async () => {
		const user = await register(ctx);
		const { generalId } = await workspaceWith(ctx, user);
		// An attachment id that doesn't exist makes the send fail after the message insert
		const failed = await call(ctx, "POST", `/channels/${generalId}/messages`, { content: "with file", attachments: ["123456789"] }, user.as);
		expect(failed.status).toBe(400);
		const client = new pg.Client({ connectionString: `postgres://postgres:postgres@127.0.0.1:${port}/app` });
		await client.connect();
		const rows = await client.query("select count(*)::int as n from messages where content = 'with file'");
		const jobs = await client.query("select count(*)::int as n from jobs where type = 'message.created' and payload->>'messageId' not in (select id::text from messages)");
		await client.end();
		expect(rows.rows[0].n).toBe(0);
		expect(jobs.rows[0].n).toBe(0);
	});
});

describe("rate limits and health", () => {
	let ctx: TestContext;
	beforeAll(async () => {
		ctx = await createTestApp({ RATE_LIMIT_SCALE: "1" });
	});
	afterAll(() => ctx.close());

	test("sign-in attempts are rate limited per address", async () => {
		const statuses: number[] = [];
		for (let i = 0; i < 12; i++) statuses.push((await call(ctx, "POST", "/auth/login", { username: "nobody", password: "guessing123" })).status);
		expect(statuses.slice(0, 10).every((s) => s === 401)).toBe(true);
		expect(statuses.slice(10)).toEqual([429, 429]);
		const limited = await call(ctx, "POST", "/auth/login", { username: "nobody", password: "guessing123" });
		expect(limited.headers["retry-after"]).toBeDefined();
		expect(limited.body.error.code).toBe("rate_limited");
	});

	test("sending is limited per person (10 per 10 seconds)", async () => {
		const ctx2 = await createTestApp({ RATE_LIMIT_SCALE: "1" });
		try {
			// Sign-up has its own tight limit, so make the user directly
			const { register: reg } = await import("./helpers.js");
			const scaled = await createTestApp({ RATE_LIMIT_SCALE: "1000" }, { databaseUrl: ctx2.services.config.DATABASE_URL });
			const user = await reg(scaled);
			const { generalId } = await workspaceWith(scaled, user);
			await scaled.close();
			const statuses = [];
			for (let i = 0; i < 12; i++) statuses.push((await call(ctx2, "POST", `/channels/${generalId}/messages`, { content: `m${i}` }, user.as)).status);
			expect(statuses.filter((s) => s === 201)).toHaveLength(10);
			expect(statuses.filter((s) => s === 429)).toHaveLength(2);
		} finally {
			await ctx2.close();
		}
	});

	test("liveness and readiness", async () => {
		expect((await call(ctx, "GET", "/health/live")).body).toEqual({ ok: true });
		const ready = await call(ctx, "GET", "/health/ready");
		expect(ready.body).toMatchObject({ ok: true, database: true, cache: true });
		expect((await call(ctx, "GET", "/nope")).status).toBe(404);
	});
});

describe("real-time gateway", () => {
	let ctx: TestContext;
	let base: string;
	beforeAll(async () => {
		ctx = await createTestApp();
		await ctx.app.listen({ port: 0, host: "127.0.0.1" });
		const address = ctx.app.server.address() as { port: number };
		base = `http://127.0.0.1:${address.port}/api/v1`;
	});
	afterAll(() => ctx.close());

	async function stream(token: string) {
		const controller = new AbortController();
		const response = await fetch(`${base}/gateway`, { headers: { authorization: `Bearer ${token}` }, signal: controller.signal });
		const reader = response.body!.getReader();
		const events: Array<{ type: string; data: any }> = [];
		let buffer = "";
		const pump = (async () => {
			try {
				for (;;) {
					const { value, done } = await reader.read();
					if (done) return;
					buffer += new TextDecoder().decode(value);
					let split;
					while ((split = buffer.indexOf("\n\n")) >= 0) {
						const frame = buffer.slice(0, split);
						buffer = buffer.slice(split + 2);
						const type = /^event: (.+)$/m.exec(frame)?.[1];
						const data = /^data: (.+)$/m.exec(frame)?.[1];
						if (type && data) events.push({ type, data: JSON.parse(data) });
					}
				}
			} catch {
				// aborted
			}
		})();
		const waitFor = async (predicate: (e: { type: string; data: any }) => boolean, ms = 3000) => {
			const until = Date.now() + ms;
			while (Date.now() < until) {
				const found = events.find(predicate);
				if (found) return found;
				await new Promise((r) => setTimeout(r, 25));
			}
			return undefined;
		};
		return { events, waitFor, close: () => (controller.abort(), pump) };
	}

	test("members get live events for channels they can see, and only those", async () => {
		const owner = await register(ctx);
		const member = await register(ctx);
		const outsider = await register(ctx);
		const { workspaceId, generalId } = await workspaceWith(ctx, owner, member);
		const secret = await call(ctx, "POST", `/workspaces/${workspaceId}/channels`, { name: "secret", isPrivate: true }, owner.as);

		const memberStream = await stream(member.token);
		const outsiderStream = await stream(outsider.token);
		expect(await memberStream.waitFor((e) => e.type === "ready")).toBeTruthy();
		expect(await outsiderStream.waitFor((e) => e.type === "ready")).toBeTruthy();

		await send(ctx, owner, generalId, "live hello");
		await send(ctx, owner, secret.body.channel.id, "private");
		const live = await memberStream.waitFor((e) => e.type === "message.create");
		expect(live?.data.content).toBe("live hello");
		await new Promise((r) => setTimeout(r, 200));
		expect(memberStream.events.filter((e) => e.type === "message.create")).toHaveLength(1);
		expect(outsiderStream.events.filter((e) => e.type === "message.create")).toHaveLength(0);

		// Joining a DM subscribes at once
		const dm = await call(ctx, "POST", "/conversations", { recipients: [outsider.id] }, owner.as);
		await outsiderStream.waitFor((e) => e.type === "conversation.create");
		await new Promise((r) => setTimeout(r, 200));
		await send(ctx, owner, dm.body.conversation.id, "psst");
		expect((await outsiderStream.waitFor((e) => e.type === "message.create"))?.data.content).toBe("psst");

		await memberStream.close();
		await outsiderStream.close();
	});
});

describe("request parsing", () => {
	let ctx: TestContext;
	beforeAll(async () => {
		ctx = await createTestApp({ ROBLOX_OAUTH_CLIENT_ID: "" });
	});
	afterAll(() => ctx.close());

	test("an empty JSON body is no body; bad or poisoned JSON is a 400", async () => {
		const empty = await ctx.app.inject({ method: "POST", url: "/api/v1/auth/roblox/start", headers: { "content-type": "application/json" }, payload: "" });
		expect(empty.statusCode).toBe(503);
		const bad = await ctx.app.inject({ method: "POST", url: "/api/v1/auth/login", headers: { "content-type": "application/json" }, payload: "{nope" });
		expect(bad.statusCode).toBe(400);
		const poisoned = await ctx.app.inject({
			method: "POST",
			url: "/api/v1/auth/login",
			headers: { "content-type": "application/json" },
			payload: '{"username":"a","password":"b","__proto__":{"admin":true}}',
		});
		expect(poisoned.statusCode).toBe(400);
	});
});
