--!strict
--[[
	Connection

	Which server this place's database is on: the Url and Token attributes of
	TeamChatData.Database. They live in the place, so everyone in Team Create
	uses the same server, and only people who can edit the place can read the
	token.
]]

local DatabaseConfig = require(script.Parent.Parent.Parent.Config.Database)
local PlaceStorage = require(script.Parent.Parent.Parent.Core.PlaceStorage)

export type Info = { url: string, token: string }

local Connection = {}

local function folder(create: boolean): Folder?
	local root = PlaceStorage.getRoot()
	local existing = root:FindFirstChild(DatabaseConfig.FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if not create then
		return nil
	end
	local made = Instance.new("Folder")
	made.Name = DatabaseConfig.FOLDER_NAME
	made.Parent = root
	return made
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
	The server's URL (without a trailing /) and token, or nil when the place
	isn't connected.
]=]
function Connection.get(): Info?
	local config = folder(false)
	if not config then
		return nil
	end
	local url, token = config:GetAttribute("Url"), config:GetAttribute("Token")
	if type(url) ~= "string" or url == "" or type(token) ~= "string" or token == "" then
		return nil
	end
	return { url = url, token = token }
end

--[=[
	Connects the place to a server. Returns false for a URL that isn't https
	(or localhost) or an empty token.
]=]
function Connection.set(url: string, token: string): boolean
	url = string.gsub(url, "/+$", "")
	if not Connection.validUrl(url) or token == "" then
		return false
	end
	local config = folder(true) :: Folder
	config:SetAttribute("Url", url)
	config:SetAttribute("Token", token)
	return true
end

--[=[
	Disconnects the place: nothing is sent until it's connected again.
]=]
function Connection.clear()
	local config = folder(false)
	if config then
		config:Destroy()
	end
end

return Connection
