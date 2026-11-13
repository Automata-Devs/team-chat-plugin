/**
 * A reference for the plugin's end-to-end encryption (src/Services/Backend/Seal.luau,
 * docs/backend/MESSAGES.md), for the tests: the server itself never seals or opens.
 *
 *   master = HMAC-SHA256(key = place secret, "Team Chat end-to-end key v1")
 *   enc, mac, nonce keys = HMAC-SHA256(master, "enc" | "mac" | "nonce")
 *   sealed = "e2e1:" + Base64(nonce[12] || ChaCha20(enc, nonce, counter 1, text) || tag[16])
 *   tag = HMAC-SHA256(mac, "e2e1" || nonce || ciphertext), first 16 bytes
 */
import { createCipheriv, createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

function keysOf(secret: string) {
	const master = createHmac("sha256", secret).update("Team Chat end-to-end key v1").digest();
	const sub = (label: string) => createHmac("sha256", master).update(label).digest();
	return { enc: sub("enc"), mac: sub("mac"), nonce: sub("nonce") };
}

function chacha(key: Buffer, nonce: Buffer, data: Buffer): Buffer {
	const counter = Buffer.alloc(4);
	counter.writeUInt32LE(1);
	const cipher = createCipheriv("chacha20", key, Buffer.concat([counter, nonce]));
	return Buffer.concat([cipher.update(data), cipher.final()]);
}

const tagOf = (mac: Buffer, nonce: Buffer, body: Buffer) =>
	createHmac("sha256", mac).update("e2e1").update(nonce).update(body).digest().subarray(0, 16);

/** What the plugin sends to join a place instead of its secret. */
export const proofOf = (secret: string) => createHash("sha256").update(secret).digest("hex");

export function seal(secret: string, text: string): string {
	const keys = keysOf(secret);
	const plain = Buffer.from(text, "utf8");
	const nonce = createHmac("sha256", keys.nonce).update(randomBytes(16)).update(plain).digest().subarray(0, 12);
	const body = chacha(keys.enc, nonce, plain);
	return `e2e1:${Buffer.concat([nonce, body, tagOf(keys.mac, nonce, body)]).toString("base64")}`;
}

/** The text, or null when it isn't sealed with this secret's key (or was changed). */
export function open(secret: string, sealed: string): string | null {
	if (!sealed.startsWith("e2e1:")) return null;
	const bytes = Buffer.from(sealed.slice(5), "base64");
	if (bytes.length < 28) return null;
	const keys = keysOf(secret);
	const nonce = bytes.subarray(0, 12);
	const body = bytes.subarray(12, bytes.length - 16);
	if (!timingSafeEqual(tagOf(keys.mac, nonce, body), bytes.subarray(bytes.length - 16))) return null;
	return chacha(keys.enc, nonce, body).toString("utf8");
}
