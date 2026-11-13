/**
 * Places: one workspace per Roblox place, made by whoever opens the place
 * with Team Chat first, so nobody has to set anything up. The place's team
 * chat, DMs and groups all live in it.
 *
 * Joining needs the place's secret, which the plugin keeps in the place
 * (TeamChatData.Backend): only people who can open the place have it, so
 * knowing a place id isn't enough to read its chat.
 *
 * The plugin also makes the place's end-to-end encryption key from that
 * secret, so the secret itself never comes here: the plugin sends a proof of
 * it, sha256(secret) in hex, and the database keeps sha256 of the proof.
 */
import { timingSafeEqual } from "node:crypto";
import { and, eq } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import { z } from "zod";
import type { Actor, Services } from "../../context.js";
import { pgCode, UNIQUE_VIOLATION } from "../../db/client.js";
import { workspaceMembers, workspaces } from "../../db/schema.js";
import { LIMITS } from "../../http/rateLimit.js";
import { personOf, type Module } from "../../http/types.js";
import { sha256 } from "../../lib/crypto.js";
import { AppError, forbidden } from "../../lib/errors.js";
import { name, parse } from "../../lib/validation.js";
import { audit, publish } from "../shared.js";
import { createWorkspace, serializeWorkspace } from "../workspaces/service.js";

const Params = z.object({
	placeKey: z.string().regex(/^(place:[0-9]{1,20}|local:[A-Za-z0-9-]{8,64})$/, "Not a place key"),
});
const Body = z
	.object({ proof: z.string().regex(/^[0-9a-f]{64}$/, "Not a proof"), name: name(100, 2).default("Team Chat") })
	.strict();

function sameProof(given: string, hash: Buffer | null): boolean {
	if (!hash) return false;
	const actual = sha256(given);
	return actual.length === hash.length && timingSafeEqual(actual, hash);
}

async function joinExisting(services: Services, request: FastifyRequest, actor: Actor, placeKey: string, proof: string) {
	const joined = await services.db.transaction(async (tx) => {
		const [workspace] = await tx.select().from(workspaces).where(eq(workspaces.placeKey, placeKey));
		if (!workspace) return null;
		if (workspace.deletedAt) throw new AppError(410, "expired", "This place's workspace was deleted");
		if (!sameProof(proof, workspace.placeSecretHash)) throw forbidden("That isn't this place's secret");
		const added = await tx
			.insert(workspaceMembers)
			.values({ workspaceId: workspace.id, userId: actor.userId })
			.onConflictDoNothing()
			.returning();
		if (added.length > 0) {
			await audit(services, tx, request, {
				action: "member.join",
				actorId: actor.userId,
				workspaceId: workspace.id,
				data: { place: placeKey },
			});
		}
		return { workspace, joined: added.length > 0 };
	});
	if (joined?.joined) {
		publish(services, `workspace:${joined.workspace.id}`, "member.add", { workspaceId: joined.workspace.id, userId: actor.userId });
		publish(services, `user:${actor.userId}`, "workspace.join", { id: joined.workspace.id });
	}
	return joined?.workspace ?? null;
}

export const placesModule: Module = (app, services) => {
	/**
	 * The place's workspace: joins it (with the place's secret), or makes it when
	 * it doesn't exist yet, with its team chat channel. Safe to call every time
	 * the plugin starts, and by several people at once.
	 */
	app.post("/places/:placeKey/workspace", { config: { limit: LIMITS.auth } }, async (request) => {
		const { placeKey } = parse(Params, request.params);
		if (typeof request.body === "object" && request.body !== null && "secret" in request.body) {
			throw new AppError(426, "upgrade_required", "Update Team Chat: this server stores places end-to-end encrypted");
		}
		const body = parse(Body, request.body);
		const actor = personOf(request);

		let workspace = await joinExisting(services, request, actor, placeKey, body.proof);
		let created = false;
		if (!workspace) {
			try {
				await createWorkspace(services, request, actor, { name: body.name }, { key: placeKey, secretHash: sha256(body.proof) });
				created = true;
			} catch (error) {
				// Someone else made it at the same moment: join theirs
				if (pgCode(error) !== UNIQUE_VIOLATION) throw error;
			}
			workspace = await joinExisting(services, request, actor, placeKey, body.proof);
		}
		if (!workspace) throw new AppError(500, "internal", "The place's workspace couldn't be made");
		return { workspace: serializeWorkspace(workspace), teamChatChannelId: workspace.teamChatChannelId, created };
	});
};
