import type { FastifyInstance, FastifyRequest } from "fastify";
import type { Actor, Services } from "../context.js";
import { forbidden, unauthorized } from "../lib/errors.js";
import type { Limit } from "./rateLimit.js";

declare module "fastify" {
	interface FastifyRequest {
		actor: Actor | null;
	}
	interface FastifyContextConfig {
		/** "user" (the default): a signed-in person. "any": a person or a bot. "none": public. */
		auth?: "none" | "user" | "any";
		/** Counted on top of the global limit. */
		limit?: Limit;
	}
}

export type Module = (app: FastifyInstance, services: Services) => void;

/** The caller (routes with auth "user" or "any" always have one). */
export function actorOf(request: FastifyRequest): Actor {
	if (!request.actor) throw unauthorized();
	return request.actor;
}

/** The calling person, refusing bots (for routes that also accept bots but have person-only parts). */
export function personOf(request: FastifyRequest): Actor {
	const actor = actorOf(request);
	if (actor.kind !== "user") throw forbidden("Bots can't do this");
	return actor;
}
