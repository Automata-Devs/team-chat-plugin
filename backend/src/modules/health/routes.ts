import { sql } from "drizzle-orm";
import { databaseHealthy } from "../../db/client.js";
import type { Module } from "../../http/types.js";

export const healthModule: Module = (app, services) => {
	/** The process is up (for restarts). */
	app.get("/health/live", { config: { auth: "none" } }, async () => ({ ok: true }));

	/** It can serve requests (for load balancers): the database and cache answer. */
	app.get("/health/ready", { config: { auth: "none" } }, async (_request, reply) => {
		const [database, cache] = await Promise.all([databaseHealthy(services.db), services.cache.ping()]);
		let jobs: { waiting: number; failed: number } | undefined;
		if (database) {
			const result = await services.db.execute<{ waiting: string; failed: string }>(sql`
				select count(*) filter (where attempts < max_attempts) as waiting,
				       count(*) filter (where attempts >= max_attempts) as failed
				from jobs`);
			const row = result.rows[0];
			jobs = { waiting: Number(row?.waiting ?? 0), failed: Number(row?.failed ?? 0) };
		}
		const ok = database && cache;
		return reply.status(ok ? 200 : 503).send({ ok, database, cache, jobs });
	});
};
