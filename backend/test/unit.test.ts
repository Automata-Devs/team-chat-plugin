import { describe, expect, test } from "vitest";
import { loadConfig } from "../src/config.js";
import { SecretBox, hashPassword, verifyPassword } from "../src/lib/crypto.js";
import { ALL_PERMISSIONS, DEFAULT_EVERYONE_PERMISSIONS, Permission, channelPermissions, type MemberContext } from "../src/lib/permissions.js";
import { EPOCH, SnowflakeGenerator, snowflakeAt, timestampOf, workerOf } from "../src/lib/snowflake.js";
import { isPrivateAddress } from "../src/lib/urls.js";
import { applyPatch, withDefaults } from "../src/modules/settings/defaults.js";
import { parseMentions } from "../src/modules/messages/shapes.js";
import { emoji } from "../src/modules/reactions/routes.js";
import { safeFilename } from "../src/modules/attachments/routes.js";
import { toTsquery } from "../src/modules/search/routes.js";

describe("snowflake ids", () => {
	test("are unique and increasing, even thousands in one millisecond", () => {
		const ids = new SnowflakeGenerator(7, () => 1_750_000_000_000);
		const made = Array.from({ length: 10_000 }, () => ids.next());
		expect(new Set(made).size).toBe(made.length);
		for (let i = 1; i < made.length; i++) expect(made[i] > made[i - 1]).toBe(true);
	});

	test("hold the time and the worker", () => {
		const id = new SnowflakeGenerator(513, () => 1_750_000_000_123).next();
		expect(timestampOf(id).getTime()).toBe(1_750_000_000_123);
		expect(workerOf(id)).toBe(513);
		expect(id > 0n && id < 1n << 63n).toBe(true);
	});

	test("never go backwards when the clock does", () => {
		let now = 1_750_000_000_000;
		const ids = new SnowflakeGenerator(1, () => now);
		const first = ids.next();
		now -= 5000;
		expect(ids.next() > first).toBe(true);
	});

	test("two workers never collide", () => {
		const a = new SnowflakeGenerator(1, () => 1_750_000_000_000);
		const b = new SnowflakeGenerator(2, () => 1_750_000_000_000);
		const all = new Set([...Array.from({ length: 1000 }, () => a.next()), ...Array.from({ length: 1000 }, () => b.next())]);
		expect(all.size).toBe(2000);
	});

	test("snowflakeAt bounds ids by time", () => {
		const at = new Date(Number(EPOCH) + 60_000);
		const id = new SnowflakeGenerator(3, () => at.getTime()).next();
		expect(id >= snowflakeAt(at)).toBe(true);
		expect(id < snowflakeAt(new Date(at.getTime() + 1))).toBe(true);
		expect(() => new SnowflakeGenerator(1024)).toThrow();
	});
});

describe("permissions", () => {
	const member = (roles: Array<[bigint, bigint]>, isOwner = false): MemberContext => ({
		userId: 50n,
		isOwner,
		everyoneRoleId: 1n,
		roles: new Map(roles),
	});
	const open = { isPrivate: false, isChannelMember: false };

	test("@everyone, then roles, then the member's own overwrite", () => {
		const m = member([
			[1n, DEFAULT_EVERYONE_PERMISSIONS],
			[2n, 0n],
		]);
		const denyEveryone = { targetType: "role" as const, targetId: 1n, allow: 0n, deny: Permission.SEND_MESSAGES };
		const allowRole = { targetType: "role" as const, targetId: 2n, allow: Permission.SEND_MESSAGES, deny: 0n };
		const denyMember = { targetType: "member" as const, targetId: 50n, allow: 0n, deny: Permission.SEND_MESSAGES };
		expect(channelPermissions(m, [denyEveryone], open) & Permission.SEND_MESSAGES).toBe(0n);
		expect(channelPermissions(m, [denyEveryone, allowRole], open) & Permission.SEND_MESSAGES).toBe(Permission.SEND_MESSAGES);
		expect(channelPermissions(m, [denyEveryone, allowRole, denyMember], open) & Permission.SEND_MESSAGES).toBe(0n);
	});

	test("owners and administrators can do everything; no view means nothing", () => {
		expect(channelPermissions(member([[1n, 0n]], true), [], open)).toBe(ALL_PERMISSIONS);
		expect(channelPermissions(member([[1n, Permission.ADMINISTRATOR]]), [], { isPrivate: true, isChannelMember: false })).toBe(ALL_PERMISSIONS);
		const hidden = { targetType: "role" as const, targetId: 1n, allow: 0n, deny: Permission.VIEW_CHANNEL };
		expect(channelPermissions(member([[1n, DEFAULT_EVERYONE_PERMISSIONS]]), [hidden], open)).toBe(0n);
	});

	test("private channels need membership", () => {
		const m = member([[1n, DEFAULT_EVERYONE_PERMISSIONS]]);
		expect(channelPermissions(m, [], { isPrivate: true, isChannelMember: false })).toBe(0n);
		expect(channelPermissions(m, [], { isPrivate: true, isChannelMember: true })).not.toBe(0n);
	});
});

