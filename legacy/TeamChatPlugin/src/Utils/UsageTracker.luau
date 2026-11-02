--!
-- UsageTracker
-- Tracks how often commands and emojis are used so autocomplete menus can
-- list the most used entries first. Counts are stored per user in plugin
-- settings (plugin:SetSetting), so every developer gets their own ordering.
--!

local HttpService = game:GetService("HttpService")

local PluginConfig = require(script.Parent.Parent.Config.PluginConfig)

local UsageTracker = {}

local SAVE_DELAY = 1 -- seconds; batches rapid successive writes into one save

local pluginRef: Plugin? = nil
local counts: { [string]: { [string]: number } } = {
	command = {},
	emoji = {},
}
local saveQueued = false

local function save()
	saveQueued = false
	if not pluginRef then
		return
	end
	local okEncode, json = pcall(function()
		return HttpService:JSONEncode(counts)
	end)
	if okEncode and json then
		pcall(function()
			(pluginRef :: Plugin):SetSetting(PluginConfig.SETTING_KEY_USAGE, json)
		end)
	end
end

local function queueSave()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(SAVE_DELAY, save)
end

--!
-- Loads previously saved counts. Call once at startup.
-- @param p Plugin - the plugin global
--!
function UsageTracker.init(p: Plugin)
	pluginRef = p

	local okGet, json = pcall(function()
		return p:GetSetting(PluginConfig.SETTING_KEY_USAGE)
	end)
	if not okGet or type(json) ~= "string" or json == "" then
		return
	end

	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not okDecode or type(decoded) ~= "table" then
		return
	end

	-- Only accept well-formed numeric counts so corrupted data can't break sorting.
	for category, entries in pairs(counts) do
		local saved = decoded[category]
		if type(saved) == "table" then
			for key, value in pairs(saved) do
				if type(key) == "string" and type(value) == "number" then
					entries[key] = value
				end
			end
		end
	end
end

--!
-- Records one use of an entry.
-- @param category string - "command" or "emoji"
-- @param key string - lowercase command name or emoji name
--!
function UsageTracker.record(category: string, key: string)
	local bucket = counts[category]
	if not bucket then
		return
	end
	bucket[key] = (bucket[key] or 0) + 1
	queueSave()
end

--!
-- Returns how many times an entry has been used (0 if never).
--!
function UsageTracker.getCount(category: string, key: string): number
	local bucket = counts[category]
	return bucket and bucket[key] or 0
end

return UsageTracker
