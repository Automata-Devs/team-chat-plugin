/**
 * The short sign-in address: GET /link. Studio plugins can't open a browser
 * or copy to the clipboard, so a Roblox sign-in link is hard to get out of
 * Studio. Instead the plugin shows this short address and an 8-character
 * code (ABCD-2345) that's easy to type; the code sends the browser on to
 * Roblox's sign-in page for that plugin's login. A code works once, for 10
 * minutes, and the plugin still checks that the Roblox account it gets back
 * is the one signed in to Studio.
 */
import type { Module } from "../../http/types.js";
import { LIMITS } from "../../http/rateLimit.js";
import { linkPage, pageCsp } from "./pages.js";
import { takeLinkCode } from "./roblox.js";

export const linkModule: Module = (app, services) => {
	app.get("/link", { config: { auth: "none", limit: LIMITS.auth } }, async (request, reply) => {
		const robloxOrigin = new URL(services.config.ROBLOX_OAUTH_BASE_URL).origin;
		reply
			.type("text/html; charset=utf-8")
			// form-action also covers where the form's answer redirects to: Roblox
			.header("Content-Security-Policy", pageCsp(robloxOrigin))
			.header("Cache-Control", "no-store")
			.header("Referrer-Policy", "no-referrer");
		const code = (request.query as { code?: unknown }).code;
		if (typeof code !== "string" || code === "") return reply.send(linkPage());
		const url = await takeLinkCode(services, code);
		if (!url) {
			return reply
				.status(404)
				.send(
					linkPage(
						"That code didn't work. It may be mistyped, used already, or older than 10 minutes. Get a new one in Studio with /backend login.",
					),
				);
		}
		return reply.redirect(url, 302);
	});
};
