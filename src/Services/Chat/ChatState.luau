--!
-- ChatState
-- Shared state module for the chat subsystem.
-- Holds the chat folder reference, current user info, plugin reference,
-- and provides message serialization / deserialization for persistence.
--
-- Persistence: the chat folder lives in the place (see PlaceStorage), so it
-- is shared over Team Create and saved with the place. A per-place backup in
-- plugin settings restores it if the place's copy is missing.
--!

local HttpService = game:GetService("HttpService")

local PluginConfig = require(script.Parent.Parent.Parent.Config.Constants)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local PlaceStorage = require(script.Parent.Parent.Parent.Core.PlaceStorage)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)

local ChatState = {}

-- Constants
ChatState.MESSAGE_TYPE_TEXT = "Text"
ChatState.MESSAGE_TYPE_POLL = "Poll"
ChatState.MESSAGE_TYPE_FILE = "File"

local CHAT_FOLDER_NAME = PluginConfig.CHAT_FOLDER_NAME

-- Shared state (the current user is copied from Core/Identity in init)
ChatState.chatFolder = nil
ChatState.currentUsername = "Unknown"
ChatState.currentUserId = 0

--!
-- Finds or creates the chat messages folder in the place
-- (ServerStorage.TeamChatData._TeamChatData).
--!
function ChatState.getFolder(): Folder
	if ChatState.chatFolder and ChatState.chatFolder.Parent then
		return ChatState.chatFolder
	end

	local folder = PlaceStorage.getFolder(CHAT_FOLDER_NAME)
	ChatState.chatFolder = folder
	return folder
end

-- Returns the folder of the conversation new messages go to: the team chat,
-- or a direct-message folder once Conversations sets the resolver.
ChatState.activeFolderResolver = nil :: (() -> Folder)?

function ChatState.getActiveFolder(): Folder
	if ChatState.activeFolderResolver then
		return ChatState.activeFolderResolver()
	end
	return ChatState.getFolder()
end

--!
-- Plugin setting key holding this place's local chat backup.
--!
local function historySettingKey(): string
	return PlaceStorage.settingKey(PluginConfig.SETTING_KEY_HISTORY)
end

local getSetting = Settings.get
local setSetting = Settings.set

--!
-- One-time import of pre-0.4 data, which was stored in plugin settings shared
-- by every place. It goes to the first place opened after updating (so it is
-- not copied into every place), along with its version-history index.
-- @return the legacy history JSON, or nil if it was already imported / absent
--!
local function takeLegacyHistory(): string?
	if getSetting(PluginConfig.SETTING_KEY_LEGACY_MIGRATED) then
		return nil
	end
	setSetting(PluginConfig.SETTING_KEY_LEGACY_MIGRATED, PlaceStorage.placeKey())

	local legacyVersions = getSetting(PluginConfig.SETTING_KEY_VERSIONS_LEGACY)
	local versionsKey = PlaceStorage.settingKey(PluginConfig.SETTING_KEY_VERSIONS)
	if legacyVersions and legacyVersions ~= "" and not getSetting(versionsKey) then
		setSetting(versionsKey, legacyVersions)
	end

	local legacyHistory = getSetting(PluginConfig.SETTING_KEY_HISTORY_LEGACY)
	if type(legacyHistory) == "string" and legacyHistory ~= "" then
		return legacyHistory
	end
	return nil
end

--!
-- Initializes chat state with the current user (Core/Identity must be initialized).
--!
function ChatState.init()
	ChatState.currentUserId = Identity.userId
	ChatState.currentUsername = Identity.username
end

