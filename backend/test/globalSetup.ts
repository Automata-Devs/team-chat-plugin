/**
 * Starts one real PostgreSQL for the whole run (embedded-postgres: the actual
 * server binaries, no Docker) and migrates a template database. Each test file
 * then copies the template, so files run in parallel without sharing data.
 */
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import EmbeddedPostgres from "embedded-postgres";
import type { TestProject } from "vitest/node";
import { connectDatabase } from "../src/db/client.js";
import { runMigrations } from "../src/db/migrate.js";

declare module "vitest" {
	export interface ProvidedContext {
		pgAdminUrl: string;
		pgBaseUrl: string;
	}
}

export default async function setup(project: TestProject) {
	const dir = mkdtempSync(path.join(tmpdir(), "teamchat-pg-"));
	const port = 54_000 + Math.floor(Math.random() * 900);
	const pg = new EmbeddedPostgres({ databaseDir: dir, user: "postgres", password: "postgres", port, persistent: false, initdbFlags: ["--encoding=UTF8", "--locale=C"], postgresFlags: ["-c", "io_method=sync"], onLog: () => {} });
	await pg.initialise();
	await pg.start();
	await pg.createDatabase("teamchat_template");

	const base = `postgres://postgres:postgres@127.0.0.1:${port}`;
	const handle = connectDatabase({ url: `${base}/teamchat_template`, poolMax: 1 });
	await runMigrations(handle.db);
	await handle.close();

	project.provide("pgAdminUrl", `${base}/postgres`);
	project.provide("pgBaseUrl", base);

	return async () => {
		await pg.stop();
		rmSync(dir, { recursive: true, force: true });
	};
}
