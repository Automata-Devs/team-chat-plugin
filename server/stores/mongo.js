// Keeps everything in MongoDB (for example a MongoDB Atlas cluster).
// Collections: kv, archive and profiles, in the database named by the
// connection string (or MONGODB_DB, default "teamchat").

"use strict";

const HIDDEN = { _id: 0, place: 0, conversation: 0 };

// Stat names may contain "." (a path separator in MongoDB updates)
const statField = (stat) => "stats." + stat.replaceAll(".", "%2E");
const statName = (field) => field.replaceAll("%2E", ".");

function escapeRegex(text) {
	return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function profileOut(doc) {
	if (!doc) return null;
	const { _id, stats, ...profile } = doc;
	profile.stats = {};
	for (const [field, value] of Object.entries(stats || {})) profile.stats[statName(field)] = value;
	return profile;
}

// Values are kept as JSON text: bot values may have keys MongoDB doesn't allow ("$x", "a.b")
const kvOut = (doc) => ({ value: JSON.parse(doc.json), version: doc.version, updatedAt: doc.updatedAt });

class MongoStore {
	static async connect(uri, dbName) {
		let MongoClient;
		try {
			({ MongoClient } = require("mongodb"));
		} catch {
			throw new Error("MONGODB_URI is set but the mongodb package isn't installed: run npm install in server/");
		}
		const client = new MongoClient(uri, { ignoreUndefined: true, appName: "teamchat-database" });
		await client.connect();
		const store = new MongoStore(client, client.db(dbName || undefined));
		await store.prepare();
		return store;
	}

	constructor(client, db) {
		this.client = client;
		this.kv = db.collection("kv");
		this.archive = db.collection("archive");
		this.profiles = db.collection("profiles");
	}

	get kind() {
		return "mongodb";
	}

	async prepare() {
		await Promise.all([
			this.kv.createIndex({ collection: 1, key: 1 }, { unique: true }),
			this.archive.createIndex({ place: 1, conversation: 1, id: 1 }, { unique: true }),
			this.archive.createIndex({ place: 1, conversation: 1, timestamp: -1, id: -1 }),
			this.profiles.createIndex({ userId: 1 }, { unique: true }),
		]);
	}

	async close() {
		await this.client.close();
	}

	async kvList(collection, prefix, limit) {
		const filter = { collection };
		if (prefix) filter.key = { $regex: "^" + escapeRegex(prefix) };
		const docs = await this.kv.find(filter).sort({ key: 1 }).limit(limit).toArray();
		return docs.map((doc) => ({ key: doc.key, value: JSON.parse(doc.json), updatedAt: doc.updatedAt }));
	}

	async kvGet(collection, key) {
		const doc = await this.kv.findOne({ collection, key });
		return doc ? kvOut(doc) : null;
	}

	async kvPut(collection, key, value, ifVersion) {
		const updatedAt = Math.floor(Date.now() / 1000);
		const json = JSON.stringify(value ?? null);
		if (ifVersion === 0) {
			try {
				await this.kv.insertOne({ collection, key, json, version: 1, updatedAt });
			} catch (error) {
				if (error.code === 11000) return null;
				throw error;
			}
			return { value, version: 1, updatedAt };
		}
		const filter = ifVersion === undefined ? { collection, key } : { collection, key, version: ifVersion };
		try {
			const doc = await this.kv.findOneAndUpdate(
				filter,
				{ $set: { json, updatedAt }, $inc: { version: 1 } },
				{ upsert: ifVersion === undefined, returnDocument: "after" },
			);
			return doc ? kvOut(doc) : null;
		} catch (error) {
			// Two first writes at once: the other one won the insert
			if (error.code === 11000) return this.kvPut(collection, key, value, ifVersion);
			throw error;
		}
	}

	async kvDelete(collection, key) {
		const { deletedCount } = await this.kv.deleteOne({ collection, key });
		return deletedCount > 0;
	}

	async archivePut(place, conversation, messages, cap) {
		if (messages.length === 0) return;
		await this.archive.bulkWrite(
			messages.map((message) => ({
				replaceOne: {
					filter: { place, conversation, id: message.id },
					replacement: { ...message, place, conversation },
					upsert: true,
				},
			})),
			{ ordered: false },
		);
		const extra = (await this.archive.countDocuments({ place, conversation })) - cap;
		if (extra > 0) {
			const oldest = await this.archive
				.find({ place, conversation }, { projection: { _id: 1 } })
				.sort({ timestamp: 1, id: 1 })
				.limit(extra)
				.toArray();
			await this.archive.deleteMany({ _id: { $in: oldest.map((doc) => doc._id) } });
		}
	}

	async archiveHistory(place, conversation, before, limit) {
		const filter = { place, conversation };
		if (Number.isFinite(before)) filter.timestamp = { $lt: before };
		const newest = await this.archive
			.find(filter, { projection: HIDDEN })
			.sort({ timestamp: -1, id: -1 })
			.limit(limit)
			.toArray();
		return newest.reverse();
	}

	async archiveSearch(place, needle, limit) {
		const docs = await this.archive
			.find({ place, content: { $regex: escapeRegex(needle), $options: "i" } }, { projection: { _id: 0, place: 0 } })
			.sort({ timestamp: -1, id: -1 })
			.limit(limit)
			.toArray();
		return docs;
	}

	async profileGet(userId) {
		return profileOut(await this.profiles.findOne({ userId: Number(userId) }));
	}

	async profileUpdate(userId, set, increment) {
		const update = { $setOnInsert: { userId: Number(userId), firstSeen: Math.floor(Date.now() / 1000) } };
		if (Object.keys(set).length > 0) update.$set = set;
		const inc = {};
		for (const [stat, by] of Object.entries(increment)) inc[statField(stat)] = by;
		if (Object.keys(inc).length > 0) update.$inc = inc;
		try {
			return profileOut(
				await this.profiles.findOneAndUpdate({ userId: Number(userId) }, update, {
					upsert: true,
					returnDocument: "after",
				}),
			);
		} catch (error) {
			if (error.code === 11000) return this.profileUpdate(userId, set, increment);
			throw error;
		}
	}
}

module.exports = { MongoStore };
