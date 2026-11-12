import { z } from "zod";

/**
 * User settings. Only what a user changes is stored (user_settings.settings);
 * everything else comes from these defaults, so new settings need no migration.
 */
export const SettingsSchema = z
	.object({
		notifications: z
			.object({
				desktop: z.boolean(),
				sound: z.boolean(),
				/** For channels without their own level. */
				defaultLevel: z.enum(["all", "mentions", "none"]),
				directMessages: z.boolean(),
				mentions: z.boolean(),
				replies: z.boolean(),
				everyone: z.boolean(),
			})
			.strict(),
		appearance: z
			.object({
				theme: z.enum(["dark", "light", "system"]),
				compact: z.boolean(),
				fontScale: z.number().min(0.75).max(1.5),
				showAvatars: z.boolean(),
			})
			.strict(),
		messages: z
			.object({
				showEmbeds: z.boolean(),
				showReactions: z.boolean(),
				groupMessages: z.boolean(),
				timestampFormat: z.enum(["relative", "12h", "24h"]),
			})
			.strict(),
		privacy: z
			.object({
				allowDirectMessages: z.enum(["everyone", "workspace_members", "none"]),
				showActivity: z.boolean(),
			})
			.strict(),
		/** BCP 47, e.g. "en", "nl", "pt-BR". */
		language: z.string().regex(/^[a-z]{2,3}(-[A-Z]{2})?$/),
		accessibility: z
			.object({
				reducedMotion: z.boolean(),
				highContrast: z.boolean(),
				screenReaderHints: z.boolean(),
			})
			.strict(),
		account: z
			.object({
				timezone: z.string().max(64),
				developerMode: z.boolean(),
			})
			.strict(),
	})
	.strict();

export type Settings = z.infer<typeof SettingsSchema>;

export const DEFAULT_SETTINGS: Settings = {
	notifications: {
		desktop: true,
		sound: true,
		defaultLevel: "mentions",
		directMessages: true,
		mentions: true,
		replies: true,
		everyone: true,
	},
	appearance: { theme: "dark", compact: false, fontScale: 1, showAvatars: true },
	messages: { showEmbeds: true, showReactions: true, groupMessages: true, timestampFormat: "relative" },
	privacy: { allowDirectMessages: "everyone", showActivity: true },
	language: "en",
	accessibility: { reducedMotion: false, highContrast: false, screenReaderHints: false },
	account: { timezone: "UTC", developerMode: false },
};

export type DeepPatch<T> = { [K in keyof T]?: (T[K] extends object ? DeepPatch<T[K]> : T[K]) | null };

/** The same shape with every field optional, and null meaning "back to the default". */
function patchOf(schema: z.ZodTypeAny): z.ZodTypeAny {
	if (schema instanceof z.ZodObject) {
		const shape = Object.fromEntries(
			Object.entries(schema.shape as Record<string, z.ZodTypeAny>).map(([key, value]) => [
				key,
				patchOf(value).nullable().optional(),
			]),
		);
		return z.object(shape).strict();
	}
	return schema;
}

export const SettingsPatch = patchOf(SettingsSchema) as z.ZodType<DeepPatch<Settings>>;

type Plain = Record<string, unknown>;
const isPlain = (value: unknown): value is Plain => typeof value === "object" && value !== null && !Array.isArray(value);

/** Applies a patch to stored overrides: values are set, null removes one (back to the default). */
export function applyPatch(overrides: Plain, patch: Plain): Plain {
	const result: Plain = { ...overrides };
	for (const [key, value] of Object.entries(patch)) {
		if (value === null) {
			delete result[key];
		} else if (isPlain(value)) {
			const merged = applyPatch(isPlain(result[key]) ? (result[key] as Plain) : {}, value);
			if (Object.keys(merged).length === 0) delete result[key];
			else result[key] = merged;
		} else {
			result[key] = value;
		}
	}
	return result;
}

/** The defaults with a user's overrides on top. Overrides for settings that no longer exist are ignored. */
export function withDefaults(overrides: unknown): Settings {
	const merge = (base: Plain, over: unknown): Plain => {
		if (!isPlain(over)) return base;
		const out: Plain = { ...base };
		for (const [key, value] of Object.entries(over)) {
			if (!(key in base)) continue;
			out[key] = isPlain(base[key]) ? merge(base[key] as Plain, value) : value;
		}
		return out;
	};
	const merged = merge(DEFAULT_SETTINGS as unknown as Plain, overrides);
	const checked = SettingsSchema.safeParse(merged);
	return checked.success ? checked.data : DEFAULT_SETTINGS;
}
