import { and, desc, eq, gt, isNull, sql } from "drizzle-orm";
import { z } from "zod";
import { sessions } from "../../db/schema.js";
import { LIMITS } from "../../http/rateLimit.js";
import { actorOf, type Module } from "../../http/types.js";
import { AppError, forbidden, notFound } from "../../lib/errors.js";
import { idParams, name, parse, username } from "../../lib/validation.js";
import { pageCsp, resultPage } from "./pages.js";
import { finishRobloxLogin, pollRobloxLogin, startRobloxLogin } from "./roblox.js";
import { changePassword, connectedAccountsOf, login, register, revokeSession } from "./service.js";

const password = z.string().min(10, "At least 10 characters").max(256);

const Register = z.object({ username, password, displayName: name(64).optional() });
const Login = z.object({ username: z.string().min(1).max(64), password: z.string().min(1).max(256) });
const ChangePassword = z.object({ currentPassword: z.string().max(256).optional(), newPassword: password });
const Poll = z.object({ loginId: z.string().min(10).max(64), pollSecret: z.string().min(10).max(128) });
const Callback = z.object({
	code: z.string().min(1).max(2048).optional(),
	state: z.string().min(1).max(256),
	error: z.string().max(256).optional(),
});

const failed = (message: string) =>
	resultPage({ ok: false, title: "Sign-in didn't work", message, next: "Start again in Roblox Studio: type /backend login in Team Chat." });

export const authModule: Module = (app, services) => {
	app.post("/auth/register", { config: { auth: "none", limit: LIMITS.signup } }, async (request, reply) => {
		if (!services.config.ALLOW_PASSWORD_SIGNUP) throw forbidden("Sign-up with a password is turned off; sign in with Roblox");
		return reply.status(201).send(await register(services, request, parse(Register, request.body)));
	});

	app.post("/auth/login", { config: { auth: "none", limit: LIMITS.auth } }, async (request) =>
		login(services, request, parse(Login, request.body)),
	);

	app.post("/auth/logout", async (request, reply) => {
		const actor = actorOf(request);
		if (actor.sessionId) await revokeSession(services, request, actor.userId, actor.sessionId);
		return reply.status(204).send();
	});

	app.get("/auth/sessions", async (request) => {
		const actor = actorOf(request);
		const rows = await services.db
			.select({
				id: sessions.id,
				createdAt: sessions.createdAt,
				lastUsedAt: sessions.lastUsedAt,
				expiresAt: sessions.expiresAt,
				ip: sessions.ip,
				userAgent: sessions.userAgent,
			})
			.from(sessions)
			.where(and(eq(sessions.userId, actor.userId), isNull(sessions.revokedAt), gt(sessions.expiresAt, sql`now()`)))
			.orderBy(desc(sessions.id))
			.limit(100);
		return { sessions: rows.map((row) => ({ ...row, current: row.id === actor.sessionId })) };
	});

	app.delete("/auth/sessions/:sessionId", async (request, reply) => {
		const { sessionId } = parse(idParams("sessionId"), request.params);
		if (!(await revokeSession(services, request, actorOf(request).userId, sessionId))) throw notFound("Session");
		return reply.status(204).send();
	});

	app.post("/auth/password", { config: { limit: LIMITS.auth } }, async (request, reply) => {
		const actor = actorOf(request);
		await changePassword(services, request, actor.userId, actor.sessionId, parse(ChangePassword, request.body));
		return reply.status(204).send();
	});

	app.get("/auth/connections", async (request) => ({ connections: await connectedAccountsOf(services, actorOf(request).userId) }));

	// Signed in already, this links Roblox to the current account instead of signing in
	app.post("/auth/roblox/start", { config: { auth: "none", limit: LIMITS.auth } }, async (request) => {
		if (request.actor?.kind === "bot") throw forbidden("Bots can't sign in with Roblox");
		return startRobloxLogin(services, request.actor?.userId);
	});

	app.get("/auth/roblox/callback", { config: { auth: "none", limit: LIMITS.auth } }, async (request, reply) => {
		reply.type("text/html; charset=utf-8").header("Content-Security-Policy", pageCsp()).header("Cache-Control", "no-store");
		// A person lands here in a browser: answer with a page, never raw JSON
		const parsed = Callback.safeParse(request.query);
		if (!parsed.success) return reply.status(400).send(failed("This sign-in link is incomplete or was changed."));
		const query = parsed.data;
		if (query.error || !query.code) return reply.status(400).send(failed("Sign-in was cancelled on Roblox."));
		try {
			const done = await finishRobloxLogin(services, request, query.code, query.state);
			return reply.send(
				done === "linked"
					? resultPage({ ok: true, title: "Roblox account linked", message: "You can close this tab." })
					: resultPage({
							ok: true,
							title: "You're signed in",
							message: "Go back to Roblox Studio: Team Chat stores this place's chat from now on. You can close this tab.",
						}),
			);
		} catch (error) {
			const status = error instanceof AppError ? error.status : 500;
			if (status >= 500) request.log.error({ err: error }, "Roblox sign-in failed");
			const message = error instanceof AppError && status < 500 ? error.message : "Sign-in failed. Try again from Studio.";
			return reply.status(status).send(failed(message));
		}
	});

	app.post("/auth/roblox/poll", { config: { auth: "none" } }, async (request, reply) => {
		const body = parse(Poll, request.body);
		const result = await pollRobloxLogin(services, body.loginId, body.pollSecret);
		return reply.status(result.status === "pending" ? 202 : 200).send(result);
	});
};
