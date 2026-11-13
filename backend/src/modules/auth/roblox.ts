/**
 * Sign in with Roblox (OAuth 2.0 + PKCE), shaped for a Studio plugin, which
 * can't receive a redirect itself:
 *
 *   1. The plugin calls POST /auth/roblox/start and gets a URL, a short code
 *      for GET /link (see link.ts) and a poll secret.
 *   2. The person opens the URL, or types the short address and code, in a
 *      browser and approves on roblox.com.
 *   3. Roblox redirects to GET /auth/roblox/callback here; the code is checked
 *      with Roblox, which tells us their real Roblox user id.
 *   4. The plugin polls POST /auth/roblox/poll and receives a session token.
 *
 * So a Roblox identity is never taken from the plugin's word.
 */
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { and, eq } from "drizzle-orm";
import type { FastifyRequest } from "fastify";
import type { Services } from "../../context.js";
import { connectedAccounts, users } from "../../db/schema.js";
import { randomToken } from "../../lib/crypto.js";
import { AppError, badRequest, conflict, forbidden, unavailable } from "../../lib/errors.js";
import { audit, publicUser } from "../shared.js";
import { createSession, freeUsername } from "./service.js";

const FLOW_SECONDS = 600;
// No 0/O or 1/I: easy to read off a screen and type. 32 letters, so a random byte maps without bias.
const CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

/** A short sign-in code, ABCD-2345: 8 letters, about 10^12 possibilities. */
function shortCode(): string {
	const letters = [...randomBytes(8)].map((byte) => CODE_LETTERS[byte % 32]).join("");
	return `${letters.slice(0, 4)}-${letters.slice(4)}`;
}

/** A code as typed (any case, with or without the dash or spaces) in its stored form, or null. */
function normalizeCode(typed: string): string | null {
	const letters = typed.toUpperCase().replace(/[^A-Z0-9]/g, "");
	if (letters.length !== 8 || [...letters].some((c) => !CODE_LETTERS.includes(c))) return null;
	return `${letters.slice(0, 4)}-${letters.slice(4)}`;
}

interface Flow {
	loginId: string;
	verifier: string;
	linkUserId?: string;
}

type LoginState =
	| { status: "pending"; pollHash: string }
	| { status: "done"; pollHash: string; sealed: string }
	| { status: "failed"; pollHash: string; error: string };

const hashHex = (value: string) => createHash("sha256").update(value).digest("hex");
const callbackUrl = (services: Services) => `${services.config.PUBLIC_URL}/api/v1/auth/roblox/callback`;
const jsonText = (value: unknown) => JSON.stringify(value, (_k, v) => (typeof v === "bigint" ? v.toString() : v));

function client(services: Services) {
	const { ROBLOX_OAUTH_CLIENT_ID: id, ROBLOX_OAUTH_CLIENT_SECRET: secret } = services.config;
	if (!id || !secret) throw unavailable("Sign in with Roblox isn't set up on this server");
	return { id, secret };
}

export async function startRobloxLogin(services: Services, linkUserId?: bigint) {
	const { id } = client(services);
	const loginId = randomToken(16);
	const pollSecret = randomToken(24);
	const state = randomToken(24);
	const verifier = randomToken(48);
	const challenge = createHash("sha256").update(verifier).digest("base64url");

	const flow: Flow = { loginId, verifier, linkUserId: linkUserId?.toString() };
	await services.cache.set(`oauth:state:${state}`, JSON.stringify(flow), FLOW_SECONDS);
	const login: LoginState = { status: "pending", pollHash: hashHex(pollSecret) };
	await services.cache.set(`oauth:login:${loginId}`, JSON.stringify(login), FLOW_SECONDS);

	const url = new URL(`${services.config.ROBLOX_OAUTH_BASE_URL}/v1/authorize`);
	url.search = new URLSearchParams({
		client_id: id,
		redirect_uri: callbackUrl(services),
		scope: "openid profile",
		response_type: "code",
		state,
		code_challenge: challenge,
		code_challenge_method: "S256",
	}).toString();
	const code = shortCode();
	await services.cache.set(`oauth:code:${code}`, url.toString(), FLOW_SECONDS);
	return {
		loginId,
		pollSecret,
		url: url.toString(),
		code,
		linkUrl: `${services.config.PUBLIC_URL}/link`,
		expiresIn: FLOW_SECONDS,
	};
}

/** The Roblox sign-in URL for a short code, once: the code is used up. Null when unknown or expired. */
export async function takeLinkCode(services: Services, typed: string): Promise<string | null> {
	const code = normalizeCode(typed);
	if (!code) return null;
	const key = `oauth:code:${code}`;
	const url = await services.cache.get(key);
	if (url) await services.cache.del(key);
	return url;
}

interface RobloxProfile {
	sub: string;
	preferred_username?: string;
	name?: string;
	nickname?: string;
	picture?: string;
}

