import { inArray } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import type { Services } from "../context.js";
import type { Tx } from "../db/client.js";
import { auditLog, users } from "../db/schema.js";

export type UserRow = typeof users.$inferSelect;

/** What anyone may see about a user. */
export function publicUser(user: UserRow) {
	const deleted = user.status === "deleted";
	return {
		id: user.id,
		username: deleted ? "deleted-user" : user.username,
		displayName: deleted ? "Deleted User" : user.displayName,
		avatarUrl: deleted ? null : user.avatarUrl,
		isBot: user.isBot,
		createdAt: user.createdAt,
	};
}

export type PublicUser = ReturnType<typeof publicUser>;

/** Loads users by id in one query (no N+1). */
export async function usersById(tx: Tx, ids: Iterable<bigint>): Promise<Map<bigint, PublicUser>> {
	const unique = [...new Set(ids)];
	if (unique.length === 0) return new Map();
	const rows = await tx.select().from(users).where(inArray(users.id, unique));
	return new Map(rows.map((row) => [row.id, publicUser(row)]));
}

export interface AuditEntry {
	action: string;
	actorId?: bigint | null;
	workspaceId?: bigint | null;
	targetType?: string;
	targetId?: bigint | string;
	data?: Record<string, unknown>;
}

/** Records a security-relevant action. Runs in the caller's transaction, so it's kept only if the action is. */
export async function audit(services: Services, tx: Tx, request: FastifyRequest | null, entry: AuditEntry): Promise<void> {
	const data = JSON.parse(JSON.stringify(entry.data ?? {}, (_k, v) => (typeof v === "bigint" ? v.toString() : v)));
	await tx.insert(auditLog).values({
		id: services.ids.next(),
		action: entry.action,
		actorId: entry.actorId ?? null,
		workspaceId: entry.workspaceId ?? null,
		targetType: entry.targetType,
		targetId: entry.targetId === undefined ? undefined : String(entry.targetId),
		data,
		ip: request?.ip,
	});
}

/** Publishes after the transaction committed; a failed publish never fails the request. */
export function publish(services: Services, topic: string, type: string, data: unknown): void {
	services.events.publish(topic, { type, data }).catch((error) => services.log.warn({ err: error, topic, type }, "Publish failed"));
}