--!
-- Populates the DataModel folder from a decoded array of message entries.
--!
local function populateFolder(folder, messages)
	for _, entry in ipairs(messages) do
		local msgType = entry.messageType or ChatState.MESSAGE_TYPE_TEXT
		local message = Instance.new("Folder")
		message.Name = (
			msgType == ChatState.MESSAGE_TYPE_POLL and "poll_"
			or msgType == ChatState.MESSAGE_TYPE_FILE and "file_"
			or "msg_"
		)
			.. tostring(entry.timestamp or os.time())
			.. "_"
			.. math.random(100000, 999999)
		message:SetAttribute("Sender", entry.sender or "Unknown")
		message:SetAttribute("SenderId", entry.senderId or 0)
		message:SetAttribute("Timestamp", entry.timestamp or os.time())
		message:SetAttribute("Content", entry.content or "")
		message:SetAttribute("MessageType", msgType)
		message:SetAttribute("EditedAt", entry.editedAt)
		-- Bot messages everyone sees: who ran which command, and its card
		message:SetAttribute("SaidBy", entry.saidBy)
		message:SetAttribute("SaidByName", entry.saidByName)
		message:SetAttribute("Command", entry.command)
		message:SetAttribute("Embed", entry.embed)
		message:SetAttribute("BotId", entry.botId)
		message:SetAttribute("BotOwner", entry.botOwner)
		message:SetAttribute("BotAvatar", entry.botAvatar)
		message:SetAttribute("Components", entry.components)
		message:SetAttribute("VisibleTo", entry.visibleTo)
		if entry.pinned then
			message:SetAttribute("PinnedAt", entry.pinnedAt)
			message:SetAttribute("PinnedBy", entry.pinnedBy)
			message:SetAttribute("PinnedByName", entry.pinnedByName)
			message:SetAttribute("Pinned", true)
		end
		if type(entry.reactions) == "string" and entry.reactions ~= "" then
			message:SetAttribute("Reactions", entry.reactions)
		end
		if entry.imageUrl then
			message:SetAttribute("ImageUrl", entry.imageUrl)
		end
		-- Restore reply reference attributes so reply context survives reloads
		if entry.replyToTimestamp then
			message:SetAttribute("ReplyToTimestamp", entry.replyToTimestamp)
			message:SetAttribute("ReplyToSender", entry.replyToSender)
			message:SetAttribute("ReplyToSenderId", entry.replyToSenderId)
			message:SetAttribute("ReplyToContent", entry.replyToContent)
		end
		if msgType == ChatState.MESSAGE_TYPE_POLL then
			message:SetAttribute("Question", entry.question or "")
			message:SetAttribute("Options", HttpService:JSONEncode(entry.options or {}))
			message:SetAttribute("Votes", HttpService:JSONEncode(entry.votes or {}))
		elseif msgType == ChatState.MESSAGE_TYPE_FILE then
			message:SetAttribute("FileName", entry.fileName or "file")
			message:SetAttribute("FileUrl", entry.fileUrl or "")
			message:SetAttribute("FileType", entry.fileType or "Other")
		end
		message.Parent = folder
	end
end

--!
-- Serializes all messages from the DataModel folder to a JSON string.
--!
function ChatState.serializeMessages(): string?
	local folder = ChatState.getFolder()
	local serialized = {}
	for _, child in ipairs(folder:GetChildren()) do
		local msgType = child:GetAttribute("MessageType") or ChatState.MESSAGE_TYPE_TEXT
		local entry = {
			sender = child:GetAttribute("Sender") or "Unknown",
			senderId = child:GetAttribute("SenderId") or 0,
			timestamp = child:GetAttribute("Timestamp") or 0,
			content = child:GetAttribute("Content") or "",
			imageUrl = child:GetAttribute("ImageUrl"),
			messageType = msgType,
			editedAt = child:GetAttribute("EditedAt"),
			saidBy = child:GetAttribute("SaidBy"),
			saidByName = child:GetAttribute("SaidByName"),
			command = child:GetAttribute("Command"),
			embed = child:GetAttribute("Embed"),
			botId = child:GetAttribute("BotId"),
			botOwner = child:GetAttribute("BotOwner"),
			botAvatar = child:GetAttribute("BotAvatar"),
			components = child:GetAttribute("Components"),
			visibleTo = child:GetAttribute("VisibleTo"),
			pinned = child:GetAttribute("Pinned"),
			pinnedAt = child:GetAttribute("PinnedAt"),
			pinnedBy = child:GetAttribute("PinnedBy"),
			pinnedByName = child:GetAttribute("PinnedByName"),
			reactions = child:GetAttribute("Reactions"), -- JSON (Chat/Reactions)
		}
		-- Persist reply reference attributes so replies keep their context
		local replyToTimestamp = child:GetAttribute("ReplyToTimestamp")
		if replyToTimestamp then
			entry.replyToTimestamp = replyToTimestamp
			entry.replyToSender = child:GetAttribute("ReplyToSender")
			entry.replyToSenderId = child:GetAttribute("ReplyToSenderId")
			entry.replyToContent = child:GetAttribute("ReplyToContent")
		end
		if msgType == ChatState.MESSAGE_TYPE_POLL then
			entry.question = child:GetAttribute("Question") or ""
			local okOpts, options = pcall(function()
				return HttpService:JSONDecode(child:GetAttribute("Options") or "[]")
			end)
			local okVotes, votes = pcall(function()
				return HttpService:JSONDecode(child:GetAttribute("Votes") or "[]")
			end)
			entry.options = okOpts and options or {}
			entry.votes = okVotes and votes or {}
		elseif msgType == ChatState.MESSAGE_TYPE_FILE then
			entry.fileName = child:GetAttribute("FileName") or "file"
			entry.fileUrl = child:GetAttribute("FileUrl") or ""
			entry.fileType = child:GetAttribute("FileType") or "Other"
		end
		table.insert(serialized, entry)
	end
	table.sort(serialized, function(a, b)
		return a.timestamp < b.timestamp
	end)
	local ok, json = pcall(function()
		return HttpService:JSONEncode(serialized)
	end)
	if ok then
		return json
	end
	return nil
