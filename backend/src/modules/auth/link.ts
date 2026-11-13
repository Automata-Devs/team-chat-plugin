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
import { takeLinkCode } from "./roblox.js";

const escape = (text: string) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");

function page(message?: string): string {
	return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Team Chat sign-in</title>
<body style="font:16px system-ui;max-width:420px;margin:60px auto;padding:0 16px">
<h1 style="font-size:22px">Sign in to Team Chat</h1>
<p>Enter the code Team Chat shows in Roblox Studio.</p>
${message ? `<p style="color:#b42318">${escape(message)}</p>` : ""}
<form method="get" action="/link">
<input name="code" required autofocus autocomplete="off" spellcheck="false" maxlength="12" placeholder="ABCD-2345"
 style="font:600 24px ui-monospace,monospace;letter-spacing:2px;text-transform:uppercase;padding:8px 10px;width:100%;box-sizing:border-box">
<button style="font:16px system-ui;margin-top:12px;padding:10px 16px">Continue to Roblox</button>
</form></body>`;
}

export const linkModule: Module = (app, services) => {
	app.get("/link", { config: { auth: "none", limit: LIMITS.auth } }, async (request, reply) => {
		const robloxOrigin = new URL(services.config.ROBLOX_OAUTH_BASE_URL).origin;
		reply
			.type("text/html; charset=utf-8")
			// form-action also covers where the form's answer redirects to: Roblox
			.header("Content-Security-Policy", `default-src 'none'; style-src 'unsafe-inline'; form-action 'self' ${robloxOrigin}`)
			.header("Cache-Control", "no-store")
			.header("Referrer-Policy", "no-referrer");
		const code = (request.query as { code?: unknown }).code;
		if (typeof code !== "string" || code === "") return reply.send(page());
		const url = await takeLinkCode(services, code);
		if (!url) return reply.status(404).send(page("That code isn't right, or it was already used or expired. Start again from Studio."));
		return reply.redirect(url, 302);
	});
};
