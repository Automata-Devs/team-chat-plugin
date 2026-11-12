import { sql } from "drizzle-orm";
import type { Database, Tx } from "../db/client.js";
import { jobs } from "../db/schema.js";

/**
 * Background jobs in Postgres. enqueue() runs in the caller's transaction,
 * so a job exists exactly when the change it follows was committed. Workers on
 * any number of instances claim jobs with FOR UPDATE SKIP LOCKED.
 */
export type JobHandler = (payload: any, job: { id: bigint; attempts: number }) => Promise<void>;

export interface EnqueueOptions {
	delaySeconds?: number;
	maxAttempts?: number;
	/** Skip if a job with this key is still waiting. */
	dedupeKey?: string;
}

export async function enqueue(tx: Tx, type: string, payload: object, options: EnqueueOptions = {}): Promise<void> {
	const json = JSON.parse(JSON.stringify(payload, (_k, v) => (typeof v === "bigint" ? v.toString() : v)));
	await tx
		.insert(jobs)
		.values({
			type,
			payload: json,
			runAt: new Date(Date.now() + (options.delaySeconds ?? 0) * 1000),
			maxAttempts: options.maxAttempts ?? 5,
			dedupeKey: options.dedupeKey,
		})
		.onConflictDoNothing({ target: jobs.dedupeKey });
}

const LOCK_SECONDS = 120;

export class JobRunner {
	private readonly handlers = new Map<string, JobHandler>();
	private timer: NodeJS.Timeout | undefined;
	private running: Promise<number> | undefined;
	private stopped = false;

	constructor(
		private readonly db: Database,
		private readonly log: { error(obj: object, msg: string): void; warn(obj: object, msg: string): void },
	) {}

	register(type: string, handler: JobHandler): this {
		this.handlers.set(type, handler);
		return this;
	}

	/** Claims and runs one batch; returns how many ran. Tests call this directly. */
	async runOnce(batch = 20): Promise<number> {
		const result = await this.db.execute<{ id: string; type: string; payload: unknown; attempts: number; max_attempts: number }>(sql`
			update jobs set locked_until = now() + make_interval(secs => ${LOCK_SECONDS}), attempts = attempts + 1
			where id in (
				select id from jobs
				where run_at <= now() and attempts < max_attempts
				  and (locked_until is null or locked_until < now())
				order by run_at
				limit ${batch}
				for update skip locked
			)
			returning id, type, payload, attempts, max_attempts`);

		for (const row of result.rows) {
			const id = BigInt(row.id);
			const handler = this.handlers.get(row.type);
			try {
				if (!handler) throw new Error(`No handler for job type ${row.type}`);
				await handler(row.payload, { id, attempts: row.attempts });
				await this.db.execute(sql`delete from jobs where id = ${id}`);
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				const backoff = Math.min(3600, 2 ** row.attempts * 5);
				await this.db.execute(sql`
					update jobs set locked_until = null, last_error = ${message.slice(0, 2000)},
						run_at = now() + make_interval(secs => ${backoff})
					where id = ${id}`);
				const level = row.attempts >= row.max_attempts ? "error" : "warn";
				this.log[level]({ err: error, job: row.type, id: row.id, attempt: row.attempts }, "Job failed");
			}
		}
		return result.rows.length;
	}

	/** Runs everything that's ready now, including jobs those jobs enqueue. */
	async drain(maxRounds = 50): Promise<void> {
		for (let round = 0; round < maxRounds; round++) {
			if ((await this.runOnce()) === 0) return;
		}
	}

	start(intervalMs = 1000): void {
		this.stopped = false;
		const tick = async () => {
			if (this.stopped) return;
			try {
				this.running = this.runOnce();
				const ran = await this.running;
				this.timer = setTimeout(tick, ran > 0 ? 0 : intervalMs);
			} catch (error) {
				this.log.error({ err: error }, "Job worker tick failed");
				this.timer = setTimeout(tick, intervalMs * 5);
			}
		};
		this.timer = setTimeout(tick, intervalMs);
	}

	async stop(): Promise<void> {
		this.stopped = true;
		clearTimeout(this.timer);
		await this.running?.catch(() => undefined);
	}
}
