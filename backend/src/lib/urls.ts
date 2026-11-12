import { isIP } from "node:net";
import { badRequest } from "./errors.js";

/**
 * Bot event URLs are called by this server, so they must not point inside
 * its network (SSRF): https only, and every address the name resolves to
 * must be public. Checked when the URL is saved and again before each call.
 */
export async function assertPublicUrl(
	raw: string,
	options: { allowInsecure: boolean; resolveHost: (hostname: string) => Promise<string[]> },
): Promise<URL> {
	let url: URL;
	try {
		url = new URL(raw);
	} catch {
		throw badRequest("Not a valid URL");
	}
	if (url.username || url.password) throw badRequest("URLs can't contain credentials");
	if (options.allowInsecure) return url;
	if (url.protocol !== "https:") throw badRequest("Bot URLs must use https://");

	const host = url.hostname.replace(/^\[|\]$/g, "");
	if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".internal") || host.endsWith(".local")) {
		throw badRequest("Bot URLs must be on the public internet");
	}
	let addresses: string[];
	try {
		addresses = isIP(host) ? [host] : await options.resolveHost(host);
	} catch {
		throw badRequest("The bot URL's host can't be found");
	}
	if (addresses.length === 0 || addresses.some(isPrivateAddress)) throw badRequest("Bot URLs must be on the public internet");
	return url;
}

export function isPrivateAddress(address: string): boolean {
	const ip = address.toLowerCase().replace(/^::ffff:(?=\d+\.\d+\.\d+\.\d+$)/, "");
	if (isIP(ip) === 4) {
		const [a, b] = ip.split(".").map(Number);
		return (
			a === 0 ||
			a === 10 ||
			a === 127 ||
			(a === 100 && b >= 64 && b <= 127) ||
			(a === 169 && b === 254) ||
			(a === 172 && b >= 16 && b <= 31) ||
			(a === 192 && b === 168) ||
			(a === 192 && b === 0) ||
			(a === 198 && (b === 18 || b === 19)) ||
			a >= 224
		);
	}
	if (isIP(ip) === 6) {
		return ip === "::" || ip === "::1" || /^f[cd]/.test(ip) || /^fe[89ab]/.test(ip) || ip.startsWith("ff") || ip.startsWith("64:ff9b");
	}
	return true;
}
