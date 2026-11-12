// Tests for the database server: npm test (or node --test test.js)

"use strict";

const assert = require("node:assert/strict");
const { after, before, test } = require("node:test");
const { createServer } = require("./server");

const TOKEN = "test-token-0123456789";
let server;
let base;

before(async () => {
	server = createServer({ token: TOKEN });
	await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
	base = `http://127.0.0.1:${server.address().port}/v1`;
});

after(() => new Promise((resolve) => server.close(resolve)));

async function call(method, path, body, token = TOKEN) {
	const response = await fetch(base + path, {
		method,
		headers: { "Content-Type": "application/json", "X-TeamChat-Token": token },
		body: body === undefined ? undefined : JSON.stringify(body),
	});
	return { status: response.status, data: await response.json() };
}

test("refuses a wrong token", async () => {
	const { status } = await call("GET", "/health", undefined, "wrong");
	assert.equal(status, 401);
});

test("health", async () => {
	const { status, data } = await call("GET", "/health");
	assert.equal(status, 200);
	assert.equal(data.ok, true);
});

test("key/value: put, get, list, version check, delete", async () => {
	assert.equal((await call("GET", "/kv/notes/todo")).status, 404);
	const put = await call("PUT", "/kv/notes/todo", { value: ["lights"] });
	assert.equal(put.data.version, 1);
	assert.deepEqual((await call("GET", "/kv/notes/todo")).data.value, ["lights"]);
	assert.equal((await call("PUT", "/kv/notes/todo", { value: 1, ifVersion: 5 })).status, 409);
	await call("PUT", "/kv/notes/other", { value: 2 });
	const list = await call("GET", "/kv/notes?prefix=to");
	assert.deepEqual(
		list.data.items.map((item) => item.key),
		["todo"],
	);
	assert.equal((await call("DELETE", "/kv/notes/todo")).data.deleted, true);
	assert.equal((await call("GET", "/kv/notes/todo")).status, 404);
});

test("refuses bad names and big values", async () => {
	assert.equal((await call("PUT", "/kv/bad%20name/a", { value: 1 })).status, 400);
	assert.equal((await call("PUT", "/kv/notes/big", { value: "x".repeat(70000) })).status, 413);
});

test("archive: upload replaces by id, history in order, search", async () => {
	const messages = [
		{ id: "msg_2", sender: "Ana", senderId: 1, timestamp: 200, content: "Lighting is done" },
		{ id: "msg_1", sender: "Bo", senderId: 2, timestamp: 100, content: "hello" },
	];
	assert.equal((await call("POST", "/archive/123/main", { messages })).data.stored, 2);
	await call("POST", "/archive/123/main", { messages: [{ ...messages[1], content: "hello again" }] });
	const history = await call("GET", "/archive/123/main?limit=10");
	assert.deepEqual(
		history.data.messages.map((m) => m.content),
		["hello again", "Lighting is done"],
	);
	assert.equal((await call("GET", "/archive/123/main?before=150")).data.messages.length, 1);
	const found = await call("GET", "/archive/123?q=LIGHT");
	assert.equal(found.data.messages.length, 1);
	assert.equal(found.data.messages[0].conversation, "main");
	assert.equal((await call("POST", "/archive/123/main", { messages: [{ id: "bad id" }] })).status, 400);
});

test("profiles: set fields and add up stats", async () => {
	assert.equal((await call("GET", "/profiles/156")).status, 404);
	await call("POST", "/profiles/156", { set: { username: "builderman" }, increment: { messagesSent: 2 } });
	const second = await call("POST", "/profiles/156", { set: {}, increment: { messagesSent: 3 } });
	assert.equal(second.data.username, "builderman");
	assert.equal(second.data.stats.messagesSent, 5);
	assert.ok(second.data.firstSeen > 0);
	assert.equal((await call("POST", "/profiles/abc", {})).status, 400);
});
