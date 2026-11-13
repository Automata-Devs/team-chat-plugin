--!strict
--[[
	Backend

	Stores everything in the Team Chat backend (backend/, docs/backend),
	automatically and per place, like a Discord server: every place has its
	own workspace there, holding its team chat, DMs and groups. Each person's
	plugin stores what they write (messages, edits, deletes, reactions) under
	their own account. Chat still travels through the place in Team Create; the
	backend keeps it safe, outlives /clear and the place, and restores it.

	Everything stored is end-to-end encrypted (Seal): sealed in Studio with a
	key made from the place's secret, which the server never gets.

	Nothing needs setting up: with a server (BackendConfig.DEFAULT_URL, or the
	place's own), the plugin asks you once per computer to sign in with Roblox,
	then finds or makes the place's workspace by itself.

	Parts:
	  Connection  the server, the place's key and secret, its workspace (in the place)
	  Session     my sign-in, on this computer
	  Client      one request: JSON, my token, problems
	  Channels    conversation -> backend channel (DMs, groups)
	  Mirror      uploads my messages and changes
	  Outbox      changes waiting for the server (survives closing Studio)
	  Restore     brings the team chat back into the place
	  Seal        end-to-end encryption: seals what's stored, opens what's restored
]]

local BackendConfig = require(script.Parent.Parent.Config.Backend)
local ChatState = require(script.Parent.Chat.ChatState)
local Identity = require(script.Parent.Parent.Core.Identity)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local Logger = require(script.Parent.Parent.Core.Logger)
local Channels = require(script.Channels)
local Client = require(script.Client)
local Connection = require(script.Connection)
local Mirror = require(script.Mirror)
local Outbox = require(script.Outbox)
local Restore = require(script.Restore)
local Seal = require(script.Seal)
local Session = require(script.Session)

export type Status = {
	connected: boolean,
	url: string?,
	workspace: boolean,
	signedIn: boolean,
	username: string?,
	online: boolean?,
	waiting: number,
}

local log = Logger.scope("Backend")

local Backend = {}

Backend.validUrl = Connection.validUrl
Backend.restore = Restore.teamChat

-- For the specs
Backend._setTransport = Client.setTransport
Backend._mirror = Mirror
Backend._channels = Channels
Backend._connection = Connection
Backend._seal = Seal

local started = false
local signingIn = false
local askedThisSession = false
local joinedWorkspace: string? = nil -- the workspace this session is a member of
local joinRetryAt = 0 -- os.clock() before which a refused join isn't tried again
local lastJoinProblem: string? = nil -- warned about once, not on every retry
local noticeCallbacks: { (string) -> () } = {}

local function notice(text: string)
	for _, callback in ipairs(noticeCallbacks) do
		task.spawn(callback, text)
	end
end

--[=[
	Called with messages for me only (the sign-in link, problems): App shows
	them in the chat.
]=]
function Backend.onNotice(callback: (string) -> ())
	table.insert(noticeCallbacks, callback)
end

--[=[
	True when the place has a workspace and I'm signed in: what I write is stored.
]=]
function Backend.isActive(): boolean
	local info = Connection.get()
	return info ~= nil
		and info.channelId ~= nil
		and Session.get(info.url) ~= nil
		and joinedWorkspace == info.workspaceId
end

local function placeName(): string
	local name = string.gsub(game.Name, "%.rbxlx?$", "")
	return string.sub(if #name >= 2 then name else "Team Chat", 1, 100)
end

local function tryJoin(secret: string)
	-- Only a proof of the secret: the secret makes the encryption key, so it never leaves Studio
	return Client.request("POST", "/places/" .. Client.escape(Connection.placeKey()) .. "/workspace", {
		proof = Seal.proof(secret),
		name = placeName(),
	})
end

--[=[
	Joins the place's workspace, making it when nobody has yet. The secret is
	the place's, or the one this computer remembers when the place lost it; a
	teammate who made the workspace a moment ago is waited for. Yields.
]=]
function Backend.join(): (boolean, string?)
	local info = Connection.get()
	if not info then
		return false, "notConnected"
	end
	if not Session.get(info.url) then
		return false, "signedOut"
	end
	local secret = Connection.placeSecret()
	local result = tryJoin(secret)
	-- The place lost its secret (reverted, or a copy): this computer remembers the one that worked
	local remembered = Connection.rememberedSecret()
	if result.status == 403 and remembered and remembered ~= secret then
		secret = remembered
		result = tryJoin(secret)
		if not result.problem then
			Connection.setPlaceSecret(secret)
		end
	end
	-- A teammate made the workspace a moment ago: Team Create brings their secret over
	for _ = 1, BackendConfig.JOIN_ATTEMPTS do
		if result.status ~= 403 then
			break
		end
		task.wait(BackendConfig.JOIN_RETRY_EVERY)
		local candidate = Connection.placeSecretInPlace()
		if candidate and candidate ~= secret then
			secret = candidate
			result = tryJoin(secret)
		end
	end
	if result.problem then
		return false, result.problem
	end
	local workspaceId = result.data.workspace.id
	if info.workspaceId ~= workspaceId then
		Channels.forget()
	end
	Connection.setWorkspace(workspaceId, result.data.teamChatChannelId)
	Connection.rememberSecret(secret)
	Seal.use(secret)
	joinedWorkspace = workspaceId
	return true, nil
end

--[=[
	Stores what's waiting: my new messages, then waiting changes. Returns how
	many went out. Yields.
]=]
function Backend.sync(): (number, string?)
	if not Backend.isActive() then
		local info = Connection.get()
		if info and Session.get(info.url) then
			local ok, problem = Backend.join()
			if not ok then
				return 0, problem
			end
		else
			return 0, if not info then "notConnected" else "signedOut"
		end
	end
	Mirror.scan()
	local sent = Mirror.flush()
	sent += Outbox.flush()
	return sent, if Client.online == false then "unreachable" else nil
end

--[=[
	Signs me in with Roblox: `showUrl(url)` is called with the page to open in a
	browser, then this waits (up to 10 minutes) until I've approved there. The
	Roblox account must be the one signed in to Studio. Then joins the place's
	workspace (or makes it) and stores what I already wrote. Returns true, or
	false and a problem. Yields.
]=]
function Backend.signIn(showUrl: (string) -> ()): (boolean, string?)
	local info = Connection.get()
	if not info then
		return false, "notConnected"
	end
	if signingIn then
		return false, "alreadySigningIn"
	end
	signingIn = true
	local ok, problem = pcall(function()
		-- Signing in again starts fresh: with a session, start would link instead of sign in
		Session.clear(info.url)
		joinedWorkspace = nil
		local flow = Client.request("POST", "/auth/roblox/start", nil, true)
		if flow.problem then
			error(flow.problem, 0)
		end
		showUrl(flow.data.url)

		local deadline = os.clock() + BackendConfig.SIGN_IN_SECONDS
		local done: any = nil
		while os.clock() < deadline do
			task.wait(BackendConfig.POLL_EVERY)
			local poll = Client.request("POST", "/auth/roblox/poll", {
				loginId = flow.data.loginId,
				pollSecret = flow.data.pollSecret,
			}, true)
			if poll.problem then
				error(poll.problem, 0)
			end
			if poll.data.status == "failed" then
				error(poll.data.error or "failed", 0)
			elseif poll.data.status == "done" then
				done = poll.data
				break
			end
		end
		if not done then
			error("timedOut", 0)
		end

		Session.set(info.url, { token = done.token, userId = done.user.id, username = done.user.username })
		-- Only the Roblox account signed in to Studio may store messages as me
		local connections = Client.request("GET", "/auth/connections")
		local matches = false
		for _, account in ipairs(if connections.data then connections.data.connections or {} else {}) do
			if account.provider == "roblox" and account.providerUserId == tostring(Identity.userId) then
				matches = true
			end
		end
		if not matches then
			Client.request("POST", "/auth/logout")
			Session.clear(info.url)
			error("wrongAccount", 0)
		end

		local joined, joinProblem = Backend.join()
		if not joined then
			error(joinProblem or "noWorkspace", 0)
		end
	end)
	signingIn = false
	if ok then
		task.spawn(Backend.sync) -- store what I already wrote
		return true, nil
	end
	return false, tostring(problem)
end

-- Asks me (once per session) to sign in, with the link in the chat and the Output window
local function askToSignIn()
	askedThisSession = true
	task.spawn(function()
		local ok, problem = Backend.signIn(function(url)
			print("[Team Chat] Sign in with Roblox to keep this place's chat safe on the backend:\n" .. url)
			notice(
				"Team Chat stores this place's chat on your team's backend. Sign in once with Roblox: copy the link from the Output window (View > Output) into your browser and approve."
			)
		end)
		if ok then
			notice(
				"Signed in. Everything you write in this place is now stored on the backend, including what you wrote before."
			)
		elseif problem == "wrongAccount" then
			notice(
				"That Roblox account isn't the one signed in to Studio, so it wasn't used. Type /backend login to try again."
			)
		elseif problem ~= "timedOut" and problem ~= "alreadySigningIn" then
			log.warn("Signing in to the backend didn't work: %s", problem)
		end
	end)
end

--[=[
	One round of the background work: sign-in, joining the place, storing.
	Yields. (The specs call it directly.)
]=]
function Backend.tick(scan: boolean?)
	local info = Connection.get()
	if not info or Identity.userId <= 0 then
		return
	end
	if not Session.get(info.url) then
		if BackendConfig.AUTO_SIGN_IN and not askedThisSession and not signingIn then
			askToSignIn()
		end
		return
	end
	if joinedWorkspace == nil or joinedWorkspace ~= info.workspaceId then
		-- A refused join isn't retried every few seconds: that only hits the rate limit
		if os.clock() < joinRetryAt then
			return
		end
		local ok, problem = Backend.join()
		if not ok then
			joinRetryAt = os.clock() + BackendConfig.RETRY_EVERY
			if problem ~= "unreachable" and problem ~= lastJoinProblem then
				log.warn("Couldn't open this place's workspace on the backend: %s", tostring(problem))
			end
			lastJoinProblem = problem
			return
		end
		joinRetryAt = 0
		lastJoinProblem = nil
	end
	if scan then
		Mirror.scan()
	end
	Mirror.flush()
	Outbox.flush()
end

local function loop()
	local lastScan = -math.huge
	while Lifetime.alive do
		task.wait(if Client.online == false then BackendConfig.RETRY_EVERY else BackendConfig.FLUSH_EVERY)
		if not Lifetime.alive then
			break
		end
		local scan = os.clock() - lastScan >= BackendConfig.RESCAN_EVERY
		local ok, problem = pcall(Backend.tick, scan)
		if not ok then
			log.warn("Backend: %s", tostring(problem))
		elseif scan and Backend.isActive() then
			lastScan = os.clock()
		end
	end
end

function Backend.init(chat: any)
	if started then
		return
	end
	started = true
	Channels.init(chat.Conversations)
	Mirror.init(chat)
	ChatState.onDelete(Mirror.deleted)
	Lifetime.add(task.spawn(loop))
end

function Backend.status(): Status
	local info = Connection.get()
	local session = if info then Session.get(info.url) else nil
	return {
		connected = info ~= nil,
		url = if info then info.url else nil,
		workspace = info ~= nil and info.channelId ~= nil,
		signedIn = session ~= nil,
		username = if session then session.username else nil,
		online = Client.online,
		waiting = Mirror.pendingCount() + Outbox.size(),
	}
end

--[=[
	Uses another server than the default one for this place (admins). Returns
	false for a URL that isn't https (or localhost).
]=]
function Backend.connect(url: string): boolean
	if not Connection.setUrl(url) then
		return false
	end
	Client.online = nil
	joinedWorkspace = nil
	askedThisSession = false
	Channels.forget()
	return true
end

--[=[
	Stops storing this place. What's stored stays on the server, and connecting
	again finds the same workspace.
]=]
function Backend.disconnect()
	Connection.disable()
	Outbox.clear()
	Mirror.clear()
	Channels.forget()
	joinedWorkspace = nil
	Client.online = nil
end

function Backend.signOut()
	local info = Connection.get()
	if info and Session.get(info.url) then
		Client.request("POST", "/auth/logout")
		Session.clear(info.url)
	end
	joinedWorkspace = nil
end

return Backend
