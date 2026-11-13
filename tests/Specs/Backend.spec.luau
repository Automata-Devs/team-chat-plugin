--[[
	Storing everything on the Team Chat backend (Services/Backend) against a
	fake backend: signing in with Roblox (and refusing another account), the
	place's own workspace made by itself (and found again with the secret this
	computer remembers), mirroring messages once, edits, reactions, deletes,
	working offline, DMs in the place's workspace that wait for a teammate,
	/clear keeping what's stored, restoring, signing in without a command, and
	the /backend command.
]]

local HttpService = game:GetService("HttpService")

local Harness = require(script.Parent.Parent.Harness)

local URL = "https://chat.test"

local function urlDecode(text: string): string
	return (
		string.gsub(string.gsub(text, "+", " "), "%%(%x%x)", function(hex)
			return string.char(tonumber(hex, 16) :: number)
		end)
	)
end

-- Just enough of backend/ for the plugin
local function fakeBackend(robloxId: number)
	local server = {
		robloxId = robloxId,
		down = false,
		channels = {} :: { [string]: { any } },
		accounts = {} :: { [string]: string },
		reactions = {} :: { [string]: boolean },
		polls = 0,
		places = {} :: { [string]: string }, -- place key -> its secret
		lastConversation = nil :: any,
		lastAuth = nil :: string?,
		nextId = 1000,
	}
	local function reply(status: number, body: any)
		return {
			Success = status < 300,
			StatusCode = status,
			StatusMessage = if status < 300 then "OK" else "Error",
			Body = if body == nil then "" else HttpService:JSONEncode(body),
		}
	end
	local function newId(): string
		server.nextId += 1
		return tostring(server.nextId)
	end
	local function find(channel: string, id: string)
		for _, message in ipairs(server.channels[channel] or {}) do
			if message.id == id then
				return message
			end
		end
		return nil
	end
	function server.handle(request)
		if server.down then
			error("HttpError: ConnectFail")
		end
		server.lastAuth = request.Headers.Authorization
		local path, query = string.match(request.Url, "^https://chat%.test/api/v1([^?]*)%??(.*)$")
		local p = {}
		for part in string.gmatch(path or "", "[^/]+") do
			table.insert(p, urlDecode(part))
		end
		local params = {}
		for key, value in string.gmatch(query or "", "([^&=]+)=([^&]*)") do
			params[key] = urlDecode(value)
		end
		local body = if request.Body and request.Body ~= "" then HttpService:JSONDecode(request.Body) else nil
		local m = request.Method

		if p[1] == "auth" and p[3] == "start" then
			return reply(
				200,
				{ loginId = "login-1", pollSecret = "secret-1", url = "https://roblox.test/authorize?x=1" }
			)
		elseif p[1] == "auth" and p[3] == "poll" then
			server.polls += 1
			if server.polls % 2 == 1 then
				return reply(202, { status = "pending" })
			end
			return reply(
				200,
				{ status = "done", token = "token-" .. server.polls, user = { id = "u1", username = "builder" } }
			)
		elseif p[1] == "auth" and p[2] == "connections" then
			return reply(200, { connections = { { provider = "roblox", providerUserId = tostring(server.robloxId) } } })
		elseif p[1] == "auth" and p[2] == "logout" then
			return reply(204, nil)
		elseif p[1] == "places" and p[3] == "workspace" then
			local created = server.places[p[2]] == nil
			if created then
				server.places[p[2]] = body.secret
			elseif server.places[p[2]] ~= body.secret then
				return reply(403, { error = { message = "That isn't this place's secret" } })
			end
			return reply(
				200,
				{ workspace = { id = "w1", name = body.name }, teamChatChannelId = "c1", created = created }
			)
		elseif p[1] == "workspaces" and p[3] == "members" and p[4] == "roblox" then
			local account = server.accounts[p[5]]
			return if account
				then reply(200, { user = { id = account } })
				else reply(404, { error = { message = "Member not found" } })
		elseif p[1] == "conversations" and m == "POST" then
			server.lastConversation = body
			return reply(201, { conversation = { id = "dm-" .. table.concat(body.recipients, "-") } })
		elseif p[1] == "channels" and p[3] == "messages" and p[4] == "batch" then
			local list = server.channels[p[2]] or {}
			server.channels[p[2]] = list
			local out = {}
			for _, item in ipairs(body.messages) do
				local existing = nil
				for _, message in ipairs(list) do
					if message.nonce == item.nonce then
						existing = message
					end
				end
				if existing then
					table.insert(out, { nonce = item.nonce, id = existing.id, created = false })
				else
					local message = {
						id = newId(),
						nonce = item.nonce,
						content = item.content,
						type = "default",
						flags = item.flags,
						metadata = { client = item.clientData },
						author = { id = "u1", username = "builder" },
					}
					table.insert(list, message)
					table.insert(out, { nonce = item.nonce, id = message.id, created = true })
				end
			end
			return reply(200, { messages = out })
		elseif p[1] == "channels" and p[3] == "messages" and #p == 3 and m == "GET" then
			local page = {}
			local list = server.channels[p[2]] or {}
			for index = #list, 1, -1 do
				local message = list[index]
				if not message.deleted and (not params.before or tonumber(message.id) < tonumber(params.before)) then
					table.insert(page, message)
				end
				if #page >= tonumber(params.limit or 50) then
					break
				end
			end
			return reply(200, { messages = page })
		elseif p[1] == "channels" and p[3] == "messages" and p[5] == "reactions" then
			server.reactions[p[4] .. ":" .. p[6]] = m == "PUT"
			return reply(204, nil)
		elseif p[1] == "channels" and p[3] == "messages" and #p == 4 then
			local message = find(p[2], p[4])
			if not message then
				return reply(404, { error = { message = "Message not found" } })
			end
			if m == "PATCH" then
				message.content = body.content
				message.metadata = { client = body.clientData }
			elseif m == "DELETE" then
				message.deleted = true
			end
			return reply(if m == "DELETE" then 204 else 200, { message = message })
		end
		return reply(404, { error = { message = "No such endpoint " .. m .. " " .. tostring(path) } })
	end
	return server