async function verifiedProfile(services: Services, code: string, verifier: string): Promise<RobloxProfile> {
	const { id, secret } = client(services);
	const base = services.config.ROBLOX_OAUTH_BASE_URL;
	const tokenResponse = await services.fetch(`${base}/v1/token`, {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body: new URLSearchParams({
			grant_type: "authorization_code",
			code,
			redirect_uri: callbackUrl(services),
			client_id: id,
			client_secret: secret,
			code_verifier: verifier,
		}),
		signal: AbortSignal.timeout(10_000),
	});
	if (!tokenResponse.ok) throw badRequest("Roblox didn't accept the sign-in");
	const { access_token } = (await tokenResponse.json()) as { access_token?: string };
	if (!access_token) throw badRequest("Roblox didn't return an access token");

	const profileResponse = await services.fetch(`${base}/v1/userinfo`, {
		headers: { Authorization: `Bearer ${access_token}` },
		signal: AbortSignal.timeout(10_000),
	});
	if (!profileResponse.ok) throw badRequest("Couldn't read the Roblox profile");
	const profile = (await profileResponse.json()) as RobloxProfile;
	if (!profile.sub || !/^[0-9]{1,20}$/.test(profile.sub)) throw badRequest("Roblox returned no user id");
	return profile;
}

/** Handles Roblox's redirect. Returns the text to show in the browser. */
export async function finishRobloxLogin(services: Services, request: FastifyRequest, code: string, state: string) {
	const raw = await services.cache.get(`oauth:state:${state}`);
	if (!raw) throw badRequest("This sign-in link expired. Start again from Studio.");
	await services.cache.del(`oauth:state:${state}`); // one use only
	const flow = JSON.parse(raw) as Flow;
	const loginKey = `oauth:login:${flow.loginId}`;
	const loginRaw = await services.cache.get(loginKey);
	if (!loginRaw) throw badRequest("This sign-in expired. Start again from Studio.");
	const { pollHash } = JSON.parse(loginRaw) as LoginState;

	try {
		const profile = await verifiedProfile(services, code, flow.verifier);
		const result = await services.db.transaction(async (tx) => {
			const [linked] = await tx
				.select({ user: users })
				.from(connectedAccounts)
				.innerJoin(users, eq(users.id, connectedAccounts.userId))
				.where(and(eq(connectedAccounts.provider, "roblox"), eq(connectedAccounts.providerUserId, profile.sub)))
				.limit(1);

			if (flow.linkUserId) {
				const userId = BigInt(flow.linkUserId);
				if (linked && linked.user.id !== userId) throw conflict("That Roblox account is linked to another user");
				if (!linked) {
					await tx.insert(connectedAccounts).values({
						id: services.ids.next(),
						userId,
						provider: "roblox",
						providerUserId: profile.sub,
						providerUsername: profile.preferred_username ?? null,
					});
				}
				await audit(services, tx, request, { action: "auth.roblox_link", actorId: userId, targetType: "roblox", targetId: profile.sub });
				return { linked: true };
			}

			let user = linked?.user;
			if (user && user.status !== "active") throw forbidden("This account can't sign in");
			if (!user) {
				const id = services.ids.next();
				[user] = await tx
					.insert(users)
					.values({
						id,
						username: await freeUsername(tx, profile.preferred_username ?? `roblox_${profile.sub}`),
						displayName: profile.name ?? profile.nickname ?? null,
						avatarUrl: profile.picture ?? null,
						lastActiveAt: new Date(),
					})
					.returning();
				await tx.insert(connectedAccounts).values({
					id: services.ids.next(),
					userId: id,
					provider: "roblox",
					providerUserId: profile.sub,
					providerUsername: profile.preferred_username ?? null,
				});
				await audit(services, tx, request, { action: "auth.register", actorId: id, targetType: "roblox", targetId: profile.sub });
			}
			const session = await createSession(services, tx, user.id, request);
			await audit(services, tx, request, {
				action: "auth.roblox_login",
				actorId: user.id,
				targetType: "session",
				targetId: session.sessionId,
			});
			return { user: publicUser(user), token: session.token, expiresAt: session.expiresAt };
		});

		// Encrypted while it waits in the cache for the plugin to collect it
		const done: LoginState = { status: "done", pollHash, sealed: services.secrets.encrypt(jsonText(result)) };
		await services.cache.set(loginKey, JSON.stringify(done), FLOW_SECONDS);
		return "linked" in result ? "Your Roblox account is linked. You can close this tab." : "You're signed in. Go back to Roblox Studio.";
	} catch (error) {
		const message = error instanceof AppError && error.status < 500 ? error.message : "Sign-in failed";
		const failed: LoginState = { status: "failed", pollHash, error: message };
		await services.cache.set(loginKey, JSON.stringify(failed), FLOW_SECONDS);
		throw error;
	}
}

export async function pollRobloxLogin(services: Services, loginId: string, pollSecret: string) {
	const key = `oauth:login:${loginId}`;
	const raw = await services.cache.get(key);
	if (!raw) throw new AppError(410, "expired", "This sign-in expired. Start again.");
	const login = JSON.parse(raw) as LoginState;
	const given = Buffer.from(hashHex(pollSecret), "hex");
	const expected = Buffer.from(login.pollHash, "hex");
	if (given.length !== expected.length || !timingSafeEqual(given, expected)) throw forbidden("Wrong poll secret");

	if (login.status === "pending") return { status: "pending" as const };
	await services.cache.del(key); // a result is handed out once
	if (login.status === "failed") return { status: "failed" as const, error: login.error };
	return { status: "done" as const, ...JSON.parse(services.secrets.decrypt(login.sealed)) };
}
