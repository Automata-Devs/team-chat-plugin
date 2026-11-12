--!strict
--[[
	Outbox

	Changes to stored messages (edits, deletes, reactions) that couldn't reach
	the backend yet, kept in plugin settings per place so they survive closing
	Studio, and sent in order when it answers again. (New messages need no
	outbox: any of mine that aren't stored yet are found again in the place.)
]]

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local Logger = require(script.Parent.Parent.Parent.Core.Logger)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)
local Client = require(script.Parent.Client)

export type Write = { method: string, path: string, body: any? }

local log = Logger.scope("Backend")

local Outbox = {}

local queue: { Write }? = nil
local flushing = false

local function key(): string
	return Settings.placeKey(BackendConfig.SETTING_KEY_OUTBOX)
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

function Outbox.push(write: Write)
	local list = load()
	table.insert(list, write)
	while #list > BackendConfig.OUTBOX_LIMIT do
		table.remove(list, 1)
	end
	save()
end

function Outbox.size(): number
	return #load()
end

--[=[
	Sends waiting changes in order. Stops at the first one that may work later;
	drops one the server refuses. Returns how many were sent. Yields.
]=]
function Outbox.flush(): number
	if flushing then
		return 0
	end
	flushing = true
	local sent = 0
	local list = load()
	while #list > 0 do
		local write = list[1]
		local result = Client.request(write.method, write.path, write.body)
		if result.problem and (result.retry or result.problem == "signedOut" or result.problem == "notConnected") then
			break
		end
		if result.problem and result.status ~= 404 then
			log.warn("The backend refused %s %s: %s", write.method, write.path, result.problem)
		end
		table.remove(list, 1)
		sent += 1
	end
	save()
	flushing = false
	return sent
end

function Outbox.clear()
	queue = {}
	save()
end

return Outbox
