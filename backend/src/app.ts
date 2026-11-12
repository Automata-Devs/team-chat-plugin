import Fastify, { type FastifyInstance } from "fastify";
import secureJson from "secure-json-parse";
import type { Services } from "./context.js";
import { isConnectionError, pgCode, UNIQUE_VIOLATION } from "./db/client.js";
import { authenticate } from "./http/auth.js";
import { hit, LIMITS } from "./http/rateLimit.js";
import "./http/types.js";
import { AppError } from "./lib/errors.js";
import { attachmentsModule } from "./modules/attachments/routes.js";
import { auditModule } from "./modules/audit/routes.js";
import { authModule } from "./modules/auth/routes.js";
import { botsModule } from "./modules/bots/routes.js";
import { channelsModule } from "./modules/channels/routes.js";
import { conversationsModule } from "./modules/conversations/routes.js";
import { gatewayModule } from "./modules/gateway/routes.js";
import { healthModule } from "./modules/health/routes.js";
import { messagesModule } from "./modules/messages/routes.js";
import { notificationsModule } from "./modules/notifications/routes.js";
import { reactionsModule } from "./modules/reactions/routes.js";
import { searchModule } from "./modules/search/routes.js";
import { settingsModule } from "./modules/settings/routes.js";
import { usersModule } from "./modules/users/routes.js";
import { workspacesModule } from "./modules/workspaces/routes.js";

export const API_PREFIX = "/api/v1";

const modules = [
	authModule,
	usersModule,
	settingsModule,
	workspacesModule,
	channelsModule,
	conversationsModule,
	messagesModule,
	reactionsModule,
	attachmentsModule,
	searchModule,
	notificationsModule,
	botsModule,
	auditModule,
	gatewayModule,
];

/** JSON with 64-bit ids as strings: JavaScript and Luau numbers can't hold them exactly. */
export const toJson = (value: unknown) =>
	JSON.stringify(value, (_key, v) => (typeof v === "bigint" ? v.toString() : v));

export function buildApp(services: Services): FastifyInstance {
	const app = Fastify({
		loggerInstance: services.log,
		trustProxy: services.config.TRUST_PROXY,
		bodyLimit: 256 * 1024,
		genReqId: () => services.ids.next().toString(36),
	});

	app.decorateRequest("actor", null);
	// Like Fastify's own JSON parser (no __proto__ tricks), but an empty body is no body:
	// HttpService sends Content-Type: application/json on body-less POSTs too
	app.removeContentTypeParser("application/json");
	app.addContentTypeParser("application/json", { parseAs: "string" }, (_request, body, done) => {
		if (body === "") return done(null, undefined);
		try {
			done(null, secureJson.parse(body as string, undefined, { protoAction: "error", constructorAction: "error" }));
		} catch {
			done(Object.assign(new Error("Body is not valid JSON"), { statusCode: 400 }), undefined);
		}
	});
	app.setReplySerializer((payload) => toJson(payload));

	app.addHook("onRequest", async (request, reply) => {
		// Unknown paths answer 404 before anything else
		if (!request.routeOptions.url) return;
		const config = request.routeOptions.config ?? {};
		const auth = config.auth ?? "user";
		request.actor = await authenticate(services, request);
		if (request.actor) request.log = request.log.child({ actor: `${request.actor.kind}:${request.actor.userId}` });

		if (auth !== "none" && !request.actor) throw new AppError(401, "unauthorized", "Sign in first");
		if (auth === "user" && request.actor?.kind === "bot") throw new AppError(403, "forbidden", "Bots can't use this endpoint");

		const subject = request.actor ? String(request.actor.userId) : request.ip;
		const global = !request.actor ? LIMITS.anonymous : request.actor.kind === "bot" ? LIMITS.bot : LIMITS.user;
		const scale = services.config.RATE_LIMIT_SCALE;
		if (!request.url.startsWith("/health")) await hit(services.cache, global, subject, reply, scale);
		if (config.limit) await hit(services.cache, config.limit, subject, reply, scale);
	});

	app.setErrorHandler((error, request, reply) => {
		if (error instanceof AppError) {
			if (error.code === "unavailable") request.log.warn(error.message);
			else if (error.status >= 500) request.log.error({ err: error }, error.message);
			return reply.status(error.status).send({ error: { code: error.code, message: error.message, details: error.details } });
		}
		const fastifyError = error as { statusCode?: number; code?: string; message: string };
		if (fastifyError.statusCode && fastifyError.statusCode < 500) {
			const code = fastifyError.statusCode === 413 ? "too_large" : "bad_request";
			return reply.status(fastifyError.statusCode).send({ error: { code, message: fastifyError.message } });
		}
		if (isConnectionError(error)) {
			request.log.error({ err: error }, "Database unreachable");
			return reply
				.status(503)
				.header("Retry-After", 5)
				.send({ error: { code: "unavailable", message: "The database is unreachable, try again shortly" } });
		}
		if (pgCode(error) === UNIQUE_VIOLATION) {
			return reply.status(409).send({ error: { code: "conflict", message: "That already exists" } });
		}
		request.log.error({ err: error }, "Unhandled error");
		return reply.status(500).send({ error: { code: "internal", message: "Something went wrong" } });
	});

	app.setNotFoundHandler((_request, reply) =>
		reply.status(404).send({ error: { code: "not_found", message: "No such endpoint" } }),
	);

	app.register(async (health) => healthModule(health, services));
	app.register(
		async (api) => {
			for (const register of modules) register(api, services);
		},
		{ prefix: API_PREFIX },
	);
	return app;
}
