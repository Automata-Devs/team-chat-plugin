import { z } from "zod";
import { httpsUrl, name, snowflake, text } from "../../lib/validation.js";

export const MessageFlags = {
	SUPPRESS_EMBEDS: 1 << 2,
	SUPPRESS_NOTIFICATIONS: 1 << 12,
} as const;
const CLIENT_FLAGS = MessageFlags.SUPPRESS_EMBEDS | MessageFlags.SUPPRESS_NOTIFICATIONS;

export const MAX_CONTENT = 4000;
const MAX_EMBED_CHARACTERS = 6000;

export const Embed = z
	.object({
		title: text(256).optional(),
		description: text(4096).optional(),
		url: httpsUrl.optional(),
		color: z.number().int().min(0).max(0xffffff).optional(),
		timestamp: z.string().datetime().optional(),
		author: z.object({ name: name(256), url: httpsUrl.optional(), iconUrl: httpsUrl.optional() }).strict().optional(),
		footer: z.object({ text: text(2048, 1), iconUrl: httpsUrl.optional() }).strict().optional(),
		image: z.object({ url: httpsUrl }).strict().optional(),
		thumbnail: z.object({ url: httpsUrl }).strict().optional(),
		fields: z
			.array(z.object({ name: text(256, 1), value: text(1024, 1), inline: z.boolean().optional() }).strict())
			.max(25)
			.optional(),
	})
	.strict();

const Button = z
	.object({
		type: z.literal("button"),
		style: z.enum(["primary", "secondary", "success", "danger", "link"]),
		label: name(80),
		customId: z.string().min(1).max(100).optional(),
		url: httpsUrl.optional(),
		disabled: z.boolean().optional(),
	})
	.strict()
	.refine((b) => (b.style === "link" ? !!b.url && !b.customId : !!b.customId && !b.url), "Link buttons need a url, others a customId");

/** Interactive parts: only bots may send them. */
export const Components = z
	.array(z.object({ type: z.literal("row"), components: z.array(Button).min(1).max(5) }).strict())
	.max(5);

type EmbedInput = z.infer<typeof Embed>;
const embedCharacters = (embeds: EmbedInput[]) =>
	embeds.reduce(
		(sum, e) =>
			sum +
			(e.title?.length ?? 0) +
			(e.description?.length ?? 0) +
			(e.footer?.text.length ?? 0) +
			(e.author?.name.length ?? 0) +
			(e.fields ?? []).reduce((s, f) => s + f.name.length + f.value.length, 0),
		0,
	);

/**
 * What the sending client wants to remember about a message (the plugin's own
 * fields: its sender name, Studio timestamp, poll, file). Display data only:
 * the author, id and time that count are the server's.
 */
export const ClientData = z
	.record(z.unknown())
	.refine((value) => JSON.stringify(value).length <= 8192, "clientData is at most 8 KB");

const clientFlags = z
	.number()
	.int()
	.refine((f) => (f & ~CLIENT_FLAGS) === 0, "Unknown flags");

export const CreateMessage = z
	.object({
		content: text(MAX_CONTENT).default(""),
		replyTo: snowflake.optional(),
		attachments: z.array(snowflake).max(10).default([]),
		embeds: z.array(Embed).max(10).default([]),
		components: Components.default([]),
		flags: clientFlags.default(0),
		/** Retry key: sending the same nonce again returns the first message instead of a copy. */
		nonce: z.string().min(1).max(64).optional(),
		/** A bot answering a command it received. */
		interactionId: z.string().max(64).optional(),
		clientData: ClientData.optional(),
	})
	.strict()
	.refine((m) => m.content.length > 0 || m.attachments.length > 0 || m.embeds.length > 0, "A message needs text, a file or an embed")
	.refine((m) => embedCharacters(m.embeds) <= MAX_EMBED_CHARACTERS, "Embeds are too long");

export const EditMessage = z
	.object({
		content: text(MAX_CONTENT).optional(),
		embeds: z.array(Embed).max(10).optional(),
		components: Components.optional(),
		flags: clientFlags.optional(),
		clientData: ClientData.optional(),
	})
	.strict()
	.refine((m) => !m.embeds || embedCharacters(m.embeds) <= MAX_EMBED_CHARACTERS, "Embeds are too long");

/** Up to 50 of the sender's own messages at once (mirroring and imports), each with a nonce. */
export const BatchMessages = z
	.object({
		messages: z
			.array(
				z
					.object({
						content: text(MAX_CONTENT).default(""),
						nonce: z.string().min(1).max(64),
						flags: clientFlags.default(0),
						clientData: ClientData.optional(),
					})
					.strict()
					.refine((m) => m.content.length > 0 || m.clientData !== undefined, "A message needs text or clientData"),
			)
			.min(1)
			.max(50),
	})
	.strict()
	.refine((b) => new Set(b.messages.map((m) => m.nonce)).size === b.messages.length, "Nonces must be unique");

export const ListMessages = z
	.object({
		before: snowflake.optional(),
		after: snowflake.optional(),
		around: snowflake.optional(),
		limit: z.coerce.number().int().min(1).max(100).default(50),
	})
	.refine((q) => [q.before, q.after, q.around].filter((v) => v !== undefined).length <= 1, "Use one of before, after, around");

const MENTION = /<@!?([0-9]{1,19})>/g;

/** User ids mentioned as <@id> (at most 50) and whether @everyone / @here is used. */
export function parseMentions(content: string): { users: bigint[]; everyone: boolean } {
	const found = new Set<bigint>();
	for (const match of content.matchAll(MENTION)) {
		if (found.size >= 50) break;
		found.add(BigInt(match[1]));
	}
	return { users: [...found], everyone: /(^|\s)@(everyone|here)\b/.test(content) };
}
