--!
-- VersionHistory
-- Versioned snapshots of the chat history for easy backup, restore, and
-- revert. Snapshots are stored in plugin settings: a JSON index per place
-- (SETTING_KEY_VERSIONS + PlaceId) plus one content key per version. The
-- newest versions are kept first and the list is capped at MAX_VERSIONS.
--!

local HttpService = game:GetService("HttpService")

local PluginConfig = require(script.Parent.Parent.Parent.Config.Constants)
local ChatState = require(script.Parent.ChatState)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)

local VersionHistory = {}

-- Each place has its own list of snapshots
local function indexKey(): string
	return Settings.placeKey(PluginConfig.SETTING_KEY_VERSIONS)
end
local CONTENT_KEY_PREFIX = PluginConfig.SETTING_KEY_VERSION_CONTENT_PREFIX
local MAX_VERSIONS = 20

--!
-- Loads the version index (array of version metadata, newest first).
--!
local function loadIndex(): { table }
	local versions = Settings.getJson(indexKey(), {})
	return if type(versions) == "table" then versions else {}
end

--!
-- Persists the version index.
--!
local function saveIndex(versions)
	Settings.setJson(indexKey(), versions)
end

--!
-- Creates a new version snapshot of the current chat history.
-- @param label Optional display label for the version.
-- @return The created version table { id, label, timestamp, author, messageCount }, or nil on failure.
--!
function VersionHistory.create(label: string?): table?
	local json = ChatState.serializeMessages()
	if not json then
		return nil
	end

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

	Settings.set(CONTENT_KEY_PREFIX .. version.id, json)

	local versions = loadIndex()
	table.insert(versions, 1, version)

	-- Prune the oldest versions beyond the cap
	while #versions > MAX_VERSIONS do
		local removed = table.remove(versions)
		Settings.set(CONTENT_KEY_PREFIX .. removed.id, nil)
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
	local version = VersionHistory.get(id)
	if not version then
		return false
	end

	local json = Settings.get(CONTENT_KEY_PREFIX .. id)
	if type(json) ~= "string" or json == "" then
		return false
	end

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
			Settings.set(CONTENT_KEY_PREFIX .. id, nil)
			saveIndex(versions)
			return true
		end
	end
	return false
end

return VersionHistory
