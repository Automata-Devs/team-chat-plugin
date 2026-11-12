--[[
	PlaceStorage

	Where the plugin keeps data that belongs to the open place.

	Shared data (chat messages, typing status, studio waypoints/claims) lives in
	a folder in ServerStorage. Team Create syncs ServerStorage to every
	collaborator and saves it with the place, so each place keeps its own chat
	and everyone sees the same history. ServerStorage is never replicated to
	players in a live game.

	Local backups go in plugin settings under per-place keys (settingKey).
]]

local ServerStorage = game:GetService("ServerStorage")

local PluginConfig = require(script.Parent.Parent.Config.Constants)

local PlaceStorage = {}

local root: Folder? = nil

--[=[
	Returns (creating it if needed) ServerStorage.TeamChatData.
]=]
function PlaceStorage.getRoot(): Folder
	if root and root.Parent == ServerStorage then
		return root
	end

	local existing = ServerStorage:FindFirstChild(PluginConfig.PLACE_DATA_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		root = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = PluginConfig.PLACE_DATA_FOLDER_NAME
	folder.Parent = ServerStorage
	root = folder
	return folder
end

--[=[
	Returns (creating it if needed) a named subfolder of the place data root.
]=]
function PlaceStorage.getFolder(name: string): Folder
	local parent = PlaceStorage.getRoot()
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

--[=[
	Identifies the open place for per-place plugin settings.
	Unpublished places all have PlaceId 0, so they share one "unpublished" slot.
]=]
function PlaceStorage.placeKey(): string
	return if game.PlaceId ~= 0 then tostring(game.PlaceId) else "unpublished"
end

--[=[
	Per-place version of a plugin setting key, e.g. "TeamChatHistory_v2_1077...".
]=]
function PlaceStorage.settingKey(baseKey: string): string
	return baseKey .. "_" .. PlaceStorage.placeKey()
end

return PlaceStorage
