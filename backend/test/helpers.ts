import { randomBytes } from "node:crypto";
import type { FastifyInstance } from "fastify";
import pg from "pg";
import pino from "pino";
import { inject } from "vitest";
import { buildApp } from "../src/app.js";
import { bootstrap, type Runtime } from "../src/bootstrap.js";
import { loadConfig } from "../src/config.js";
import type { Services } from "../src/context.js";
import { MemoryStorage } from "../src/infra/storage.js";

/** A fresh database copied from the migrated template. */
export async function createTestDatabase(): Promise<string> {
	const name = `t_${randomBytes(6).toString("hex")}`;
	const admin = new pg.Client({ connectionString: inject("pgAdminUrl") });
	await admin.connect();
	try {
		// Copying a template fails while another copy is reading it: wait and retry
		for (let attempt = 0; ; attempt++) {
			try {
				await admin.query(`create database "${name}" template teamchat_template`);
				break;
			} catch (error) {
				if (attempt > 40 || !/being accessed by other users/.test(String(error))) throw error;
				await new Promise((resolve) => setTimeout(resolve, 100 + Math.random() * 200));
			}
		}
	} finally {
		await admin.end();
	}
	return `${inject("pgBaseUrl")}/${name}`;
}

export interface FetchCall {
	url: string;
	init: RequestInit;
}

export interface TestContext {
	app: FastifyInstance;
	services: Services;
	runtime: Runtime;
	storage: MemoryStorage;
	/** Outgoing requests (Roblox, bot event URLs) land here; set `respond` to answer them. */
	fetched: FetchCall[];
	respond: (call: FetchCall) => Promise<Response> | Response;
	close(): Promise<void>;
}

export async function createTestApp(env: Record<string, string> = {}, options: { databaseUrl?: string } = {}): Promise<TestContext> {
	const config = loadConfig({
		NODE_ENV: "test",
		LOG_LEVEL: "silent",
		DATABASE_URL: options.databaseUrl ?? (await createTestDatabase()),
		ENCRYPTION_KEY: randomBytes(32).toString("base64"),
		PUBLIC_URL: "https://chat.test",
		RATE_LIMIT_SCALE: "1000",
		ROBLOX_OAUTH_CLIENT_ID: "client-id",
		ROBLOX_OAUTH_CLIENT_SECRET: "client-secret",
		ROBLOX_OAUTH_BASE_URL: "https://roblox.test/oauth",
		DATABASE_POOL_MAX: "10",
		...env,
	});
	const storage = new MemoryStorage();
	const context = {
		fetched: [] as FetchCall[],
		respond: (() => new Response("{}", { status: 200 })) as TestContext["respond"],
	};
	const runtime = await bootstrap(config, {
		log: pino({ level: process.env.TEST_LOG ? "error" : "silent" }),
		storage,
		fetch: (async (input: string | URL | Request, init: RequestInit = {}) => {
			const call = { url: String(input), init };
			context.fetched.push(call);
			return context.respond(call);
		}) as typeof fetch,
		// Every name resolves to a public address unless it says otherwise
		resolveHost: async (hostname) => (hostname.includes("internal-") ? ["10.0.0.5"] : ["93.184.216.34"]),
	});
	const app = buildApp(runtime.services);
	await app.ready();
	const ctx: TestContext = Object.assign(context, {
		app,
		services: runtime.services,
		runtime,
		storage,
		async close() {
			await app.close();
			await runtime.close();
		},
	});
	return ctx;
}

export interface Response_ {
	status: number;
	body: any;
	headers: Record<string, unknown>;
}

export interface Caller {
	token?: string;
	bot?: string;
}

/** Calls the API like a client: JSON in, JSON out, ids as strings. */
export async function call(ctx: TestContext, method: string, path: string, body?: unknown, as: Caller = {}): Promise<Response_> {
	const headers: Record<string, string> = {};
	if (as.token) headers.authorization = `Bearer ${as.token}`;
	if (as.bot) headers.authorization = `Bot ${as.bot}`;
	const response = await ctx.app.inject({
		method: method as "GET",
		url: path.startsWith("/health") ? path : `/api/v1${path}`,
		headers,
		...(body === undefined ? {} : { payload: body as object }),
	});
	const text = response.body;
	return { status: response.statusCode, body: text ? safeJson(text) : null, headers: response.headers };
}

function safeJson(text: string) {
	try {
		return JSON.parse(text);
	} catch {
		return text;
	}
}

export interface TestUser {
	id: string;
	username: string;
	token: string;
	as: Caller;
}

let counter = 0;
export async function register(ctx: TestContext, name?: string): Promise<TestUser> {
	const username = name ?? `user${process.pid}_${++counter}`;
	const response = await call(ctx, "POST", "/auth/register", { username, password: "correct horse battery" });
	if (response.status !== 201) throw new Error(`register ${username}: ${response.status} ${JSON.stringify(response.body)}`);
	return { id: response.body.user.id, username, token: response.body.token, as: { token: response.body.token } };
}

/** A workspace owned by `owner`, with its general channel. */
export async function workspaceWith(ctx: TestContext, owner: TestUser, ...members: TestUser[]) {
	const created = await call(ctx, "POST", "/workspaces", { name: "Studio team" }, owner.as);
	if (created.status !== 201) throw new Error(JSON.stringify(created.body));
	const workspaceId: string = created.body.workspace.id;
	const channels = await call(ctx, "GET", `/workspaces/${workspaceId}/channels`, undefined, owner.as);
	const general = channels.body.channels.find((c: { name: string }) => c.name === "general");
	if (members.length > 0) {
		const invite = await call(ctx, "POST", `/workspaces/${workspaceId}/invites`, {}, owner.as);
		for (const member of members) {
			const joined = await call(ctx, "POST", `/invites/${invite.body.invite.code}`, undefined, member.as);
			if (joined.status !== 200) throw new Error(JSON.stringify(joined.body));
		}
	}
	return { workspaceId, generalId: general.id as string };
}

export async function send(ctx: TestContext, user: TestUser | Caller, channelId: string, content: string, extra: object = {}) {
	const as = "as" in user ? user.as : user;
	const response = await call(ctx, "POST", `/channels/${channelId}/messages`, { content, ...extra }, as);
	if (response.status !== 201) throw new Error(`send: ${response.status} ${JSON.stringify(response.body)}`);
	return response.body.message;
}
