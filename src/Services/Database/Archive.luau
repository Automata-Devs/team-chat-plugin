--!strict
--[[
	Archive

	Keeps the team chat's history on the database server, so it outlives
	/clear, /purge and the place itself, and can be searched.

	Each message is uploaded by the plugin of the person who sent it (or who
	ran the bot command it answers), so it's uploaded once. The server keys
	them by place, conversation and message name, so a repeat replaces it.
]]

local DatabaseConfig = require(script.Parent.Parent.Parent.Config.Database)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Logger = require(script.Parent.Parent.Parent.Core.Logger)
local PlaceStorage = require(script.Parent.Parent.Parent.Core.PlaceStorage)
local Client = require(script.Parent.Client)
local Outbox = require(script.Parent.Outbox)

export type Entry = {
	id: string,
	sender: string,
	senderId: number,
	timestamp: number,
	content: string,
	type: string?,
	editedAt: number?,
	command: string?,
	botId: string?,
	saidBy: number?,
	fileName: string?,
	fileUrl: string?,
	imageUrl: string?,
	replyToTimestamp: number?,
}

local THINKING_WAIT = 60 -- seconds a bot's "thinking" placeholder may take to get its answer

local log = Logger.scope("Database")

local Archive = {}

-- Messages I sent since the last profile sync (UserStats adds them up)
Archive.sentSinceSync = 0

local pending: { { conversation: string, message: Instance, queuedAt: number } } = {}
local readEntry: ((Instance) -> { [string]: any })? = nil

local function isMine(message: Instance): boolean
	local me = Identity.userId
	if me <= 0 then
		return false
	end
	local saidBy = message:GetAttribute("SaidBy")
	if saidBy ~= nil then
		return saidBy == me
	end
	return message:GetAttribute("SenderId") == me
end

--[=[
	Starts archiving: `chat` is the Chat facade (its Conversations and readEntry).
]=]
function Archive.init(chat: any)
	readEntry = chat.readEntry
	chat.Conversations.onMessage(function(conversation: string, message: Instance)
		Archive.consider(conversation, message)
	end)
end

--[=[
	Queues a new message for upload when it's in an archived conversation,
	mine, and not an ephemeral answer.
]=]
function Archive.consider(conversation: string, message: Instance)
	if not DatabaseConfig.ARCHIVED_CONVERSATIONS[conversation] then
		return
	end
	if message:GetAttribute("VisibleTo") ~= nil or not isMine(message) then
		return
	end
	table.insert(pending, { conversation = conversation, message = message, queuedAt = os.clock() })
end

--[=[
	How many messages are waiting to be uploaded.
]=]
function Archive.pendingCount(): number
	return #pending
end

local function toEntry(message: Instance): Entry
	local raw = if readEntry then readEntry(message) else {}
	return {
		id = message.Name,
		sender = raw.sender or message:GetAttribute("Sender") or "Unknown",
		senderId = raw.senderId or message:GetAttribute("SenderId") or 0,
		timestamp = raw.timestamp or message:GetAttribute("Timestamp") or os.time(),
		content = raw.content or message:GetAttribute("Content") or "",
		type = raw.messageType,
		editedAt = raw.editedAt,
		command = raw.command,
		botId = raw.botId,
		saidBy = raw.saidBy,
		fileName = raw.fileName,
		fileUrl = raw.fileUrl,
		imageUrl = raw.imageUrl,
		replyToTimestamp = raw.replyToTimestamp,
	}
end

local function archivePath(conversation: string, suffix: string?): string
	return "/archive/" .. Client.escape(PlaceStorage.placeKey()) .. "/" .. Client.escape(conversation) .. (suffix or "")
end

--[=[
	Uploads waiting messages in batches per conversation. A batch that can't
	reach the server goes to the Outbox. Returns how many were sent. Yields.
]=]
function Archive.flush(): number
	local ready: { [string]: { Entry } } = {}
	local keep = {}
	for _, item in ipairs(pending) do
		local message = item.message
		if message.Parent == nil then
			continue -- deleted before it was uploaded
		end
		if message:GetAttribute("Thinking") == true and os.clock() - item.queuedAt < THINKING_WAIT then
			table.insert(keep, item)
			continue
		end
		local batch = ready[item.conversation] or {}
		ready[item.conversation] = batch
		if #batch >= DatabaseConfig.ARCHIVE_BATCH then
			table.insert(keep, item)
			continue
		end
		table.insert(batch, toEntry(message))
	end
	pending = keep

	local sent = 0
	for conversation, entries in pairs(ready) do
		local path = archivePath(conversation)
		local body = { messages = entries }
		local result = Client.request("POST", path, body)
		if result.problem and result.retry then
			Outbox.push({ method = "POST", path = path, body = body })
		elseif result.problem then
			log.warn("The database didn't archive %d messages: %s", #entries, result.problem)
			continue
		end
		sent += #entries
		for _, entry in ipairs(entries) do
			if entry.saidBy == nil and entry.senderId == Identity.userId then
				Archive.sentSinceSync += 1
			end
		end
	end
	return sent
end

--[=[
	Archived messages of a conversation, newest last: up to `limit` from
	before `before` (os.time). Returns nil and a problem when it can't be read. Yields.
]=]
function Archive.history(conversation: string, before: number?, limit: number?): ({ Entry }?, string?)
	local query = "?limit=" .. tostring(limit or 50)
	if before then
		query ..= "&before=" .. tostring(before)
	end
	local result = Client.request("GET", archivePath(conversation, query))
	if result.problem then
		return nil, result.problem
	end
	return if type(result.data) == "table" then result.data.messages or {} else {}, nil
end

--[=[
	Archived messages in this place whose text contains `text` (any case),
	newest first. Yields.
]=]
function Archive.search(text: string, limit: number?): ({ Entry & { conversation: string? } }?, string?)
	local path = "/archive/"
		.. Client.escape(PlaceStorage.placeKey())
		.. "?q="
		.. Client.escape(text)
		.. "&limit="
		.. tostring(limit or DatabaseConfig.SEARCH_LIMIT)
	local result = Client.request("GET", path)
	if result.problem then
		return nil, result.problem
	end
	return if type(result.data) == "table" then result.data.messages or {} else {}, nil
end

--[=[
	Drops waiting messages (after disconnecting).
]=]
function Archive.clear()
	pending = {}
	Archive.sentSinceSync = 0
end

return Archive
