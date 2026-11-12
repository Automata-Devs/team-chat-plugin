--!strict
--[[
	Connection

	Which backend this place uses, saved in the place (TeamChatData.Backend)
	so everyone in Team Create uses the same one: the server's Url, and the
	place's WorkspaceId, ChannelId (the team chat) and Invite (how teammates
	join the workspace). Sign-ins are per person and never saved here.
]]

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local PlaceStorage = require(script.Parent.Parent.Parent.Core.PlaceStorage)

export type Info = { url: string, workspaceId: string?, channelId: string?, invite: string? }

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

--[=[
	True for an https URL, or http to this computer (for testing).
]=]
function Connection.validUrl(url: string): boolean
	return string.match(url, "^https://[%w%.%-]+") ~= nil
		or string.match(url, "^http://localhost[:/]?") ~= nil
		or string.match(url, "^http://127%.0%.0%.1[:/]?") ~= nil
end

--[=[
	The place's backend, or nil when it isn't connected.
]=]
function Connection.get(): Info?
	local config = folder(false)
	local url = config and text(config:GetAttribute("Url"))
	if not config or not url then
		return nil
	end
	return {
		url = url,
		workspaceId = text(config:GetAttribute("WorkspaceId")),
		channelId = text(config:GetAttribute("ChannelId")),
		invite = text(config:GetAttribute("Invite")),
	}
end

--[=[
	Points the place at a server. Moving to another server forgets the old
	workspace. Returns false for a URL that isn't https (or localhost).
]=]
function Connection.setUrl(url: string): boolean
	url = string.gsub(url, "/+$", "")
	if not Connection.validUrl(url) then
		return false
	end
	local config = folder(true) :: Folder
	if config:GetAttribute("Url") ~= url then
		for _, key in ipairs({ "WorkspaceId", "ChannelId", "Invite" }) do
			config:SetAttribute(key, nil)
		end
	end
	config:SetAttribute("Url", url)
	return true
end

function Connection.setWorkspace(workspaceId: string, channelId: string, invite: string)
	local config = folder(true) :: Folder
	config:SetAttribute("WorkspaceId", workspaceId)
	config:SetAttribute("ChannelId", channelId)
	config:SetAttribute("Invite", invite)
end

function Connection.clear()
	local config = folder(false)
	if config then
		config:Destroy()
	end
end

return Connection
