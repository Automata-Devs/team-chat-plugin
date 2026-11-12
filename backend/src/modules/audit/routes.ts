import { and, desc, eq, lt } from "drizzle-orm";
import { z } from "zod";
import { auditLog } from "../../db/schema.js";
import { actorOf, type Module } from "../../http/types.js";
import { Permission } from "../../lib/permissions.js";
import { idParams, limit, parse, snowflake } from "../../lib/validation.js";
import { requireWorkspacePermission } from "../access.js";

const Query = z.object({ before: snowflake.optional(), limit: limit(50, 100), action: z.string().max(64).optional() });

export const auditModule: Module = (app, services) => {
	app.get("/workspaces/:workspaceId/audit-log", async (request) => {
		const { workspaceId } = parse(idParams("workspaceId"), request.params);
		const query = parse(Query, request.query);
		await requireWorkspacePermission(services.db, workspaceId, actorOf(request).userId, Permission.VIEW_AUDIT_LOG);
		const entries = await services.db
			.select()
			.from(auditLog)
			.where(
				and(
					eq(auditLog.workspaceId, workspaceId),
					query.before ? lt(auditLog.id, query.before) : undefined,
					query.action ? eq(auditLog.action, query.action) : undefined,
				),
			)
			.orderBy(desc(auditLog.id))
			.limit(query.limit);
		return { entries: entries.map(({ ip: _ip, ...entry }) => entry) };
	});

	/** Your own account's security history: sign-ins, password changes, sessions. */
	app.get("/users/@me/audit-log", async (request) => {
		const query = parse(Query, request.query);
		const entries = await services.db
			.select()
			.from(auditLog)
			.where(and(eq(auditLog.actorId, actorOf(request).userId), query.before ? lt(auditLog.id, query.before) : undefined))
			.orderBy(desc(auditLog.id))
			.limit(query.limit);
		return { entries };
	});
};
