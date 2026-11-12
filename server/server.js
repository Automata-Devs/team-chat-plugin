// Team Chat database server: the chat archive, profiles and key/value
// collections for one team. Node.js 18+.
//
//   TEAMCHAT_TOKEN=<long random secret> node server.js
//
// Environment: TEAMCHAT_TOKEN (required), PORT (default 8787), and where to
// keep the data: MONGODB_URI (+ MONGODB_DB, default "teamchat") for MongoDB,
// otherwise a JSON file in DATA_DIR (default ./data). See docs/DATABASE.md.

"use strict";

const crypto = require("node:crypto");
const http = require("node:http");
const path = require("node:path");
const { FileStore } = require("./stores/file");
const { MongoStore } = require("./stores/mongo");

const NAME = /^[A-Za-z0-9_\-.:]{1,128}$/;
const MAX_BODY = 1024 * 1024;
const MAX_VALUE = 64 * 1024;
const MAX_CONTENT = 4000;
const MAX_ARCHIVE_PER_CONVERSATION = 100000;
const MAX_LIST = 1000;

class HttpError extends Error {
	constructor(status, message) {
		super(message);
		this.status = status;
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

function limitOf(query, fallback) {
	const value = Number.parseInt(query.get("limit") || "", 10);
	return Math.min(Math.max(Number.isFinite(value) ? value : fallback, 1), MAX_LIST);
}

function handlers(store) {
	return {
		health: () => ({ ok: true, time: Math.floor(Date.now() / 1000), store: store.kind }),

		async kvList(collection, query) {
			const prefix = query.get("prefix") || "";
			return { items: await store.kvList(name(collection, "collection"), prefix, limitOf(query, MAX_LIST)) };
		},

		async kvGet(collection, key) {
			const item = await store.kvGet(name(collection, "collection"), name(key, "key"));
			if (!item) throw new HttpError(404, "Not found");
			return { key, ...item };
		},

		async kvPut(collection, key, body) {
			name(collection, "collection");
			name(key, "key");
			if (!body || !("value" in body)) throw new HttpError(400, "Missing value");
			if (JSON.stringify(body.value ?? null).length > MAX_VALUE) throw new HttpError(413, "Value too large");
			const ifVersion = number(body.ifVersion);
			if (body.ifVersion !== undefined && ifVersion === undefined) throw new HttpError(400, "Invalid ifVersion");
			const item = await store.kvPut(collection, key, body.value, ifVersion);
			if (!item) throw new HttpError(409, "Version conflict");
			return { key, ...item };
		},

		async kvDelete(collection, key) {
			return { deleted: await store.kvDelete(name(collection, "collection"), name(key, "key")) };
		},

		async archivePost(place, conversation, body) {
			name(place, "place");
			name(conversation, "conversation");
			if (!body || !Array.isArray(body.messages)) throw new HttpError(400, "Missing messages");
			const clean = body.messages.map(cleanMessage);
			await store.archivePut(place, conversation, clean, MAX_ARCHIVE_PER_CONVERSATION);
			return { stored: clean.length };
		},

		async archiveHistory(place, conversation, query) {
			const before = Number(query.get("before")) || Infinity;
			const messages = await store.archiveHistory(
				name(place, "place"),
				name(conversation, "conversation"),
				before,
				limitOf(query, 50),
			);
			return { messages };
		},

		async archiveSearch(place, query) {
			const needle = (query.get("q") || "").toLowerCase().slice(0, 200);
			if (!needle) throw new HttpError(400, "Missing q");
			return { messages: await store.archiveSearch(name(place, "place"), needle, limitOf(query, 10)) };
		},

		async profileGet(userId) {
			const profile = await store.profileGet(name(userId, "user id"));
			if (!profile) throw new HttpError(404, "Not found");
			return profile;
		},

		async profilePost(userId, body) {
			if (!/^[0-9]{1,20}$/.test(userId)) throw new HttpError(400, "Invalid user id");
			const given = (body && body.set) || {};
			const set = {};
			if (typeof given.username === "string") set.username = given.username.slice(0, 50);
			if (number(given.lastSeen) !== undefined) set.lastSeen = given.lastSeen;
			if (given.lastPlace && typeof given.lastPlace === "object") {
				set.lastPlace = { id: number(given.lastPlace.id) || 0, name: text(given.lastPlace.name, 100) || "" };
			}
			const increment = {};
			for (const [stat, by] of Object.entries((body && body.increment) || {})) {
				if (NAME.test(stat) && number(by) !== undefined && Math.abs(by) <= 1e6) increment[stat] = by;
			}
			return store.profileUpdate(userId, set, increment);
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

// store: a FileStore or MongoStore (default: a FileStore in dataDir, or in memory)
function createServer({ token, dataDir, store = new FileStore(dataDir) } = {}) {
	if (!token || token.length < 16) throw new Error("TEAMCHAT_TOKEN must be set (16 characters or more)");
	const api = handlers(store);
	const server = http.createServer(async (req, res) => {
		const send = (status, payload) => {
			res.writeHead(status, { "Content-Type": "application/json" });
			res.end(JSON.stringify(payload));
		};
		try {
			const url = new URL(req.url, "http://localhost");
			// For hosts' health checks: says nothing beyond "up"
			if (url.pathname === "/" && req.method === "GET") return send(200, { ok: true });
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
	server.on("close", () => store.close().catch((error) => console.error(error)));
	return server;
}

module.exports = { createServer, FileStore, MongoStore };

async function main() {
	const port = Number(process.env.PORT) || 8787;
	const store = process.env.MONGODB_URI
		? await MongoStore.connect(process.env.MONGODB_URI, process.env.MONGODB_DB || "teamchat")
		: new FileStore(process.env.DATA_DIR || path.join(__dirname, "data"));
	const server = createServer({ token: process.env.TEAMCHAT_TOKEN, store });
	server.listen(port, () => console.log(`Team Chat database on port ${port} (${store.kind})`));
	for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => server.close(() => process.exit(0)));
}

if (require.main === module) {
	main().catch((error) => {
		console.error(error.message);
		process.exit(1);
	});
}
