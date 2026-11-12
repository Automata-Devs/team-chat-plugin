--!strict
--[[
	Database

	The team database: Team Chat's own server (server/, docs/DATABASE.md),
	reached over HttpService. It keeps the team chat's history, everyone's
	profile and stats, and key/value collections for bots and commands,
	across places and computers.

	Parts:
	  Connection  the server's URL and token, saved in the place
	  Client      one request: JSON, token header, problems
	  Outbox      writes waiting for the server (survives closing Studio)
	  Cache       last answers, for reading while offline
	  Store       key/value collections
	  Archive     uploads the team chat; history and search
	  UserStats   profiles and stats

	Usage:
		Database.init(ChatNetwork)                  -- once, in App
		Database.connect("https://chat.example.com", token)
		Database.store("notes"):set("todo", { "lights" })
		Database.archive.search("lighting")
		Database.profiles.get(156)
]]

local DatabaseConfig = require(script.Parent.Parent.Config.Database)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local Archive = require(script.Archive)
local Cache = require(script.Cache)
local Client = require(script.Client)
local Connection = require(script.Connection)
local Outbox = require(script.Outbox)
local Store = require(script.Store)
local UserStats = require(script.UserStats)

export type Status = {
	connected: boolean,
	url: string?,
	online: boolean?,
	queued: number,
	pending: number,
}

local Database = {}

-- Fires with true/false when the server starts or stops answering
Database.statusChanged = Client.statusChanged

Database.archive = {
	history = Archive.history,
	search = Archive.search,
}

Database.profiles = {
	get = UserStats.get,
	sync = UserStats.sync,
}

Database.validName = Store.validName
Database.validUrl = Connection.validUrl

-- For the specs: a fake server instead of HttpService
Database._setTransport = Client.setTransport
Database._archive = Archive

local started = false

--[=[
	Sends everything waiting: archived messages, then queued writes, then my
	profile when `withProfile`. Returns how many items went out. Yields.
]=]
function Database.sync(withProfile: boolean?): (number, string?)
	if not Connection.get() then
		return 0, "notConnected"
	end
	local sent = Archive.flush()
	sent += Outbox.flush()
	if withProfile then
		local ok, problem = UserStats.sync()
		if not ok then
			return sent, problem
		end
	end
	return sent, if Client.online == false then "unreachable" else nil
end

local function loop()
	local lastProfile = -math.huge
	while Lifetime.alive do
		task.wait(if Client.online == false then DatabaseConfig.RETRY_EVERY else DatabaseConfig.FLUSH_EVERY)
		if not Lifetime.alive or not Connection.get() then
			continue
		end
		local profileDue = os.clock() - lastProfile >= DatabaseConfig.PROFILE_SYNC_EVERY
		Database.sync(profileDue)
		if profileDue then
			lastProfile = os.clock()
		end
	end
end

--[=[
	Starts archiving the team chat and the background uploads. `chat` is the
	Chat facade. Does nothing on the network until the place is connected.
]=]
function Database.init(chat: any)
	if started then
		return
	end
	started = true
	Archive.init(chat)
	Lifetime.add(task.spawn(loop))
end

--[=[
	True when the place is connected to a server.
]=]
function Database.isConnected(): boolean
	return Connection.get() ~= nil
end

--[=[
	Where things stand: connected, the server's URL, whether it answered last
	time (nil before the first request) and what's waiting to be sent.
]=]
function Database.status(): Status
	local info = Connection.get()
	return {
		connected = info ~= nil,
		url = if info then info.url else nil,
		online = Client.online,
		queued = Outbox.size(),
		pending = Archive.pendingCount(),
	}
end

--[=[
	Asks the server if it's up and the token is right. Returns true, or false
	and a problem. Yields.
]=]
function Database.ping(): (boolean, string?)
	local result = Client.request("GET", "/health")
	return result.problem == nil, result.problem
end

--[=[
	Connects the place to a server (everyone in Team Create uses it) and
	checks it. Returns false and "badUrl" for a URL that isn't https.
	Otherwise true, plus the ping's problem if the server didn't answer. Yields.
]=]
function Database.connect(url: string, token: string): (boolean, string?)
	if not Connection.set(url, token) then
		return false, "badUrl"
	end
	Client.online = nil
	local ok, problem = Database.ping()
	return true, if ok then nil else problem
end

--[=[
	Disconnects the place and forgets what was waiting or cached here.
]=]
function Database.disconnect()
	Connection.clear()
	Outbox.clear()
	Cache.forget()
	Archive.clear()
	Client.online = nil
end

--[=[
	A key/value collection (see Store). Errors on an invalid name.
]=]
function Database.store(collection: string): Store.Store
	return Store.new(collection)
end

return Database
