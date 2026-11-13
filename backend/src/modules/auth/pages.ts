/**
 * The sign-in pages people see in their browser: GET /link (type the code
 * from Studio) and what Roblox's sign-in comes back to. One template, in the
 * logo's style: the code box is the logo's blue chat bubble. No scripts and
 * nothing loaded from elsewhere (see the CSPs), and a dark mode.
 */
import { LOGO_DATA_URI, LOGO_HEIGHT, LOGO_WIDTH } from "./logo.js";

const escape = (text: string) =>
	text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** Only inline styles and the inline logo; `formTo` also lets the form's answer redirect there. */
export function pageCsp(formTo?: string): string {
	const form = formTo ? `form-action 'self' ${formTo}` : "form-action 'none'";
	return `default-src 'none'; style-src 'unsafe-inline'; img-src data:; ${form}; base-uri 'none'; frame-ancestors 'none'`;
}

const STYLE = `
:root {
	color-scheme: light dark;
	--sky: #26cefc; --deep: #0058f4;
	--ink: #14204a; --muted: #4f5b86; --paper: #f3f7ff;
	--pale: #e4ecfc; --edge: #8496cf; --danger: #b4232f;
	--button-text: #ffffff;
}
@media (prefers-color-scheme: dark) {
	:root {
		--ink: #e8eeff; --muted: #a3b0da; --paper: #0b1430;
		--pale: #18264f; --edge: #3d5090; --danger: #ff8f98;
		--button-text: #0b1430;
	}
}
* { box-sizing: border-box; }
html { background: var(--paper); }
body {
	margin: 0; min-height: 100vh; min-height: 100svh;
	display: grid; place-items: center;
	color: var(--ink); background: var(--paper);
	font: 400 17px/1.5 ui-rounded, "SF Pro Rounded", "Segoe UI Variable Display", "Segoe UI", system-ui, sans-serif;
}
main { width: 100%; max-width: 420px; padding: 40px 20px 56px; }
.logo { display: block; width: 64px; height: auto; }
h1 { margin: 24px 0 8px; font-size: 30px; line-height: 1.15; font-weight: 700; letter-spacing: -0.015em; }
p { margin: 0; color: var(--muted); }
.error { margin-top: 16px; color: var(--danger); font-weight: 600; }

/* The code box: the logo's blue bubble, with the pale one behind it */
.bubble { position: relative; margin: 32px 0 44px; }
.bubble::before {
	content: ""; position: absolute; inset: 22px -12px -26px 40px;
	background: var(--pale); border: 1.5px solid var(--edge); border-radius: 26px;
}
.bubble::after {
	content: ""; position: absolute; left: 34px; bottom: -20px; width: 30px; height: 24px;
	background: #0a63f5; clip-path: polygon(0 0, 100% 0, 0 100%); border-bottom-left-radius: 6px;
}
.code {
	position: relative; z-index: 1; display: block; width: 100%;
	padding: 22px 20px; border: 0; border-radius: 24px;
	background: linear-gradient(160deg, var(--sky), var(--deep) 85%);
	box-shadow: 0 12px 28px rgba(0, 88, 244, 0.3);
	color: #ffffff; caret-color: #ffffff; text-align: center; text-transform: uppercase;
	font: 700 clamp(28px, 9vw, 36px)/1.1 ui-monospace, "Cascadia Mono", "SF Mono", Consolas, monospace;
	letter-spacing: 0.16em;
}
.code::placeholder { color: rgba(255, 255, 255, 0.5); }
.code:focus { outline: none; }
.code:focus-visible { outline: 3px solid #0a63f5; outline-offset: 4px; }

button {
	display: block; width: 100%; padding: 15px 18px; border: 0; border-radius: 14px;
	background: var(--ink); color: var(--button-text);
	font-family: inherit; font-size: 17px; font-weight: 600; line-height: 1.2; cursor: pointer;
}
button:hover { opacity: 0.9; }
button:focus-visible { outline: 3px solid var(--sky); outline-offset: 3px; }
.hint { margin-top: 16px; font-size: 15px; }

/* The result: a small bubble with a check, or a pale one with a ! */
.mark {
	display: grid; place-items: center; width: 64px; height: 56px; border-radius: 18px; position: relative;
	background: linear-gradient(160deg, var(--sky), var(--deep) 85%); color: #ffffff;
}
.mark::after {
	content: ""; position: absolute; left: 12px; bottom: -11px; width: 16px; height: 13px;
	background: #0a63f5; clip-path: polygon(0 0, 100% 0, 0 100%);
}
.mark.failed { background: var(--pale); border: 1.5px solid var(--edge); color: var(--danger); }
.mark.failed::after { background: var(--edge); }
.mark svg { width: 28px; height: 28px; }
`;

function shell(title: string, body: string): string {
	return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<link rel="icon" href="${LOGO_DATA_URI}">
<title>${escape(title)} · Team Chat</title>
<style>${STYLE}</style>
</head>
<body>
<main>
${body}
</main>
</body>
</html>`;
}

const logo = `<img class="logo" src="${LOGO_DATA_URI}" width="${LOGO_WIDTH}" height="${LOGO_HEIGHT}" alt="Team Chat">`;

/** GET /link: type the code Team Chat shows in Studio. */
export function linkPage(error?: string): string {
	return shell(
		"Sign in",
		`${logo}
<h1>Sign in to Team Chat</h1>
<p>Type the code from the Team Chat window in Roblox Studio.</p>
${error ? `<p class="error" role="alert">${escape(error)}</p>` : ""}
<form method="get" action="/link">
<div class="bubble">
<input class="code" name="code" aria-label="Sign-in code" placeholder="ABCD-2345" required autofocus
 autocomplete="one-time-code" autocapitalize="characters" spellcheck="false" maxlength="12" inputmode="text">
</div>
<button type="submit">Continue to Roblox</button>
</form>
<p class="hint">Each code works once, for 10 minutes. Roblox then asks you to approve signing in.</p>`,
	);
}

const CHECK = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>`;
const BANG = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" aria-hidden="true"><path d="M12 6v8"/><path d="M12 18.5v.01"/></svg>`;

/** What the browser shows once Roblox's sign-in is done (or didn't work). */
export function resultPage(result: { ok: boolean; title: string; message: string }): string {
	return shell(
		result.title,
		`<div class="mark${result.ok ? "" : " failed"}">${result.ok ? CHECK : BANG}</div>
<h1>${escape(result.title)}</h1>
<p>${escape(result.message)}</p>`,
	);
}
