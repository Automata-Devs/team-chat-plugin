--!strict
--[[
	Backend

	Stores everything in the Team Chat backend (backend/, docs/backend): each
	person's plugin stores what they write (messages in the team chat, DMs and
	groups, edits, deletes, reactions) under their own account, after signing
	in with Roblox. The place stays how chat travels in Team Create; the
	backend keeps it safe, outlives /clear and the place, and restores it.

	Parts:
	  Connection  the server, workspace and team chat channel, saved in the place
	  Session     my sign-in, on this computer
	  Client      one request: JSON, my token, problems
	  Channels    conversation -> backend channel (DMs, groups)
	  Mirror      uploads my messages and changes
	  Outbox      changes waiting for the server (survives closing Studio)
	  Restore     brings the team chat back into the place

	Usage:
		Backend.init(ChatNetwork)                    -- once, in App
		Backend.connect("https://chat.example.com")  -- an admin, once per place
		Backend.signIn(function(url) ... end, true)  -- each person, once per computer
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

local started = false

--[=[
	True when the place has a workspace and I'm signed in: what I write is stored.
]=]
function Backend.isActive(): boolean
	local info = Connection.get()
	return info ~= nil and info.channelId ~= nil and Session.get(info.url) ~= nil
end

--[=[
	Stores what's waiting: my new messages, then waiting changes. Returns how
	many went out. Yields.
]=]
function Backend.sync(): (number, string?)
	if not Backend.isActive() then
		local info = Connection.get()
		return 0, if not info then "notConnected" elseif not Session.get(info.url) then "signedOut" else "noWorkspace"
	end
	Mirror.scan()
	local sent = Mirror.flush()
	sent += Outbox.flush()
	return sent, if Client.online == false then "unreachable" else nil
end

local function loop()
	local lastScan = -math.huge
	while Lifetime.alive do
		task.wait(if Client.online == false then BackendConfig.RETRY_EVERY else BackendConfig.FLUSH_EVERY)
		if not Lifetime.alive or not Backend.isActive() then
			continue
		end
		if os.clock() - lastScan >= BackendConfig.RESCAN_EVERY then
			Mirror.scan()
			lastScan = os.clock()
		end
		Mirror.flush()
		Outbox.flush()
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
	Points the place at a backend (an admin, once). Returns false for a URL
	that isn't https (or localhost).
]=]
function Backend.connect(url: string): boolean
	if not Connection.setUrl(url) then
		return false
	end
	Client.online = nil
	Channels.forget()
	return true
end

--[=[
	Stops using the backend in this place. What's stored stays on the server.
]=]
function Backend.disconnect()
	Connection.clear()
	Outbox.clear()
	Mirror.clear()
	Channels.forget()
	Client.online = nil
end

-- Joins the place's workspace, or (an admin) makes it: a workspace named
-- after the place, its #general as the team chat, and an invite for teammates
local function joinWorkspace(canCreate: boolean): (boolean, string?)
	local info = Connection.get()
	if not info then
		return false, "notConnected"
	end
	if info.workspaceId and info.invite then
		local joined = Client.request("POST", "/invites/" .. Client.escape(info.invite))
		return joined.problem == nil, joined.problem
	end
	if not canCreate then
		return false, "noWorkspace"
	end
	local name = string.sub(if #game.Name >= 2 then game.Name else "Team Chat", 1, 100)
	local made = Client.request("POST", "/workspaces", { name = name })
	if made.problem then
		return false, made.problem
	end
	local workspaceId = made.data.workspace.id
	local channels = Client.request("GET", "/workspaces/" .. workspaceId .. "/channels")
	local invite = Client.request("POST", "/workspaces/" .. workspaceId .. "/invites", {})
	if channels.problem or invite.problem then
		return false, channels.problem or invite.problem
	end
	local general = nil
	for _, channel in ipairs(channels.data.channels) do
		if channel.type == "text" then
			general = channel.id
			break
		end
	end
	if not general then
		return false, "noChannel"
	end
	Connection.setWorkspace(workspaceId, general, invite.data.invite.code)
	return true, nil
end

--[=[
	Signs me in with Roblox: `showUrl(url)` is called with the page to open in a
	browser, then this waits (up to 10 minutes) until I've approved there. The
	Roblox account must be the one signed in to Studio. Then joins the place's
	workspace, or makes it when `canCreate` (admins). Returns true, or false and
	a problem. Yields.
]=]
function Backend.signIn(showUrl: (string) -> (), canCreate: boolean): (boolean, string?)
	local info = Connection.get()
	if not info then
		return false, "notConnected"
	end
	-- Signing in again starts fresh: with a session, start would link instead of sign in
	Session.clear(info.url)
	local flow = Client.request("POST", "/auth/roblox/start", nil, true)
	if flow.problem then
		return false, flow.problem
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
			return false, poll.problem
		end
		if poll.data.status == "failed" then
			return false, poll.data.error or "failed"
		elseif poll.data.status == "done" then
			done = poll.data
			break
		end
	end
	if not done then
		return false, "timedOut"
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
		return false, "wrongAccount"
	end

	local ok, problem = joinWorkspace(canCreate)
	if ok then
		task.spawn(Backend.sync) -- store what I already wrote
	else
		log.warn("Signed in, but couldn't join the workspace: %s", tostring(problem))
	end
	return ok, problem
end

--[=[
	Joins the workspace (when an admin made it after I signed in). Yields.
]=]
function Backend.join(canCreate: boolean): (boolean, string?)
	return joinWorkspace(canCreate)
end

function Backend.signOut()
	local info = Connection.get()
	if info and Session.get(info.url) then
		Client.request("POST", "/auth/logout")
		Session.clear(info.url)
	end
end

return Backend
