--!strict
--[[
	Outbox

	Writes that couldn't reach the server yet, kept in plugin settings (per
	place) so they survive closing Studio, and sent in order when the server
	answers again.
]]

local DatabaseConfig = require(script.Parent.Parent.Parent.Config.Database)
local Logger = require(script.Parent.Parent.Parent.Core.Logger)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)
local Client = require(script.Parent.Client)

export type Write = { method: string, path: string, body: any? }

local log = Logger.scope("Database")

local Outbox = {}

local queue: { Write }? = nil
local flushing = false

local function key(): string
	return Settings.placeKey(DatabaseConfig.SETTING_KEY_OUTBOX)
end

local function load(): { Write }
	if not queue then
		local saved = Settings.getJson(key(), {})
		queue = if type(saved) == "table" then saved else {}
	end
	return queue :: { Write }
end

local function save()
	Settings.setJson(key(), load())
end

--[=[
	Queues a write. The oldest ones are dropped past OUTBOX_LIMIT.
]=]
function Outbox.push(write: Write)
	local writes = load()
	table.insert(writes, write)
	while #writes > DatabaseConfig.OUTBOX_LIMIT do
		table.remove(writes, 1)
	end
	save()
end

--[=[
	How many writes are waiting.
]=]
function Outbox.size(): number
	return #load()
end

--[=[
	Sends waiting writes in order. Stops at the first one that may work later;
	one the server refuses is dropped (and logged). Returns how many were sent. Yields.
]=]
function Outbox.flush(): number
	if flushing then
		return 0
	end
	flushing = true
	local writes = load()
	local sent = 0
	while #writes > 0 do
		local write = writes[1]
		local result = Client.request(write.method, write.path, write.body)
		if result.problem and result.retry then
			break
		end
		if result.problem then
			log.warn("The database refused a saved change (%s %s): %s", write.method, write.path, result.problem)
		else
			sent += 1
		end
		table.remove(writes, 1)
		save()
	end
	flushing = false
	return sent
end

--[=[
	Forgets every waiting write (after disconnecting from a server).
]=]
function Outbox.clear()
	queue = {}
	save()
end

return Outbox
