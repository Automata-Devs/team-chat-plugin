import path from "node:path";
import { fileURLToPath } from "node:url";
import { sql } from "drizzle-orm";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import { connectDatabase, type Database } from "./client.js";

export const MIGRATIONS_FOLDER = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../migrations");

// Any constant: every instance takes the same lock, so only one migrates at a time
const MIGRATION_LOCK = 7_461_120_001;

/** Applies pending migrations. Safe to run from several instances starting at once. */
export async function runMigrations(db: Database, folder = MIGRATIONS_FOLDER): Promise<void> {
	// Messages hold any Unicode (emoji, every script); a WIN1252 or LATIN1 database would reject them
	const [{ encoding }] = (
		await db.execute<{ encoding: string }>(
			sql`select pg_encoding_to_char(encoding) as encoding from pg_database where datname = current_database()`,
		)
	).rows;
	if (encoding !== "UTF8") throw new Error(`The database must use UTF8 encoding, not ${encoding} (CREATE DATABASE ... ENCODING 'UTF8')`);
	await db.transaction(async (tx) => {
		await tx.execute(sql`select pg_advisory_xact_lock(${MIGRATION_LOCK})`);
		await migrate(tx as unknown as Database, { migrationsFolder: folder });
	});
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
	const url = process.env.DATABASE_URL;
	if (!url) {
		console.error("DATABASE_URL is not set");
		process.exit(1);
	}
	const handle = connectDatabase({ url, poolMax: 1 });
	runMigrations(handle.db)
		.then(() => console.log("Migrations are up to date"))
		.catch((error) => {
			console.error(error);
			process.exitCode = 1;
		})
		.finally(() => handle.close());
}
