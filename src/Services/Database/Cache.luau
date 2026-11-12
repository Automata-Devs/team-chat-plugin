--!strict
--[[
	Cache

	The last answer to each read, kept in plugin settings (per place), so
	reads still give something while the server can't be reached.
]]

local DatabaseConfig = require(script.Parent.Parent.Parent.Config.Database)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)

type Entry = { at: number, data: any }

local Cache = {}

local entries: { [string]: Entry }? = nil

local function key(): string
	return Settings.placeKey(DatabaseConfig.SETTING_KEY_CACHE)
end

local function load(): { [string]: Entry }
	if not entries then
		local saved = Settings.getJson(key(), {})
		entries = if type(saved) == "table" then saved else {}
	end
	return entries :: { [string]: Entry }
end

--[=[
	Remembers an answer; the oldest go past CACHE_LIMIT.
]=]
function Cache.put(path: string, data: any)
	local all = load()
	all[path] = { at = os.time(), data = data }
	local paths = {}
	for name in pairs(all) do
		table.insert(paths, name)
	end
	if #paths > DatabaseConfig.CACHE_LIMIT then
		table.sort(paths, function(a, b)
			return all[a].at < all[b].at
		end)
		for i = 1, #paths - DatabaseConfig.CACHE_LIMIT do
			all[paths[i]] = nil
		end
	end
	Settings.setJson(key(), all)
end

--[=[
	The last answer for a path and when it came (os.time), or nil.
]=]
function Cache.get(path: string): (any, number?)
	local entry = load()[path]
	if not entry then
		return nil, nil
	end
	return entry.data, entry.at
end

--[=[
	Forgets one path (after it was deleted) or everything.
]=]
function Cache.forget(path: string?)
	if path then
		load()[path] = nil
	else
		entries = {}
	end
	Settings.setJson(key(), load())
end

return Cache
