--!strict
--[[
	Store

	A collection of keys and JSON values on the database server, for bots and
	commands. Writes that can't reach the server are queued (Outbox) and
	reads fall back to the last answer seen (Cache).

	Usage:
		local notes = Database.store("notes")
		notes:set("todo", { "lights", "doors" })
		local value, info = notes:get("todo")   -- info.stale when it came from the cache
		local items = notes:list("to")          -- { { key, value, updatedAt } }
		notes:delete("todo")
]]

local HttpService = game:GetService("HttpService")

local DatabaseConfig = require(script.Parent.Parent.Parent.Config.Database)
local Cache = require(script.Parent.Cache)
local Client = require(script.Parent.Client)
local Outbox = require(script.Parent.Outbox)

export type ReadInfo = { stale: boolean, problem: string? }
export type Item = { key: string, value: any, updatedAt: number? }
export type Store = {
	collection: string,
	get: (self: Store, key: string) -> (any, ReadInfo),
	set: (self: Store, key: string, value: any) -> (boolean, string?),
	delete: (self: Store, key: string) -> (boolean, string?),
	list: (self: Store, prefix: string?) -> ({ Item }, ReadInfo),
}

local Store = {}
Store.__index = Store

--[=[
	True for a collection or key the server accepts: letters, digits and
	_ - . : up to MAX_KEY_LENGTH.
]=]
function Store.validName(name: any): boolean
	return type(name) == "string"
		and #name > 0
		and #name <= DatabaseConfig.MAX_KEY_LENGTH
		and string.match(name, "^[%w_%-%.:]+$") ~= nil
end

--[=[
	The store for one collection. Errors on an invalid name.
]=]
function Store.new(collection: string): Store
	assert(Store.validName(collection), "Invalid database collection name: " .. tostring(collection))
	return setmetatable({ collection = collection }, Store) :: any
end

local function itemPath(self: Store, key: string): string
	return "/kv/" .. Client.escape(self.collection) .. "/" .. Client.escape(key)
end

-- Sends a write now; queues it when the server can't be reached
local function write(method: string, path: string, body: any?): (boolean, string?)
	local result = Client.request(method, path, body)
	if result.problem and result.retry then
		Outbox.push({ method = method, path = path, body = body })
		return true, "queued"
	end
	return result.problem == nil, result.problem
end

function Store.get(self: Store, key: string): (any, ReadInfo)
	if not Store.validName(key) then
		return nil, { stale = false, problem = "badKey" }
	end
	local path = itemPath(self, key)
	local result = Client.request("GET", path)
	if result.problem and string.sub(result.problem, 1, 3) == "404" then
		Cache.forget(path)
		return nil, { stale = false }
	end
	if result.problem then
		return Cache.get(path), { stale = true, problem = result.problem }
	end
	local value = if type(result.data) == "table" then result.data.value else nil
	Cache.put(path, value)
	return value, { stale = false }
end

function Store.set(self: Store, key: string, value: any): (boolean, string?)
	if not Store.validName(key) then
		return false, "badKey"
	end
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, { value = value })
	if not ok then
		return false, "badValue"
	end
	if #encoded > DatabaseConfig.MAX_VALUE_BYTES then
		return false, "tooLarge"
	end
	local path = itemPath(self, key)
	Cache.put(path, value)
	return write("PUT", path, { value = value })
end

function Store.delete(self: Store, key: string): (boolean, string?)
	if not Store.validName(key) then
		return false, "badKey"
	end
	local path = itemPath(self, key)
	Cache.forget(path)
	return write("DELETE", path, nil)
end

function Store.list(self: Store, prefix: string?): ({ Item }, ReadInfo)
	local path = "/kv/" .. Client.escape(self.collection)
	if prefix and prefix ~= "" then
		path ..= "?prefix=" .. Client.escape(prefix)
	end
	local result = Client.request("GET", path)
	if result.problem then
		return Cache.get(path) or {}, { stale = true, problem = result.problem }
	end
	local items = if type(result.data) == "table" and type(result.data.items) == "table" then result.data.items else {}
	Cache.put(path, items)
	return items, { stale = false }
end

return Store
