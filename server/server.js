// Team Chat database server: the chat archive, profiles and key/value
// collections for one team. Node.js 18+, no dependencies.
//
//   TEAMCHAT_TOKEN=<long random secret> node server.js
//
// Environment: TEAMCHAT_TOKEN (required), PORT (default 8787),
// DATA_DIR (default ./data). See docs/DATABASE.md.

"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const NAME = /^[A-Za-z0-9_\-.:]{1,128}$/;
const MAX_BODY = 1024 * 1024;
const MAX_VALUE = 64 * 1024;
const MAX_CONTENT = 4000;
const MAX_ARCHIVE_PER_CONVERSATION = 100000;
const MAX_LIST = 1000;
const SAVE_DELAY_MS = 200;

class HttpError extends Error {
	constructor(status, message) {
		super(message);
		this.status = status;
	}
}

function emptyData() {
	return { kv: {}, archive: {}, profiles: {} };
}

// One JSON file, saved shortly after each change (written to a temp file, then renamed)
class FileStore {
	constructor(dir) {
		this.file = dir ? path.join(dir, "teamchat.json") : null;
		this.timer = null;
		this.data = emptyData();
		if (this.file && fs.existsSync(this.file)) {
			this.data = { ...emptyData(), ...JSON.parse(fs.readFileSync(this.file, "utf8")) };
		}
	}

	changed() {
		if (!this.file || this.timer) return;
		this.timer = setTimeout(() => this.flush(), SAVE_DELAY_MS);
	}

	flush() {
		clearTimeout(this.timer);
		this.timer = null;
		if (!this.file) return;
		fs.mkdirSync(path.dirname(this.file), { recursive: true });
		const temp = this.file + ".tmp";
		fs.writeFileSync(temp, JSON.stringify(this.data));
		fs.renameSync(temp, this.file);
	}
}

function sameSecret(given, expected) {
	const a = crypto.createHash("sha256").update(String(given || "")).digest();
	const b = crypto.createHash("sha256").update(String(expected)).digest();
	return crypto.timingSafeEqual(a, b);
}

function name(value, what) {
	if (!NAME.test(value)) throw new HttpError(400, `Invalid ${what}`);
	return value;
}

function readBody(req) {
	return new Promise((resolve, reject) => {
		let size = 0;
		const chunks = [];
		req.on("data", (chunk) => {
			size += chunk.length;
			if (size > MAX_BODY) {
				reject(new HttpError(413, "Body too large"));
				req.destroy();
				return;
			}
			chunks.push(chunk);
		});
		req.on("end", () => {
			if (chunks.length === 0) return resolve(undefined);
			try {
				resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
			} catch {
				reject(new HttpError(400, "Body is not JSON"));
			}
		});
		req.on("error", reject);
	});
}

const text = (value, max) => (typeof value === "string" ? value.slice(0, max) : undefined);
const number = (value) => (typeof value === "number" && Number.isFinite(value) ? value : undefined);

function cleanMessage(message) {
	if (!message || typeof message !== "object") throw new HttpError(400, "Invalid message");
	return {
		id: name(String(message.id || ""), "message id"),
		sender: text(message.sender, 100) || "Unknown",
		senderId: number(message.senderId) || 0,
		timestamp: number(message.timestamp) || Math.floor(Date.now() / 1000),
		content: text(message.content, MAX_CONTENT) || "",
		type: text(message.type, 20),
		editedAt: number(message.editedAt),
		command: text(message.command, 100),
		botId: text(message.botId, 100),
		saidBy: number(message.saidBy),
		fileName: text(message.fileName, 200),
		fileUrl: text(message.fileUrl, 500),
		imageUrl: text(message.imageUrl, 500),
		replyToTimestamp: number(message.replyToTimestamp),
	};
}

function byTime(a, b) {
	return a.timestamp - b.timestamp || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}

function limitOf(query, fallback) {
	const value = Number.parseInt(query.get("limit") || "", 10);
	return Math.min(Math.max(Number.isFinite(value) ? value : fallback, 1), MAX_LIST);
}

