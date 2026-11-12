import { EventEmitter } from "node:events";
import type { Redis } from "ioredis";

/**
 * Real-time events, published after a change is committed. Topics:
 *   channel:<id>    everything that happens in a channel or conversation
 *   user:<id>       one user's own events (notifications, settings, membership)
 *   workspace:<id>  workspace-wide changes (channels, roles, members)
 *
 * The gateway (modules/gateway) streams them to clients; with Redis every
 * instance sees every event, so a client can be connected to any of them.
 */
export interface GatewayEvent {
	type: string;
	data: unknown;
}

export interface EventBus {
	publish(topic: string, event: GatewayEvent): Promise<void>;
	subscribe(topics: string[], handler: (topic: string, event: GatewayEvent) => void): Promise<() => Promise<void>>;
	close(): Promise<void>;
}

const serialize = (event: GatewayEvent) =>
	JSON.stringify(event, (_key, value) => (typeof value === "bigint" ? value.toString() : value));

export class MemoryEventBus implements EventBus {
	private readonly emitter = new EventEmitter().setMaxListeners(0);

	async publish(topic: string, event: GatewayEvent) {
		// Through JSON like Redis, so both behave the same
		this.emitter.emit(topic, topic, JSON.parse(serialize(event)));
	}

	async subscribe(topics: string[], handler: (topic: string, event: GatewayEvent) => void) {
		for (const topic of topics) this.emitter.on(topic, handler);
		return async () => {
			for (const topic of topics) this.emitter.off(topic, handler);
		};
	}

	async close() {
		this.emitter.removeAllListeners();
	}
}

export class RedisEventBus implements EventBus {
	private readonly local = new MemoryEventBus();
	private readonly counts = new Map<string, number>();

	constructor(
		private readonly publisher: Redis,
		private readonly subscriber: Redis,
	) {
		subscriber.on("message", (topic: string, message: string) => {
			try {
				void this.local.publish(topic, JSON.parse(message));
			} catch {
				// A malformed message is dropped
			}
		});
	}

	async publish(topic: string, event: GatewayEvent) {
		await this.publisher.publish(topic, serialize(event));
	}

	async subscribe(topics: string[], handler: (topic: string, event: GatewayEvent) => void) {
		const fresh = topics.filter((topic) => (this.counts.get(topic) ?? 0) === 0);
		for (const topic of topics) this.counts.set(topic, (this.counts.get(topic) ?? 0) + 1);
		if (fresh.length > 0) await this.subscriber.subscribe(...fresh);
		const off = await this.local.subscribe(topics, handler);
		return async () => {
			await off();
			const idle: string[] = [];
			for (const topic of topics) {
				const left = (this.counts.get(topic) ?? 1) - 1;
				if (left <= 0) {
					this.counts.delete(topic);
					idle.push(topic);
				} else {
					this.counts.set(topic, left);
				}
			}
			if (idle.length > 0) await this.subscriber.unsubscribe(...idle).catch(() => undefined);
		};
	}

	async close() {
		await this.local.close();
		await this.subscriber.quit().catch(() => this.subscriber.disconnect());
	}
}
