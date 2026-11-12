/**
 * Snowflake IDs, as Discord uses them: 64 bits that sort by creation time.
 *
 *   42 bits  milliseconds since EPOCH (about 139 years)
 *   10 bits  worker id (0-1023), unique per running instance
 *   12 bits  sequence within the same millisecond (4096 per ms per worker)
 *
 * The top bit stays 0, so every ID fits a signed bigint column.
 */

export const EPOCH = 1_704_067_200_000n; // 2024-01-01T00:00:00Z

const WORKER_BITS = 10n;
const SEQUENCE_BITS = 12n;
const MAX_SEQUENCE = (1n << SEQUENCE_BITS) - 1n;
const MAX_WORKER = (1n << WORKER_BITS) - 1n;

export class SnowflakeGenerator {
	private readonly worker: bigint;
	private lastMs = -1n;
	private sequence = 0n;

	constructor(
		workerId: number,
		private readonly now: () => number = Date.now,
	) {
		const worker = BigInt(workerId);
		if (worker < 0n || worker > MAX_WORKER) throw new RangeError(`Worker id must be 0-${MAX_WORKER}`);
		this.worker = worker;
	}

	next(): bigint {
		let ms = BigInt(this.now());
		// A clock that steps back keeps using the last time, so IDs never go backwards
		if (ms < this.lastMs) ms = this.lastMs;
		if (ms === this.lastMs) {
			this.sequence = (this.sequence + 1n) & MAX_SEQUENCE;
			// 4096 IDs in this millisecond: borrow the next one
			if (this.sequence === 0n) ms = this.lastMs + 1n;
		} else {
			this.sequence = 0n;
		}
		this.lastMs = ms;
		return ((ms - EPOCH) << (WORKER_BITS + SEQUENCE_BITS)) | (this.worker << SEQUENCE_BITS) | this.sequence;
	}
}

export function timestampOf(id: bigint): Date {
	return new Date(Number((id >> (WORKER_BITS + SEQUENCE_BITS)) + EPOCH));
}

export function workerOf(id: bigint): number {
	return Number((id >> SEQUENCE_BITS) & MAX_WORKER);
}

/** The smallest ID that could have been made at `date`: for "after/before this time" queries. */
export function snowflakeAt(date: Date): bigint {
	const ms = BigInt(date.getTime()) - EPOCH;
	return ms <= 0n ? 0n : ms << (WORKER_BITS + SEQUENCE_BITS);
}