end

local function waitFor(condition: () -> boolean, seconds: number?): boolean
	local deadline = os.clock() + (seconds or 3)
	while os.clock() < deadline do
		if condition() then
			return true
		end
		task.wait(0.05)
	end
	return condition()
end

return function(t)
	local app = Harness.boot()
	local Backend = require(app.copy.Services.Backend) :: any
	local Identity = require(app.copy.Core.Identity) :: any
	local ChatState = require(app.copy.Services.Chat.ChatState) :: any
	local Conversations = require(app.copy.Services.Chat.Conversations) :: any
	local BackendConfig = require(app.copy.Config.Backend) :: any
	-- The app's own background loop would start a sign-in by itself: tested at the end
	BackendConfig.AUTO_SIGN_IN = false
	local ok, err = pcall(function()
		local me = Identity.userId
		local server = fakeBackend(me + 1) -- another Roblox account first
		Backend._setTransport(server.handle)

		t.check("not connected at first", not Backend.status().connected)
		t.equal("sync says so", select(2, Backend.sync()), "notConnected")
		t.check("plain http elsewhere is refused", not Backend.connect("http://chat.test"))
		t.check("connects", Backend.connect(URL .. "/"))
		t.equal("the trailing / is dropped", Backend.status().url, URL)
		t.equal("not signed in yet", select(2, Backend.sync()), "signedOut")

		-- Signing in with a Roblox account that isn't Studio's is undone
		local shown = nil
		local signedIn, problem = Backend.signIn(function(url)
			shown = url
		end)
		t.check("another Roblox account is refused", not signedIn and problem == "wrongAccount")
		t.equal("the sign-in page was shown", shown, "https://roblox.test/authorize?x=1")
		t.check("...and nothing is kept", not Backend.status().signedIn)

		-- The right account: the place's workspace is made by itself, no admin needed
		server.robloxId = me
		signedIn, problem = Backend.signIn(function() end)
		t.check("signs in: " .. tostring(problem), signedIn)
		local status = Backend.status()
		t.check("signed in and set up", status.signedIn and status.workspace and status.username == "builder")
		local Connection = Backend._connection
		local placeKey = Connection.placeKey()
		local secret = Connection.placeSecretInPlace()
		t.check(
			"the place has its own key: " .. placeKey,
			string.match(placeKey, "^place:%d+$") ~= nil or string.match(placeKey, "^local:%w+$") ~= nil
		)
		t.check("its workspace was made with the place's secret", secret ~= nil and server.places[placeKey] == secret)
		t.equal("...and this computer remembers it", Connection.rememberedSecret(), secret)
		t.check("requests carry the token", server.lastAuth ~= nil and string.sub(server.lastAuth, 1, 7) == "Bearer ")

		-- My messages are stored, once, with the plugin's own fields
		app.chat.sendMessage("stored safely")
		local folder = ChatState.getFolder()
		local mine = nil
		waitFor(function()
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("Content") == "stored safely" then
					mine = child
				end
			end
			return mine ~= nil
		end)
		Backend.sync()
		local stored = server.channels.c1 and server.channels.c1[#server.channels.c1]
		t.check("it reaches the team chat channel", stored and stored.content == "stored safely")
		t.equal("its nonce is the message's name", stored and stored.nonce, mine and mine.Name)
		t.equal("its sender is in the client data", stored and stored.metadata.client.senderId, me)
		t.equal("the backend's id is kept on it", mine and mine:GetAttribute("BackendId"), stored and stored.id)
		local count = #server.channels.c1
		Backend.sync()
		t.equal("syncing again stores nothing twice", #server.channels.c1, count)

		local theirs = Instance.new("Folder")
		theirs.Name = "msg_someone_else"
		theirs:SetAttribute("SenderId", me + 7)
		theirs:SetAttribute("Content", "not mine to store")
		theirs:SetAttribute("Timestamp", os.time())
		theirs.Parent = folder
		task.wait(0.1)
		Backend.sync()
		t.equal("someone else's message is left to their own plugin", #server.channels.c1, count)

		-- Edits, reactions and deletes follow
		app.chat.editMessage(mine:GetAttribute("Timestamp"), "edited text")
		task.wait(0.1) -- Studio fires attribute changes deferred
		Backend.sync()
		t.equal("an edit is stored", stored.content, "edited text")
		mine:SetAttribute("Reactions", HttpService:JSONEncode({ { e = "👍", u = { me }, n = { "me" } } }))
		task.wait(0.1)
		Backend.sync()
		t.check("my reaction is stored", server.reactions[stored.id .. ":👍"] == true)
		mine:SetAttribute("Reactions", "[]")
		task.wait(0.1)
		Backend.sync()
		t.check("...and its removal", server.reactions[stored.id .. ":👍"] == false)

		-- Offline: it waits, then goes
		server.down = true
		app.chat.sendMessage("written offline")
		task.wait(0.1)
		Backend.sync()
		t.check("waits while the backend is down", Backend.status().waiting >= 1)
		server.down = false
		Backend.sync()
		t.equal("is stored when it's back", server.channels.c1[#server.channels.c1].content, "written offline")

		-- A DM waits until the other person has signed in
		local other = me + 5
		local dmId = Conversations.dmId(me, other)
		local dmFolder = Conversations.getFolder(dmId, true)
		local dmMessage = Instance.new("Folder")
		dmMessage.Name = "msg_dm_1"
		dmMessage:SetAttribute("SenderId", me)
		dmMessage:SetAttribute("Sender", "me")
		dmMessage:SetAttribute("Content", "just between us")
		dmMessage:SetAttribute("Timestamp", os.time())
		dmMessage.Parent = dmFolder
		task.wait(0.1)
		Backend._mirror.consider(dmId, dmMessage)
		Backend.sync()
		t.check("waits for a teammate without an account", dmMessage:GetAttribute("BackendId") == nil)
		server.accounts[tostring(other)] = "u2"
		Backend._channels.forget() -- instead of waiting 5 minutes to ask again
		Backend.sync()
		local dm = server.channels["dm-u2"]
		t.equal(
			"the DM is made in the place's workspace",
			server.lastConversation and server.lastConversation.workspaceId,
			"w1"
		)
		t.check(
			"is stored in their DM once they have one",
			dm ~= nil and dm[1] ~= nil and dm[1].content == "just between us"
		)

		-- /clear keeps what's stored; restore brings it back
		local name = mine.Name
		ChatState.clearFolder()
		Backend.sync()
		t.check("clearing the place deletes nothing stored", not stored.deleted)
		local restored, restoreProblem = Backend.restore()
		t.check("restores the team chat: " .. tostring(restoreProblem), (restored or 0) >= 2)
		local back = folder:FindFirstChild(name)
		t.check("...with the original name", back ~= nil)
		t.equal("...and text", back and back:GetAttribute("Content"), "edited text")
		t.equal("...and sender", back and back:GetAttribute("SenderId"), me)
		t.equal("...and nothing twice", (Backend.restore()), 0)
		count = #server.channels.c1
		Backend.sync()
		t.equal("restored messages aren't stored again", #server.channels.c1, count)

		-- Deleting my own message deletes it there too
		-- (deletes go by timestamp, and the two messages can share a second)
		back:SetAttribute("Timestamp", 1234567)
		ChatState.deleteMessage(1234567)
		task.wait(0.1)
		Backend.sync()
		t.check("my delete is stored", stored.deleted == true)

		-- A reverted place lost its secret: the one this computer remembers gets back in
		Connection.setPlaceSecret("not-the-secret-" .. string.rep("x", 40))
		local rejoined, rejoinProblem = Backend.join()
		t.check("rejoins with the remembered secret: " .. tostring(rejoinProblem), rejoined)
		t.equal("...and puts it back in the place", Connection.placeSecretInPlace(), secret)

		-- Signing in needs no command: the plugin asks by itself, once
		Backend.signOut()
		BackendConfig.AUTO_SIGN_IN = true
		local notices = {}
		Backend.onNotice(function(text)
			table.insert(notices, text)
		end)
		Backend.tick()
		local signedInAgain = waitFor(function()
			return Backend.status().signedIn
		end, 10)
		t.check("asks to sign in by itself", #notices >= 1 and string.find(notices[1], "Sign in once", 1, true) ~= nil)
		t.check("...and is signed in once approved", signedInAgain)
		waitFor(function()
			return Backend.isActive()
		end, 5)
		t.check("...back in the place's workspace", Backend.isActive())

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
		app.commands.tryParse("/backend status", ctx)
		t.check("/backend status shows a card", embed and embed.fields and embed.fields[1].value == URL)
		app.commands.tryParse("/backend nonsense", ctx)
		t.check("unknown actions show the usage", string.find(said, "/backend status", 1, true) ~= nil)

		Backend.signOut()
		t.check("signed out", not Backend.status().signedIn)
	end)
	Backend.disconnect()
	Backend._setTransport(nil)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
