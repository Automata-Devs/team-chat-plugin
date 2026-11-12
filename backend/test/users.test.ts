import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { call, createTestApp, register, send, type TestContext, workspaceWith } from "./helpers.js";

let ctx: TestContext;
beforeAll(async () => {
	ctx = await createTestApp();
});
afterAll(() => ctx.close());

describe("settings", () => {
	test("defaults until changed; changes persist and merge; null resets", async () => {
		const user = await register(ctx);
		const fresh = await call(ctx, "GET", "/users/@me/settings", undefined, user.as);
		expect(fresh.body.settings.appearance.theme).toBe("dark");
		expect(fresh.body.overrides).toEqual({});

		await call(ctx, "PATCH", "/users/@me/settings", { appearance: { theme: "light" } }, user.as);
		const merged = await call(ctx, "PATCH", "/users/@me/settings", { appearance: { compact: true }, language: "nl" }, user.as);
		expect(merged.body.settings.appearance).toMatchObject({ theme: "light", compact: true });
		expect(merged.body.overrides).toEqual({ appearance: { theme: "light", compact: true }, language: "nl" });

		const reset = await call(ctx, "PATCH", "/users/@me/settings", { appearance: { theme: null } }, user.as);
		expect(reset.body.settings.appearance.theme).toBe("dark");
		expect((await call(ctx, "GET", "/users/@me/settings", undefined, user.as)).body.overrides).toEqual({
			appearance: { compact: true },
			language: "nl",
		});
	});

	test("unknown keys and wrong values are refused", async () => {
		const user = await register(ctx);
		expect((await call(ctx, "PATCH", "/users/@me/settings", { appearance: { theme: "pink" } }, user.as)).status).toBe(400);
		expect((await call(ctx, "PATCH", "/users/@me/settings", { notAThing: true }, user.as)).status).toBe(400);
		expect((await call(ctx, "PATCH", "/users/@me/settings", { appearance: { fontScale: 9 } }, user.as)).status).toBe(400);
	});

	test("saves from two devices at once both land", async () => {
		const user = await register(ctx);
		await Promise.all([
			call(ctx, "PATCH", "/users/@me/settings", { appearance: { theme: "light" } }, user.as),
			call(ctx, "PATCH", "/users/@me/settings", { accessibility: { reducedMotion: true } }, user.as),
			call(ctx, "PATCH", "/users/@me/settings", { language: "de" }, user.as),
		]);
		const got = await call(ctx, "GET", "/users/@me/settings", undefined, user.as);
		expect(got.body.overrides).toEqual({ appearance: { theme: "light" }, accessibility: { reducedMotion: true }, language: "de" });
		expect(got.body.version).toBe(4);
	});
});

describe("profiles and account deletion", () => {
	test("profile edits; usernames stay unique", async () => {
		const a = await register(ctx);
		const b = await register(ctx);
		const updated = await call(ctx, "PATCH", "/users/@me", { displayName: "Ana the Builder" }, a.as);
		expect(updated.body.user.displayName).toBe("Ana the Builder");
		expect((await call(ctx, "PATCH", "/users/@me", { username: b.username.toUpperCase() }, a.as)).status).toBe(409);
		expect((await call(ctx, "GET", `/users/${a.id}`, undefined, b.as)).body.user.displayName).toBe("Ana the Builder");
	});

	test("deleting an account follows the retention policy", async () => {
		const leaving = await register(ctx);
		const friend = await register(ctx);
		const other = await register(ctx);
		const owner = await register(ctx);
		const { generalId } = await workspaceWith(ctx, owner, leaving);
		const kept = await send(ctx, leaving, generalId, "my last words");
		const dm = (await call(ctx, "POST", "/conversations", { recipients: [friend.id] }, leaving.as)).body.conversation.id;
		await send(ctx, leaving, dm, "bye friend");
		const group = (await call(ctx, "POST", "/conversations", { recipients: [friend.id, other.id] }, leaving.as)).body.conversation.id;

		expect((await call(ctx, "DELETE", "/users/@me", { password: "wrong password" }, leaving.as)).status).toBe(403);
		expect((await call(ctx, "DELETE", "/users/@me", { password: "correct horse battery" }, leaving.as)).status).toBe(204);

		// Signed out, can't sign in, name freed
		expect((await call(ctx, "GET", "/users/@me", undefined, leaving.as)).status).toBe(401);
		expect((await call(ctx, "POST", "/auth/login", { username: leaving.username, password: "correct horse battery" })).status).toBe(401);
		expect((await call(ctx, "POST", "/auth/register", { username: leaving.username, password: "correct horse battery" })).status).toBe(201);

		// Messages and the DM stay for others, shown as a deleted user
		const history = await call(ctx, "GET", `/channels/${generalId}/messages`, undefined, owner.as);
		const message = history.body.messages.find((m: { id: string }) => m.id === kept.id);
		expect(message.author).toMatchObject({ displayName: "Deleted User", username: "deleted-user" });
		expect((await call(ctx, "GET", `/channels/${dm}/messages`, undefined, friend.as)).body.messages).toHaveLength(1);

		// The group lives on with a new owner
		const groupNow = await call(ctx, "GET", `/conversations/${group}`, undefined, friend.as);
		expect(groupNow.body.conversation.ownerId).not.toBe(leaving.id);
		expect(groupNow.body.conversation.recipients.map((r: { id: string }) => r.id)).not.toContain(leaving.id);

		const leftovers = await ctx.services.db.execute<{ n: number }>(sql`
			select (select count(*) from user_credentials where user_id = ${BigInt(leaving.id)})
			     + (select count(*) from workspace_members where user_id = ${BigInt(leaving.id)})
			     + (select count(*) from sessions where user_id = ${BigInt(leaving.id)} and revoked_at is null) as n`);
		expect(Number(leftovers.rows[0].n)).toBe(0);
	});

	test("an owner must hand over their workspaces first", async () => {
		const owner = await register(ctx);
		await workspaceWith(ctx, owner);
		expect((await call(ctx, "DELETE", "/users/@me", { password: "correct horse battery" }, owner.as)).status).toBe(409);
	});
});
