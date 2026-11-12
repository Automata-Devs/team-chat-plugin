import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, scrypt, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";

const scryptAsync = promisify(scrypt) as (
	password: string,
	salt: Buffer,
	length: number,
	options: { N: number; r: number; p: number; maxmem: number },
) => Promise<Buffer>;

// OWASP's scrypt minimum is N=2^17, r=8, p=1
const SCRYPT = { N: 1 << 17, r: 8, p: 1, maxmem: 256 * 1024 * 1024 };
const KEY_LENGTH = 64;

/** A random URL-safe token with `bytes` bytes of entropy. */
export function randomToken(bytes = 32): string {
	return randomBytes(bytes).toString("base64url");
}

/** For high-entropy tokens (sessions, bot tokens): a fast hash is enough, there's nothing to brute force. */
export function sha256(value: string): Buffer {
	return createHash("sha256").update(value).digest();
}

export async function hashPassword(password: string): Promise<string> {
	const salt = randomBytes(16);
	const key = await scryptAsync(password.normalize("NFKC"), salt, KEY_LENGTH, SCRYPT);
	return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${salt.toString("base64")}$${key.toString("base64")}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
	const [kind, n, r, p, salt, key] = stored.split("$");
	if (kind !== "scrypt" || !salt || !key) return false;
	const expected = Buffer.from(key, "base64");
	const actual = await scryptAsync(password.normalize("NFKC"), Buffer.from(salt, "base64"), expected.length, {
		N: Number(n),
		r: Number(r),
		p: Number(p),
		maxmem: SCRYPT.maxmem,
	});
	return actual.length === expected.length && timingSafeEqual(actual, expected);
}

/** A hash of a made-up password, so a login for an unknown user takes as long as a real one. */
let dummyHash: Promise<string> | undefined;
export function dummyPasswordHash(): Promise<string> {
	dummyHash ??= hashPassword(randomToken());
	return dummyHash;
}

/** AES-256-GCM with a random IV: "v1.<iv>.<tag>.<ciphertext>" (base64url). */
export class SecretBox {
	private readonly key: Buffer;

	constructor(keyBase64: string) {
		this.key = Buffer.from(keyBase64, "base64");
		if (this.key.length !== 32) throw new Error("Encryption key must be 32 bytes");
	}

	encrypt(plain: string): string {
		const iv = randomBytes(12);
		const cipher = createCipheriv("aes-256-gcm", this.key, iv);
		const data = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
		return ["v1", iv, cipher.getAuthTag(), data].map((part) => (typeof part === "string" ? part : part.toString("base64url"))).join(".");
	}

	decrypt(sealed: string): string {
		const [version, iv, tag, data] = sealed.split(".");
		if (version !== "v1" || !iv || !tag || data === undefined) throw new Error("Unknown secret format");
		const decipher = createDecipheriv("aes-256-gcm", this.key, Buffer.from(iv, "base64url"));
		decipher.setAuthTag(Buffer.from(tag, "base64url"));
		return Buffer.concat([decipher.update(Buffer.from(data, "base64url")), decipher.final()]).toString("utf8");
	}
}

export function hmacSha256Hex(secret: string, payload: string): string {
	return createHmac("sha256", secret).update(payload).digest("hex");
}