describe("crypto", () => {
	test("passwords hash with a salt and verify", async () => {
		const a = await hashPassword("correct horse battery");
		const b = await hashPassword("correct horse battery");
		expect(a).not.toBe(b);
		expect(await verifyPassword("correct horse battery", a)).toBe(true);
		expect(await verifyPassword("wrong", a)).toBe(false);
		expect(await verifyPassword("x", "garbage")).toBe(false);
	});

	test("secrets encrypt, decrypt, and refuse tampering", () => {
		const box = new SecretBox(Buffer.alloc(32, 7).toString("base64"));
		const sealed = box.encrypt("signing secret");
		expect(sealed).not.toContain("signing");
		expect(box.decrypt(sealed)).toBe("signing secret");
		const parts = sealed.split(".");
		parts[3] = Buffer.from("tampered").toString("base64url");
		expect(() => box.decrypt(parts.join("."))).toThrow();
	});
});

describe("input handling", () => {
	test("mentions", () => {
		expect(parseMentions("hi <@123> and <@!456> and <@123>")).toEqual({ users: [123n, 456n], everyone: false });
		expect(parseMentions("@everyone look").everyone).toBe(true);
		expect(parseMentions("mail@everyone.com").everyone).toBe(false);
	});

	test("emoji", () => {
		for (const ok of ["👍", "❤️", "👨‍👩‍👧", "🇳🇱", "1️⃣", "party:123456"]) expect(emoji.safeParse(ok).success).toBe(true);
		for (const bad of ["a", "hello", "<script>", "👍 ", "", "x:y"]) expect(emoji.safeParse(bad).success).toBe(false);
	});

	test("file names", () => {
		expect(safeFilename("../../etc/passwd")).toBe("passwd");
		expect(safeFilename("C:\\Users\\a\\map.rbxl")).toBe("map.rbxl");
		expect(safeFilename(".htaccess")).toBe("htaccess");
		expect(safeFilename("a\u0000b<>.png")).toBe("ab.png");
		expect(safeFilename("///")).toBe("file");
	});

	test("search queries can't inject tsquery syntax", () => {
		expect(toTsquery("Lighting is DONE")).toBe("lighting & is & done:*");
		expect(toTsquery("a & b | !c :* ()")).toBe("a & b & c:*");
		expect(toTsquery("!!!")).toBe("");
	});

	test("private addresses", () => {
		for (const ip of ["127.0.0.1", "10.1.2.3", "172.20.0.1", "192.168.1.1", "169.254.169.254", "::1", "fd00::1", "::ffff:10.0.0.1", "0.0.0.0"]) {
			expect(isPrivateAddress(ip)).toBe(true);
		}
		for (const ip of ["93.184.216.34", "2606:4700::1111"]) expect(isPrivateAddress(ip)).toBe(false);
	});

	test("settings patches and defaults", () => {
		const overrides = applyPatch({}, { appearance: { theme: "light" }, language: "nl" });
		expect(withDefaults(overrides).appearance).toEqual({ theme: "light", compact: false, fontScale: 1, showAvatars: true });
		const reset = applyPatch(overrides, { appearance: { theme: null } });
		expect(reset).toEqual({ language: "nl" });
		expect(withDefaults({ gone: true, appearance: { theme: "light", removed: 1 } }).appearance.theme).toBe("light");
	});
});

describe("configuration", () => {
	test("empty values from a .env file count as not set; bad ones are refused", () => {
		const base = { DATABASE_URL: "postgres://x", ENCRYPTION_KEY: Buffer.alloc(32).toString("base64") };
		const config = loadConfig({ ...base, S3_ENDPOINT: "", REDIS_URL: "", WORKER_ID: "", PORT: " " });
		expect(config.S3_ENDPOINT).toBeUndefined();
		expect(config.WORKER_ID).toBeUndefined();
		expect(config.PORT).toBe(8080);
		expect(() => loadConfig({ ...base, S3_ENDPOINT: "not a url" })).toThrow(/S3_ENDPOINT/);
		expect(() => loadConfig({ DATABASE_URL: "postgres://x" })).toThrow(/ENCRYPTION_KEY/);
		// On Render: its own address unless PUBLIC_URL says otherwise
		expect(loadConfig({ ...base, RENDER_EXTERNAL_URL: "https://teamchat.onrender.com" }).PUBLIC_URL).toBe("https://teamchat.onrender.com");
		expect(loadConfig({ ...base, RENDER_EXTERNAL_URL: "https://x.onrender.com", PUBLIC_URL: "https://chat.example.com" }).PUBLIC_URL).toBe(
			"https://chat.example.com",
		);
	});
});
