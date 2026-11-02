--!strict
--[[
	Settings

	The one place that talks to plugin:GetSetting/SetSetting. Every call is
	protected (settings can be unavailable, e.g. in a test or when Studio is
	shutting down), JSON values are encoded/decoded for you, and per-place keys
	get the PlaceId appended.

	Usage:
		Settings.init(plugin)                                   -- once, in App
		local theme = Settings.get(Constants.SETTING_KEY_THEME, "Auto")
		Settings.setJson(Settings.placeKey(Constants.SETTING_KEY_LAST_READ), lastRead)
]]

local HttpService = game:GetService("HttpService")

local Logger = require(script.Parent.Logger)
local PlaceStorage = require(script.Parent.PlaceStorage)

local log = Logger.scope("Settings")

local Settings = {}

local pluginRef: Plugin? = nil

-- True when nothing was saved before this session (a first install); set by App.
Settings.firstRun = false

--[=[
	Stores the plugin object used for every read and write.
]=]
function Settings.init(plugin: Plugin)
	pluginRef = plugin
end

--[=[
	Reads a setting; returns `default` when it's missing or can't be read.
]=]
function Settings.get(key: string, default: any?): any
	if not pluginRef then
		return default
	end
	local plugin = pluginRef :: Plugin
	local ok, value = pcall(function()
		return plugin:GetSetting(key)
	end)
	if not ok then
		log.warn("Couldn't read setting %s: %s", key, tostring(value))
		return default
	end
	if value == nil then
		return default
	end
	return value
end

--[=[
	Writes a setting (nil removes it). Returns false if it couldn't be saved.
]=]
function Settings.set(key: string, value: any?): boolean
	if not pluginRef then
		return false
	end
	local plugin = pluginRef :: Plugin
	local ok, err = pcall(function()
		plugin:SetSetting(key, value)
	end)
	if not ok then
		log.warn("Couldn't save setting %s: %s", key, tostring(err))
	end
	return ok
end

--[=[
	Reads a JSON-encoded setting; returns `default` when it's missing or not
	valid JSON.
]=]
function Settings.getJson(key: string, default: any?): any
	local raw = Settings.get(key)
	if type(raw) ~= "string" or raw == "" then
		return default
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok then
		log.warn("Setting %s isn't valid JSON; using the default", key)
		return default
	end
	return decoded
end

--[=[
	Writes a value as JSON. Returns false if it couldn't be encoded or saved.
]=]
function Settings.setJson(key: string, value: any): boolean
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, value)
	if not ok then
		log.warn("Couldn't encode setting %s: %s", key, tostring(encoded))
		return false
	end
	return Settings.set(key, encoded)
end

--[=[
	The per-place version of a key ("TeamChatHistory_v2" -> "TeamChatHistory_v2_107733...").
]=]
function Settings.placeKey(baseKey: string): string
	return PlaceStorage.settingKey(baseKey)
end

return Settings
