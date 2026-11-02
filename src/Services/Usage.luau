--!strict
--[[
	Usage

	Counts how often each command and emoji is used, so autocomplete can list
	the most used first. Counts are per user (plugin settings), saved in
	batches and flushed when the plugin unloads.

	Usage:
		Usage.init()                        -- once, after Settings.init
		Usage.record("command", "help")
		Usage.getCount("emoji", "smile")    -- 0 if never used
]]

local Constants = require(script.Parent.Parent.Config.Constants)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local Settings = require(script.Parent.Parent.Core.Settings)

export type Category = "command" | "emoji"

local SAVE_DELAY = 1 -- seconds; batches rapid uses into one write

local Usage = {}

local counts: { [string]: { [string]: number } } = {
	command = {},
	emoji = {},
}
local saveQueued = false

local function save()
	saveQueued = false
	Settings.setJson(Constants.SETTING_KEY_USAGE, counts)
end

local function queueSave()
	if saveQueued then
		return
	end
	saveQueued = true
	Lifetime.delay(SAVE_DELAY, save)
end

--[=[
	Loads the saved counts and makes sure pending counts are saved on unload.
]=]
function Usage.init()
	local saved = Settings.getJson(Constants.SETTING_KEY_USAGE, {})
	-- Only accept well-formed numeric counts so corrupted data can't break sorting.
	if type(saved) == "table" then
		for category, entries in pairs(counts) do
			local bucket = saved[category]
			if type(bucket) == "table" then
				for key, value in pairs(bucket) do
					if type(key) == "string" and type(value) == "number" then
						entries[key] = value
					end
				end
			end
		end
	end

	Lifetime.add(function()
		if saveQueued then
			save()
		end
	end)
end

--[=[
	Records one use of a command (lowercase name) or emoji (name).
]=]
function Usage.record(category: Category, key: string)
	local bucket = counts[category]
	if not bucket then
		return
	end
	bucket[key] = (bucket[key] or 0) + 1
	queueSave()
end

--[=[
	How many times an entry has been used (0 if never).
]=]
function Usage.getCount(category: Category, key: string): number
	local bucket = counts[category]
	return if bucket then bucket[key] or 0 else 0
end

return Usage