end

--!
-- Writes this place's local chat backup (the place itself is saved by Studio).
--!
function ChatState.saveHistory()
	local json = ChatState.serializeMessages()
	if json then
		setSetting(historySettingKey(), json)
	end
end

--!
-- Removes all messages from the DataModel folder.
--!
function ChatState.clearFolder()
	local folder = ChatState.getFolder()
	for _, child in ipairs(folder:GetChildren()) do
		child.Parent = nil
	end
end

--!
-- Replaces the current chat history with the given serialized JSON.
-- Clears the DataModel folder, repopulates it, and persists the result.
-- @return true on success
--!
function ChatState.applyHistory(json: string): boolean
	if not json or json == "" then
		return false
	end
	local okDecode, messages = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not okDecode or type(messages) ~= "table" then
		return false
	end

	local folder = ChatState.getFolder()
	ChatState.clearFolder()
	populateFolder(folder, messages)
	ChatState.saveHistory()
	return true
end

--!
-- Loads the chat for this place. The copy saved in the place wins (it is
-- what every collaborator shares), even when empty: an empty folder means
-- the chat was cleared, so a stale local backup must not bring it back.
-- Only when the place has no chat folder at all (new place, or the folder
-- was deleted) is this place's local backup restored, or else the pre-0.4
-- shared history imported once.
--!
function ChatState.restoreFromSettings()
	local placeHasChat = PlaceStorage.getRoot():FindFirstChild(CHAT_FOLDER_NAME) ~= nil
	local folder = ChatState.getFolder()
	if placeHasChat then
		ChatState.saveHistory() -- refresh the local backup from the place
		return
	end

	local json = getSetting(historySettingKey())
	if type(json) ~= "string" or json == "" then
		json = takeLegacyHistory()
	end
	if not json or json == "" then
		return
	end

	local okDecode, messages = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not okDecode or type(messages) ~= "table" then
		return
	end

	populateFolder(folder, messages)
	ChatState.saveHistory()
end

--!
-- Deletes a message from the open conversation by timestamp.
-- Finds the message with the matching timestamp and removes it.
-- @param timestamp number - The timestamp of the message to delete
-- @return boolean - true if message was found and deleted
--!
function ChatState.deleteMessage(timestamp: number): boolean
	local folder = ChatState.getActiveFolder()
	for _, child in ipairs(folder:GetChildren()) do
		local childTimestamp = child:GetAttribute("Timestamp")
		-- Only your own messages, and bot messages from commands you ran
		-- (moderators clear others' with /purge)
		local mine = ChatState.currentUserId > 0
			and (
				child:GetAttribute("SenderId") == ChatState.currentUserId
				or (child:GetAttribute("Sender") == "System" and child:GetAttribute("SaidBy") == ChatState.currentUserId)
				-- A message from a bot you made, or an ephemeral answer meant for you
				or (child:GetAttribute("BotId") ~= nil and child:GetAttribute("BotOwner") == ChatState.currentUserId)
				or child:GetAttribute("VisibleTo") == ChatState.currentUserId
			)
		if childTimestamp and childTimestamp == timestamp and mine then
			child.Parent = nil
			ChatState.saveHistory()
			return true
		end
	end
	return false
end

return ChatState
