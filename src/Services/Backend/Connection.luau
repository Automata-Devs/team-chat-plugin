--!strict
--[[
	Connection

	Which backend this place uses, and its place on it, saved in the place
	(TeamChatData.Backend) so everyone in Team Create uses the same:

	  Url          the server; empty means BackendConfig.DEFAULT_URL
	  PlaceKey     how the backend knows this place: "place:<PlaceId>", or a
	               random "local:<id>" while the place is unpublished
	  PlaceSecret  proves to the backend that you can open this place (also kept
	               in your plugin settings, so a reverted place keeps its workspace)
	  WorkspaceId, ChannelId  the place's workspace and its team chat channel
	  Disabled     set by /backend disconnect: this place isn't stored

	Sign-ins are per person and never saved here.
]]

local HttpService = game:GetService("HttpService")

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local PlaceStorage = require(script.Parent.Parent.Parent.Core.PlaceStorage)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)

export type Info = { url: string, workspaceId: string?, channelId: string? }

local Connection = {}

local function folder(create: boolean): Folder?
	local root = PlaceStorage.getRoot()
	local existing = root:FindFirstChild(BackendConfig.FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if not create then
		return nil
	end
	local made = Instance.new("Folder")
	made.Name = BackendConfig.FOLDER_NAME
	made.Parent = root
	return made
end

local function text(value: any): string?
	return if type(value) == "string" and value ~= "" then value else nil
end

local function randomId(): string
	return (string.gsub(HttpService:GenerateGUID(false), "[^%w]", ""))
end

--[=[
	True for an https URL, or http to this computer (for testing).
]=]
function Connection.validUrl(url: string): boolean
	return string.match(url, "^https://[%w%.%-]+") ~= nil
		or string.match(url, "^http://localhost[:/]?") ~= nil
		or string.match(url, "^http://127%.0%.0%.1[:/]?") ~= nil
end

--[=[
	The place's backend: the place's own server, or the default one. nil when
	there's neither, or the place was disconnected.
]=]
function Connection.get(): Info?
	local config = folder(false)
	if config and config:GetAttribute("Disabled") == true then
		return nil
	end
	local url = (config and text(config:GetAttribute("Url"))) or text(BackendConfig.DEFAULT_URL)
	if not url or not Connection.validUrl(url) then
		return nil
	end
	return {
		url = (string.gsub(url, "/+$", "")),
		workspaceId = config and text(config:GetAttribute("WorkspaceId")),
		channelId = config and text(config:GetAttribute("ChannelId")),
	}
end

--[=[
	How the backend knows this place. Made (and saved in the place) the first
	time for an unpublished place.
]=]
function Connection.placeKey(): string
	if game.PlaceId ~= 0 then
		return "place:" .. tostring(game.PlaceId)
	end
	local config = folder(true) :: Folder
	local key = text(config:GetAttribute("PlaceKey"))
	if not key then
		key = "local:" .. randomId()
		config:SetAttribute("PlaceKey", key)
	end
	return key :: string
end

local function savedSecrets(): { [string]: string }
	local saved = Settings.getJson(BackendConfig.SETTING_KEY_PLACE_SECRETS, {})
	return if type(saved) == "table" then saved else {}
end

--[=[
	Keeps the secret that got me into the place's workspace on this computer.
]=]
function Connection.rememberSecret(secret: string)
	local saved = savedSecrets()
	if saved[Connection.placeKey()] ~= secret then
		saved[Connection.placeKey()] = secret
		Settings.setJson(BackendConfig.SETTING_KEY_PLACE_SECRETS, saved)
	end
end

--[=[
	The place's secret: the one saved in the place, else the one this computer
	remembers for it (a reverted place), else a new one. Saved in both.
]=]
function Connection.placeSecret(): string
	local config = folder(true) :: Folder
	local secret = text(config:GetAttribute("PlaceSecret"))
		or text(savedSecrets()[Connection.placeKey()])
		or (randomId() .. randomId())
	if config:GetAttribute("PlaceSecret") ~= secret then
		config:SetAttribute("PlaceSecret", secret)
	end
	return secret
end

--[=[
	The secret this computer remembers for the place, if any.
]=]
function Connection.rememberedSecret(): string?
	return text(savedSecrets()[Connection.placeKey()])
end

--[=[
	The secret in the place right now (a teammate may have just set it).
]=]
function Connection.placeSecretInPlace(): string?
	local config = folder(false)
	return config and text(config:GetAttribute("PlaceSecret"))
end

function Connection.setPlaceSecret(secret: string)
	(folder(true) :: Folder):SetAttribute("PlaceSecret", secret)
end

--[=[
	Points the place at another server than the default one. Moving to another
	server forgets the old workspace. Returns false for a URL that isn't https
	(or localhost).
]=]
function Connection.setUrl(url: string): boolean
	url = string.gsub(url, "/+$", "")
	if not Connection.validUrl(url) then
		return false
	end
	local config = folder(true) :: Folder
	local current = Connection.get()
	if not current or current.url ~= url then
		config:SetAttribute("WorkspaceId", nil)
		config:SetAttribute("ChannelId", nil)
	end
	config:SetAttribute("Url", url)
	config:SetAttribute("Disabled", nil)
	return true
end

function Connection.setWorkspace(workspaceId: string, channelId: string)
	local config = folder(true) :: Folder
	config:SetAttribute("WorkspaceId", workspaceId)
	config:SetAttribute("ChannelId", channelId)
end

--[=[
	Stops storing this place. Its key and secret stay, so connecting again finds
	the same workspace.
]=]
function Connection.disable()
	local config = folder(true) :: Folder
	config:SetAttribute("Url", nil)
	config:SetAttribute("WorkspaceId", nil)
	config:SetAttribute("ChannelId", nil)
	config:SetAttribute("Disabled", true)
end

return Connection
