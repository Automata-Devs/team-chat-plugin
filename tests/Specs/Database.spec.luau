--[[
	The team database (Services/Database) against a fake server: connecting,
	key/value collections, the chat archive, profiles, working offline (the
	outbox and cache) and the /database command.
]]

local HttpService = game:GetService("HttpService")

local Harness = require(script.Parent.Parent.Harness)

local URL = "https://db.test"
local TOKEN = "spec-token-0123456789"

local function urlDecode(text: string): string
	return (string.gsub(string.gsub(text, "+", " "), "%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16) :: number)
	end))
end

-- A tiny in-memory version of server/server.js
local function fakeServer()
	local server = { kv = {}, archive = {}, profiles = {}, down = false, requests = 0, lastToken = nil }
	local function reply(status: number, body: any)
		return {
			Success = status < 300,
			StatusCode = status,
			StatusMessage = if status < 300 then "OK" else "Error",
			Body = HttpService:JSONEncode(body),
		}
	end
	function server.handle(request)
		if server.down then
			error("HttpError: ConnectFail")
		end
		server.requests += 1
		server.lastToken = request.Headers["X-TeamChat-Token"]
		local path, query = string.match(request.Url, "^https://db%.test/v1([^?]*)%??(.*)$")
		local parts = {}
		for part in string.gmatch(path or "", "[^/]+") do
			table.insert(parts, urlDecode(part))
		end
		local params = {}
		for key, value in string.gmatch(query or "", "([^&=]+)=([^&]*)") do
			params[key] = urlDecode(value)
		end
		local body = if request.Body then HttpService:JSONDecode(request.Body) else nil
		local method, area = request.Method, parts[1]
		if area == "health" then
			return reply(200, { ok = true })
		elseif area == "kv" then
			local collection = server.kv[parts[2]] or {}
			server.kv[parts[2]] = collection
			if #parts == 2 then
				local prefix = params.prefix or ""
				local items = {}
				for key, value in pairs(collection) do
					if string.sub(key, 1, #prefix) == prefix then
						table.insert(items, { key = key, value = value })
					end
				end
				return reply(200, { items = items })
			elseif method == "GET" then
				if collection[parts[3]] == nil then
					return reply(404, { error = "Not found" })
				end
				return reply(200, { key = parts[3], value = collection[parts[3]] })
			elseif method == "PUT" then
				if body.value == "refuse me" then
					return reply(400, { error = "Refused" })
				end
				collection[parts[3]] = body.value
				return reply(200, { key = parts[3], value = body.value })
			elseif method == "DELETE" then
				collection[parts[3]] = nil
				return reply(200, { deleted = true })
			end
		elseif area == "archive" then
			local place = server.archive[parts[2]] or {}
			server.archive[parts[2]] = place
			if #parts == 2 then
				local found = {}
				for conversation, messages in pairs(place) do
					for _, message in pairs(messages) do
						if string.find(string.lower(message.content), string.lower(params.q), 1, true) then
							message.conversation = conversation
							table.insert(found, message)
						end
					end
				end
				return reply(200, { messages = found })
			end
			local messages = place[parts[3]] or {}
			place[parts[3]] = messages
			if method == "POST" then
				for _, message in ipairs(body.messages) do
					messages[message.id] = message
				end
				return reply(200, { stored = #body.messages })
			end
			local list = {}
			for _, message in pairs(messages) do
				table.insert(list, message)
			end
			return reply(200, { messages = list })
		elseif area == "profiles" then
			local profile = server.profiles[parts[2]]
			if method == "GET" then
				return if profile then reply(200, profile) else reply(404, { error = "Not found" })
			end
			profile = profile or { userId = tonumber(parts[2]), stats = {} }
			for key, value in pairs(body.set or {}) do
				profile[key] = value
			end
			for stat, by in pairs(body.increment or {}) do
				profile.stats[stat] = (profile.stats[stat] or 0) + by
			end
			server.profiles[parts[2]] = profile
			return reply(200, profile)
		end
		return reply(404, { error = "No such route" })
	end
	return server
end

return function(t)
	local app = Harness.boot()
	local Database = require(app.copy.Services.Database) :: any
	local Identity = require(app.copy.Core.Identity) :: any
	local ok, err = pcall(function()
		local server = fakeServer()
		Database._setTransport(server.handle)

		-- Not connected: nothing is sent
		t.check("not connected at first", not Database.isConnected())
		local value, info = Database.store("notes"):get("todo")
		t.check("a read says it isn't connected", value == nil and info.problem == "notConnected")
		t.equal("no request was made", server.requests, 0)

		-- Connecting
		t.equal(
			"plain http to another computer is refused",
			select(2, Database.connect("http://db.test", TOKEN)),
			"badUrl"
		)
		local connected, problem = Database.connect(URL .. "/", TOKEN)
		t.check("connects and pings: " .. tostring(problem), connected and problem == nil)
		t.equal("the trailing / is dropped", Database.status().url, URL)
		t.equal("the token is sent", server.lastToken, TOKEN)
		t.equal("the server is online", Database.status().online, true)

		-- Key/value collections
		local notes = Database.store("notes")
		t.check("set", (notes:set("todo", { "lights", "doors" })))
		local todo = notes:get("todo")
		t.equal("get gives the value back", todo and todo[2], "doors")
		notes:set("other", 1)
		t.equal("list filters by prefix", #notes:list("to"), 1)
		t.check("delete", (notes:delete("other")))
		t.equal("...and it is gone", server.kv.notes.other, nil)
		t.equal("bad keys are refused", select(2, notes:set("bad key", 1)), "badKey")
		t.check("bad collections error", not pcall(Database.store, "bad name"))
		t.equal("big values are refused", select(2, notes:set("big", string.rep("x", 70000))), "tooLarge")

		-- The archive: my team chat messages are uploaded, once
		local Archive = Database._archive
		app.chat.sendMessage("hello archive")
		for _ = 1, 40 do
			if Archive.pendingCount() > 0 then
				break
			end
			task.wait(0.05)
		end
		t.check("my message waits to be archived", Archive.pendingCount() >= 1)
		local before = Archive.pendingCount()
		local someoneElse = Instance.new("Folder")
		someoneElse:SetAttribute("SenderId", Identity.userId + 1)
		Archive.consider("main", someoneElse)
		t.equal("someone else's message is left to them", Archive.pendingCount(), before)
		local dm = Instance.new("Folder")
		dm:SetAttribute("SenderId", Identity.userId)
		Archive.consider("dm_1_2", dm)
		t.equal("DMs are not archived", Archive.pendingCount(), before)
		Database.sync(false)
		t.equal("nothing waits after a sync", Archive.pendingCount(), 0)
		local found = Database.archive.search("HELLO ARCHIVE")
		t.check("the archive finds it", found and #found >= 1 and found[1].content == "hello archive")

		-- Profiles
		t.check("my profile syncs", (Database.profiles.sync()))
		if Identity.userId > 0 then
			local profile = Database.profiles.get(Identity.userId)
			t.check("...with the messages I sent", profile and (profile.stats.messagesSent or 0) >= 1)
			t.equal("...counted once", Archive.sentSinceSync, 0)
		end

		-- Offline: writes wait, reads use the cache
		server.down = true
		local queuedOk, queued = notes:set("offline", "later")
		t.check("a write while offline is queued", queuedOk and queued == "queued")
		t.equal("...and counted", Database.status().queued, 1)
		t.equal("the server is marked offline", Database.status().online, false)
		local cached, cachedInfo = notes:get("todo")
		t.check("reads fall back to the cache", cached and cached[1] == "lights" and cachedInfo.stale)
		server.down = false
		Database.sync(false)
		t.equal("the queued write is sent when it is back", server.kv.notes.offline, "later")
		t.equal("...and the queue is empty", Database.status().queued, 0)

		-- A write the server refuses is not retried forever
		server.down = true
		notes:set("refused", "refuse me")
		server.down = false
		Database.sync(false)
		t.equal("a refused write leaves the queue", Database.status().queued, 0)

		-- The command
		local said, embed = "", nil
		local ctx = {
			addSystemMessage = function(text)
				said = text
			end,
			addEmbed = function(spec)
				embed = spec
			end,
		}
		app.commands.tryParse("/database status", ctx)
		t.check("/database status shows a card", embed and embed.fields and embed.fields[1].value == URL)
		embed = nil
		app.commands.tryParse("/db search hello", ctx)
		t.check("/db search shows what it found", embed and #embed.fields >= 1)
		app.commands.tryParse("/database search", ctx)
		t.check("search needs text: " .. said, string.find(said, "/database search", 1, true) ~= nil)

		-- Disconnecting
		Database.disconnect()
		t.check("disconnected", not Database.isConnected())
		local requests = server.requests
		app.commands.tryParse("/database status", ctx)
		t.check("status says it is not connected: " .. said, string.find(said, "connect", 1, true) ~= nil)
		t.equal("...without a request", server.requests, requests)
	end)
	Database.disconnect()
	Database._setTransport(nil)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
