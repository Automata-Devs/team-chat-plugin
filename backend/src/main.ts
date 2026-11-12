import { buildApp } from "./app.js";
import { bootstrap } from "./bootstrap.js";
import { loadConfig } from "./config.js";
import { runMigrations } from "./db/migrate.js";
import { schedulePeriodic } from "./jobs.js";

async function main() {
	const config = loadConfig();
	const runtime = await bootstrap(config);
	const { services } = runtime;

	await runMigrations(services.db);
	const app = buildApp(services);

	if (config.RUN_JOBS) {
		await schedulePeriodic(services, "attachments.cleanup");
		await schedulePeriodic(services, "sessions.cleanup");
		services.jobs.start();
	}

	await app.listen({ host: config.HOST, port: config.PORT });

	let stopping = false;
	const stop = async (signal: string) => {
		if (stopping) return;
		stopping = true;
		services.log.info({ signal }, "Shutting down");
		const force = setTimeout(() => process.exit(1), 15_000).unref();
		await app.close(); // stops accepting, waits for open requests
		await runtime.close();
		clearTimeout(force);
		process.exit(0);
	};
	process.on("SIGTERM", () => void stop("SIGTERM"));
	process.on("SIGINT", () => void stop("SIGINT"));
}

main().catch((error) => {
	console.error(error instanceof Error ? error.message : error);
	process.exit(1);
});