function handlers(store) {
	const data = () => store.data;

	return {
		health: () => ({ ok: true, time: Math.floor(Date.now() / 1000) }),

		kvList(collection, query) {
			const items = data().kv[name(collection, "collection")] || {};
			const prefix = query.get("prefix") || "";
			const keys = Object.keys(items)
				.filter((key) => key.startsWith(prefix))
				.sort()
				.slice(0, limitOf(query, MAX_LIST));
			return { items: keys.map((key) => ({ key, value: items[key].value, updatedAt: items[key].updatedAt })) };
		},

		kvGet(collection, key) {
			const item = (data().kv[name(collection, "collection")] || {})[name(key, "key")];
			if (!item) throw new HttpError(404, "Not found");
			return { key, ...item };
		},

		kvPut(collection, key, body) {
			name(collection, "collection");
			name(key, "key");
			if (!body || !("value" in body)) throw new HttpError(400, "Missing value");
			if (JSON.stringify(body.value ?? null).length > MAX_VALUE) throw new HttpError(413, "Value too large");
			const items = (data().kv[collection] ||= {});
			const old = items[key];
			if (body.ifVersion !== undefined && (old ? old.version : 0) !== body.ifVersion) {
				throw new HttpError(409, "Version conflict");
			}
			items[key] = {
				value: body.value,
				version: (old ? old.version : 0) + 1,
				updatedAt: Math.floor(Date.now() / 1000),
			};
			store.changed();
			return { key, ...items[key] };
		},

		kvDelete(collection, key) {
			const items = data().kv[name(collection, "collection")] || {};
			const existed = Object.hasOwn(items, name(key, "key"));
			delete items[key];
			if (existed) store.changed();
			return { deleted: existed };
		},

		archivePost(place, conversation, body) {
			name(place, "place");
			name(conversation, "conversation");
			if (!body || !Array.isArray(body.messages)) throw new HttpError(400, "Missing messages");
			const clean = body.messages.map(cleanMessage);
			const messages = ((data().archive[place] ||= {})[conversation] ||= {});
			for (const message of clean) messages[message.id] = message;
			const ids = Object.keys(messages);
			if (ids.length > MAX_ARCHIVE_PER_CONVERSATION) {
				const oldest = Object.values(messages).sort(byTime);
				for (const message of oldest.slice(0, ids.length - MAX_ARCHIVE_PER_CONVERSATION)) {
					delete messages[message.id];
				}
			}
			store.changed();
			return { stored: clean.length };
		},

		archiveHistory(place, conversation, query) {
			const messages = (data().archive[name(place, "place")] || {})[name(conversation, "conversation")] || {};
			const before = Number(query.get("before")) || Infinity;
			const sorted = Object.values(messages)
				.filter((message) => message.timestamp < before)
				.sort(byTime);
			return { messages: sorted.slice(-limitOf(query, 50)) };
		},

		archiveSearch(place, query) {
			const needle = (query.get("q") || "").toLowerCase();
			if (!needle) throw new HttpError(400, "Missing q");
			const found = [];
			for (const [conversation, messages] of Object.entries(data().archive[name(place, "place")] || {})) {
				for (const message of Object.values(messages)) {
					if (message.content.toLowerCase().includes(needle)) found.push({ ...message, conversation });
				}
			}
			found.sort((a, b) => byTime(b, a));
			return { messages: found.slice(0, limitOf(query, 10)) };
		},

		profileGet(userId) {
			const profile = data().profiles[name(userId, "user id")];
			if (!profile) throw new HttpError(404, "Not found");
			return profile;
		},

		profilePost(userId, body) {
			if (!/^[0-9]{1,20}$/.test(userId)) throw new HttpError(400, "Invalid user id");
			const now = Math.floor(Date.now() / 1000);
			const profile = (data().profiles[userId] ||= { userId: Number(userId), firstSeen: now, stats: {} });
			const set = (body && body.set) || {};
			if (typeof set.username === "string") profile.username = set.username.slice(0, 50);
			if (number(set.lastSeen) !== undefined) profile.lastSeen = set.lastSeen;
			if (set.lastPlace && typeof set.lastPlace === "object") {
				profile.lastPlace = { id: number(set.lastPlace.id) || 0, name: text(set.lastPlace.name, 100) || "" };
			}
			for (const [stat, by] of Object.entries((body && body.increment) || {})) {
				if (NAME.test(stat) && number(by) !== undefined && Math.abs(by) <= 1e6) {
					profile.stats[stat] = (profile.stats[stat] || 0) + by;
				}
			}
			store.changed();
			return profile;
		},
	};
}

async function route(api, method, parts, query, req) {
	const [area, a, b] = parts;
	const body = method === "PUT" || method === "POST" ? await readBody(req) : undefined;
	if (area === "health" && parts.length === 1 && method === "GET") return api.health();
	if (area === "kv") {
		if (parts.length === 2 && method === "GET") return api.kvList(a, query);
		if (parts.length === 3 && method === "GET") return api.kvGet(a, b);
		if (parts.length === 3 && method === "PUT") return api.kvPut(a, b, body);
		if (parts.length === 3 && method === "DELETE") return api.kvDelete(a, b);
	}
	if (area === "archive") {
		if (parts.length === 2 && method === "GET") return api.archiveSearch(a, query);
		if (parts.length === 3 && method === "GET") return api.archiveHistory(a, b, query);
		if (parts.length === 3 && method === "POST") return api.archivePost(a, b, body);
	}
	if (area === "profiles" && parts.length === 2) {
		if (method === "GET") return api.profileGet(a);
		if (method === "POST") return api.profilePost(a, body);
	}
	throw new HttpError(404, "No such route");
}

function createServer({ token, dataDir } = {}) {
	if (!token || token.length < 16) throw new Error("TEAMCHAT_TOKEN must be set (16 characters or more)");
	const store = new FileStore(dataDir);
	const api = handlers(store);
	const server = http.createServer(async (req, res) => {
		const send = (status, payload) => {
			res.writeHead(status, { "Content-Type": "application/json" });
			res.end(JSON.stringify(payload));
		};
		try {
			const url = new URL(req.url, "http://localhost");
			if (!url.pathname.startsWith("/v1/")) throw new HttpError(404, "No such route");
			if (!sameSecret(req.headers["x-teamchat-token"], token)) throw new HttpError(401, "Wrong token");
			const parts = url.pathname.slice(4).split("/").filter(Boolean).map(decodeURIComponent);
			send(200, await route(api, req.method, parts, url.searchParams, req));
		} catch (error) {
			const status = error instanceof HttpError ? error.status : 500;
			if (status === 500) console.error(error);
			send(status, { error: status === 500 ? "Server error" : error.message });
		}
	});
	server.on("close", () => store.flush());
	return server;
}

module.exports = { createServer };

if (require.main === module) {
	const port = Number(process.env.PORT) || 8787;
	const server = createServer({
		token: process.env.TEAMCHAT_TOKEN,
		dataDir: process.env.DATA_DIR || path.join(__dirname, "data"),
	});
	server.listen(port, () => console.log(`Team Chat database on port ${port}`));
	for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => server.close(() => process.exit(0)));
}
