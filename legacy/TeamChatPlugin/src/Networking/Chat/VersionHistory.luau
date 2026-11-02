--!
-- VersionHistory
-- Versioned snapshots of the chat history for easy backup, restore, and
-- revert. Snapshots are stored in plugin settings: a JSON index per place
-- (SETTING_KEY_VERSIONS + PlaceId) plus one content key per version. The
-- newest versions are kept first and the list is capped at MAX_VERSIONS.
--!

local HttpService = game:GetService("HttpService")

local PluginConfig = require(script.Parent.Parent.Parent.Config.PluginConfig)
local ChatState = require(script.Parent.ChatState)
local PlaceStorage = require(script.Parent.Parent.PlaceStorage)

local VersionHistory = {}

-- Each place has its own list of snapshots
local function indexKey(): string
	return PlaceStorage.settingKey(PluginConfig.SETTING_KEY_VERSIONS)
end
local CONTENT_KEY_PREFIX = "TeamChatVersion_"
local MAX_VERSIONS = 20

local function getPlugin()
	return ChatState.pluginRef
end

--!
-- Loads the version index (array of version metadata, newest first).
--!
local function loadIndex(): { table }
	local plugin = getPlugin()
	if not plugin then return {} end
	local ok, json = pcall(function()
		return plugin:GetSetting(indexKey())
	end)
	if not ok or not json or json == "" then return {} end
	local okDecode, versions = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not okDecode or type(versions) ~= "table" then return {} end
	return versions
end

--!
-- Persists the version index.
--!
local function saveIndex(versions)
	local plugin = getPlugin()
	if not plugin then return end
	local ok, json = pcall(function()
		return HttpService:JSONEncode(versions)
	end)
	if ok and json then
		pcall(function()
			plugin:SetSetting(indexKey(), json)
		end)
	end
end

--!
-- Creates a new version snapshot of the current chat history.
-- @param label Optional display label for the version.
-- @return The created version table { id, label, timestamp, author, messageCount }, or nil on failure.
--!
function VersionHistory.create(label: string?): table?
	local plugin = getPlugin()
	if not plugin then return nil end

	local json = ChatState.serializeMessages()
	if not json then return nil end

	local messageCount = 0
	local okDecode, messages = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if okDecode and type(messages) == "table" then
		messageCount = #messages
	end

	local version = {
		id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
		label = label or "",
		timestamp = os.time(),
		author = ChatState.currentUsername,
		messageCount = messageCount,
	}

	pcall(function()
		plugin:SetSetting(CONTENT_KEY_PREFIX .. version.id, json)
	end)

	local versions = loadIndex()
	table.insert(versions, 1, version)

	-- Prune the oldest versions beyond the cap
	while #versions > MAX_VERSIONS do
		local removed = table.remove(versions)
		pcall(function()
			plugin:SetSetting(CONTENT_KEY_PREFIX .. removed.id, nil)
		end)
	end

	saveIndex(versions)
	return version
end

--!
-- Returns all saved versions, newest first.
--!
function VersionHistory.list(): { table }
	return loadIndex()
end

--!
-- Finds a single version by id.
--!
function VersionHistory.get(id: string): table?
	for _, version in ipairs(loadIndex()) do
		if version.id == id then
			return version
		end
	end
	return nil
end

--!
-- Restores the chat history from a saved version.
-- Replaces the current DataModel folder contents and persists the change.
-- @return true on success
--!
function VersionHistory.restore(id: string): boolean
	local plugin = getPlugin()
	if not plugin then return false end
	local version = VersionHistory.get(id)
	if not version then return false end

	local ok, json = pcall(function()
		return plugin:GetSetting(CONTENT_KEY_PREFIX .. id)
	end)
	if not ok or not json or json == "" then return false end

	return ChatState.applyHistory(json)
end

--!
-- Deletes a saved version snapshot.
-- @return true if a version was found and removed
--!
function VersionHistory.delete(id: string): boolean
	local versions = loadIndex()
	for i, version in ipairs(versions) do
		if version.id == id then
			table.remove(versions, i)
			local plugin = getPlugin()
			if plugin then
				pcall(function()
					plugin:SetSetting(CONTENT_KEY_PREFIX .. id, nil)
				end)
				saveIndex(versions)
			end
			return true
			end
	end
	return false
end

return VersionHistory