import { sql } from "drizzle-orm";
import { drizzle, type NodePgDatabase } from "drizzle-orm/node-postgres";
import pg from "pg";
import * as schema from "./schema.js";

export type Database = NodePgDatabase<typeof schema>;
/** A database handle or an open transaction: services accept either. */
export type Tx = Parameters<Parameters<Database["transaction"]>[0]>[0] | Database;

export interface DatabaseHandle {
	db: Database;
	pool: pg.Pool;
	close(): Promise<void>;
}

export function connectDatabase(options: {
	url: string;
	poolMax?: number;
	statementTimeoutMs?: number;
	onError?: (error: Error) => void;
}): DatabaseHandle {
	const pool = new pg.Pool({
		connectionString: options.url,
		max: options.poolMax ?? 20,
		idleTimeoutMillis: 30_000,
		connectionTimeoutMillis: 5_000,
		statement_timeout: options.statementTimeoutMs ?? 10_000,
		application_name: "teamchat-backend",
	});
	// An idle client losing its connection must not crash the process; the pool replaces it
	pool.on("error", (error) => options.onError?.(error));
	const db = drizzle(pool, { schema, casing: "snake_case" });
	return { db, pool, close: () => pool.end() };
}

export async function databaseHealthy(db: Database, timeoutMs = 2_000): Promise<boolean> {
	let timer: NodeJS.Timeout | undefined;
	try {
		await Promise.race([
			db.execute(sql`select 1`),
			new Promise((_, reject) => {
				timer = setTimeout(() => reject(new Error("timeout")), timeoutMs);
			}),
		]);
		return true;
	} catch {
		return false;
	} finally {
		clearTimeout(timer);
	}
}

const CONNECTION_CODES = new Set([
	"ECONNREFUSED",
	"ECONNRESET",
	"ETIMEDOUT",
	"EPIPE",
	"ENOTFOUND",
	"57P01", // admin_shutdown
	"57P02", // crash_shutdown
	"57P03", // cannot_connect_now
	"08000",
	"08001",
	"08003",
	"08004",
	"08006",
	"53300", // too_many_connections
]);

/** True when the database can't be reached, as opposed to a query being wrong. */
export function isConnectionError(error: unknown): boolean {
	let current: unknown = error;
	for (let depth = 0; current && depth < 5; depth++) {
		const e = current as { code?: string; message?: string; cause?: unknown };
		if (e.code && CONNECTION_CODES.has(e.code)) return true;
		if (typeof e.message === "string" && /Connection terminated|timeout exceeded when trying to connect|connect ECONNREFUSED/i.test(e.message)) {
			return true;
		}
		current = e.cause;
	}
	return false;
}

/** The Postgres error code of a failed query (also when drizzle wraps it). */
export function pgCode(error: unknown): string | undefined {
	let current: unknown = error;
	for (let depth = 0; current && depth < 5; depth++) {
		const code = (current as { code?: unknown }).code;
		if (typeof code === "string" && /^[0-9A-Z]{5}$/.test(code)) return code;
		current = (current as { cause?: unknown }).cause;
	}
	return undefined;
}

export const UNIQUE_VIOLATION = "23505";
export const FOREIGN_KEY_VIOLATION = "23503";
