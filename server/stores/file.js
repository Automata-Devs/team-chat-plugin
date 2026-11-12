// Keeps everything in one JSON file, saved shortly after each change
// (written to a temp file, then renamed). Without a directory it only
// keeps data in memory.

"use strict";

const fs = require("node:fs");
const path = require("node:path");

const SAVE_DELAY_MS = 200;

function byTime(a, b) {
	return a.timestamp - b.timestamp || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}

class FileStore {
	constructor(dir) {
		this.file = dir ? path.join(dir, "teamchat.json") : null;
		this.timer = null;
		this.data = { kv: {}, archive: {}, profiles: {} };
		if (this.file && fs.existsSync(this.file)) {
			Object.assign(this.data, JSON.parse(fs.readFileSync(this.file, "utf8")));
		}
	}

	get kind() {
		return this.file ? "file" : "memory";
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

	async close() {
		this.flush();
	}

	async kvList(collection, prefix, limit) {
		const items = this.data.kv[collection] || {};
		return Object.keys(items)
			.filter((key) => key.startsWith(prefix))
			.sort()
			.slice(0, limit)
			.map((key) => ({ key, value: items[key].value, updatedAt: items[key].updatedAt }));
	}

	async kvGet(collection, key) {
		return (this.data.kv[collection] || {})[key] || null;
	}

	async kvPut(collection, key, value, ifVersion) {
		const items = (this.data.kv[collection] ||= {});
		const old = items[key];
		if (ifVersion !== undefined && (old ? old.version : 0) !== ifVersion) return null;
		items[key] = { value, version: (old ? old.version : 0) + 1, updatedAt: Math.floor(Date.now() / 1000) };
		this.changed();
		return items[key];
	}

	async kvDelete(collection, key) {
		const items = this.data.kv[collection] || {};
		if (!Object.hasOwn(items, key)) return false;
		delete items[key];
		this.changed();
		return true;
	}

	async archivePut(place, conversation, messages, cap) {
		const stored = ((this.data.archive[place] ||= {})[conversation] ||= {});
		for (const message of messages) stored[message.id] = message;
		const all = Object.values(stored);
		if (all.length > cap) {
			for (const message of all.sort(byTime).slice(0, all.length - cap)) delete stored[message.id];
		}
		this.changed();
	}

	async archiveHistory(place, conversation, before, limit) {
		const stored = (this.data.archive[place] || {})[conversation] || {};
		return Object.values(stored)
			.filter((message) => message.timestamp < before)
			.sort(byTime)
			.slice(-limit);
	}

	async archiveSearch(place, needle, limit) {
		const found = [];
		for (const [conversation, stored] of Object.entries(this.data.archive[place] || {})) {
			for (const message of Object.values(stored)) {
				if (message.content.toLowerCase().includes(needle)) found.push({ ...message, conversation });
			}
		}
		return found.sort((a, b) => byTime(b, a)).slice(0, limit);
	}

	async profileGet(userId) {
		return this.data.profiles[userId] || null;
	}

	async profileUpdate(userId, set, increment) {
		const now = Math.floor(Date.now() / 1000);
		const profile = (this.data.profiles[userId] ||= { userId: Number(userId), firstSeen: now, stats: {} });
		Object.assign(profile, set);
		for (const [stat, by] of Object.entries(increment)) profile.stats[stat] = (profile.stats[stat] || 0) + by;
		this.changed();
		return profile;
	}
}

module.exports = { FileStore };
