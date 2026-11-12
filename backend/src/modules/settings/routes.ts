import { eq, sql } from "drizzle-orm";
import { userSettings } from "../../db/schema.js";
import { actorOf, personOf, type Module } from "../../http/types.js";
import { badRequest } from "../../lib/errors.js";
import { parse } from "../../lib/validation.js";
import { publish } from "../shared.js";
import { applyPatch, DEFAULT_SETTINGS, SettingsPatch, SettingsSchema, withDefaults } from "./defaults.js";

export const settingsModule: Module = (app, services) => {
	app.get("/users/@me/settings", async (request) => {
		const [row] = await services.db
			.select()
			.from(userSettings)
			.where(eq(userSettings.userId, actorOf(request).userId));
		return { settings: withDefaults(row?.settings), overrides: row?.settings ?? {}, version: row?.version ?? 0 };
	});

	app.get("/settings/defaults", async () => ({ settings: DEFAULT_SETTINGS }));

	/** Deep-merges the body into your settings. A null resets that setting to its default. */
	app.patch("/users/@me/settings", async (request) => {
		const userId = personOf(request).userId;
		const patch = parse(SettingsPatch, request.body);
		const result = await services.db.transaction(async (tx) => {
			// Row lock: two devices saving at once both land, one after the other
			await tx.insert(userSettings).values({ userId }).onConflictDoNothing();
			const [row] = await tx.select().from(userSettings).where(eq(userSettings.userId, userId)).for("update");
			const overrides = applyPatch((row.settings ?? {}) as Record<string, unknown>, patch as Record<string, unknown>);
			const merged = withDefaults(overrides);
			if (!SettingsSchema.safeParse(merged).success) throw badRequest("Invalid settings");
			const [saved] = await tx
				.update(userSettings)
				.set({ settings: overrides, version: sql`${userSettings.version} + 1`, updatedAt: new Date() })
				.where(eq(userSettings.userId, userId))
				.returning();
			return { settings: merged, overrides, version: saved.version };
		});
		publish(services, `user:${userId}`, "settings.update", result);
		return result;
	});
};
