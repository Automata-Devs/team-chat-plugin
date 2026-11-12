--!strict
--[[
	Mirror

	Stores everything I write in the backend, under my own account: my
	messages in the team chat, DMs and groups (with the plugin's own fields as
	client data), my edits, my deletes and my reactions.

	New messages are uploaded in batches. A message is stored once: its name
	is the upload's nonce, and the backend's id is kept on it (BackendId).
	Messages that aren't stored yet (sent offline, before connecting, or before
	the plugin was installed) are found again by rescanning the place.

	/clear and /purge don't delete anything stored: only deleting one of your
	own messages does.
]]

local HttpService = game:GetService("HttpService")

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local Logger = require(script.Parent.Parent.Parent.Core.Logger)
local Channels = require(script.Parent.Channels)
local Client = require(script.Parent.Client)
local Outbox = require(script.Parent.Outbox)

local log = Logger.scope("Backend")

local Mirror = {}

local THINKING_WAIT = 60 -- seconds a bot's "thinking" placeholder may take to get its answer

local chat: any = nil
local startedAt = os.time()
local pending: { [string]: { Instance } } = {} -- conversation -> messages to upload
local queued: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local conversationOf: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local myReactions: { [Instance]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

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

local function storable(message: Instance): boolean
	return message:IsA("Folder")
		and message:GetAttribute("VisibleTo") == nil -- an answer only one person sees
		and message:GetAttribute("BackendId") == nil
		and message:GetAttribute("BackendSkip") == nil
		and isMine(message)
end

-- At most `max` characters, never cutting one in half
local function clip(text: string, max: number): string
	local ok, length = pcall(utf8.len, text)
	if not ok or length == nil then
		text = string.gsub(text, "[\128-\255]", "?") -- not valid UTF-8
		length = #text
	end
	if (length :: number) <= max then
		return text
	end
	local cut = utf8.offset(text, max + 1)
	return if cut then string.sub(text, 1, cut - 1) else text
end

--[=[
	What's uploaded for a message: its text, and the plugin's own fields as
	client data (so a restore can rebuild it exactly).
]=]
function Mirror.toUpload(
	message: Instance
): { content: string, nonce: string, flags: number, clientData: { [string]: any } }
	local entry = if chat then chat.readEntry(message) else {}
	local data: { [string]: any } = {
		name = message.Name,
		sender = entry.sender,
		senderId = entry.senderId,
		timestamp = entry.timestamp,
		messageType = entry.messageType,
		editedAt = entry.editedAt,
		imageUrl = entry.imageUrl,
		saidBy = entry.saidBy,
		saidByName = entry.saidByName,
		command = entry.command,
		botId = entry.botId,
		botOwner = entry.botOwner,
		botAvatar = entry.botAvatar,
		embedJson = entry.embedJson,
		componentsJson = entry.componentsJson,
		replyToTimestamp = entry.replyToTimestamp,
		replyToSender = entry.replyToSender,
		replyToSenderId = entry.replyToSenderId,
		replyToContent = entry.replyToContent,
		pollData = entry.pollData,
		fileName = entry.fileName,
		fileUrl = entry.fileUrl,
		fileType = entry.fileType,
	}
	-- Big extras go first if it's over the limit
	for _, extra in ipairs({ "componentsJson", "embedJson", "replyToContent", "pollData" }) do
		local ok, json = pcall(HttpService.JSONEncode, HttpService, data)
		if ok and #json <= BackendConfig.MAX_CLIENT_DATA then
			break
		end
		data[extra] = nil
	end

	local content = entry.content or ""
	if content == "" and entry.pollData then
		content = "📊 " .. tostring(entry.pollData.question)
	elseif content == "" and entry.fileName then
		content = "📎 " .. tostring(entry.fileName)
	end
	local old = (tonumber(entry.timestamp) or os.time()) < startedAt - 60
	return {
		content = clip(content, BackendConfig.MAX_CONTENT),
		nonce = message.Name,
		-- Older messages stored later don't notify anyone again
		flags = if old then BackendConfig.SUPPRESS_NOTIFICATIONS else 0,
		clientData = data,
	}
end

-- The conversation a message is in: remembered when it was seen, or from its
-- folder (team chat, or a DM or group folder named by its id) when it's added
-- and changed in the same moment, before the place's events have run
local function conversationFor(message: Instance): string?
	if conversationOf[message] then
		return conversationOf[message]
	end
	local parent = message.Parent
	if not parent or not chat then
		return nil
	end
	if parent == chat.getFolder() then
		return "main"
	end
	return if chat.Conversations.getFolder(parent.Name, false) == parent then parent.Name else nil
end

local function emojiPath(channelId: string, messageId: string, emoji: string): string
	return "/channels/" .. channelId .. "/messages/" .. messageId .. "/reactions/" .. Client.escape(emoji) .. "/@me"
end

local function myEmoji(message: Instance): { [string]: boolean }
	local mine = {}
	local ok, list = pcall(HttpService.JSONDecode, HttpService, message:GetAttribute("Reactions") or "[]")
	if ok and type(list) == "table" then
		for _, item in ipairs(list) do
			if type(item) == "table" and type(item.e) == "string" and type(item.u) == "table" then
				if table.find(item.u, Identity.userId) then
					mine[item.e] = true
				end
			end
		end
	end
	return mine
end

-- Queues the difference between my reactions now and what was last stored
local function syncReactions(message: Instance)
	local messageId = message:GetAttribute("BackendId")
	local conversation = conversationFor(message)
	if type(messageId) ~= "string" or not conversation then
		return
	end
	local channelId = Channels.resolve(conversation)
	if not channelId then
		return
	end
	local now = myEmoji(message)
	local before = myReactions[message] or {}
	for emoji in pairs(now) do
		if not before[emoji] then
			Outbox.push({ method = "PUT", path = emojiPath(channelId, messageId, emoji) })
		end
	end
	for emoji in pairs(before) do
		if not now[emoji] then
			Outbox.push({ method = "DELETE", path = emojiPath(channelId, messageId, emoji) })
		end
	end
	myReactions[message] = now
end

local function onEdited(message: Instance)
	local messageId = message:GetAttribute("BackendId")
	local conversation = conversationFor(message)
	if type(messageId) ~= "string" or not conversation or not isMine(message) then
		return
	end
	local channelId = Channels.resolve(conversation)
	if not channelId then
		return
	end
	local upload = Mirror.toUpload(message)
	if upload.content == "" then
		return
	end
	Outbox.push({
		method = "PATCH",
		path = "/channels/" .. channelId .. "/messages/" .. messageId,
		body = { content = upload.content, clientData = upload.clientData },
	})
end

local function watch(conversation: string, message: Instance)
	conversationOf[message] = conversation
	if watched[message] then
		return
	end
	watched[message] = true
	Lifetime.connect(message.AttributeChanged, function(attribute: string)
		if attribute == "Content" then
			onEdited(message)
		elseif attribute == "Reactions" then
			task.spawn(syncReactions, message)
		elseif attribute == "Thinking" and message:GetAttribute("Thinking") ~= true then
			Mirror.consider(conversation, message) -- a bot's answer arrived
		end
	end)
end

--[=[
	Looks at a message: watches it for edits and reactions, and queues it for
	upload when it's mine and not stored yet.
]=]
function Mirror.consider(conversation: string, message: Instance)
	if not message:IsA("Folder") then
		return
	end
	watch(conversation, message)
	if queued[message] or not storable(message) then
		return
	end
	queued[message] = true
	local list = pending[conversation] or {}
	pending[conversation] = list
	table.insert(list, message)
end

--[=[
	My message was deleted (by me, not by /clear): delete it from the backend too.
]=]
function Mirror.deleted(message: Instance)
	local messageId = message:GetAttribute("BackendId")
	local conversation = conversationFor(message)
	if type(messageId) ~= "string" or not conversation or not isMine(message) then
		return
	end
	task.spawn(function()
		local channelId = Channels.resolve(conversation)
		if channelId then
			Outbox.push({ method = "DELETE", path = "/channels/" .. channelId .. "/messages/" .. messageId })
		end
	end)
end

function Mirror.pendingCount(): number
	local count = 0
	for _, list in pairs(pending) do
		count += #list
	end
	return count
end

--[=[
	Queues every message of mine in the place that isn't stored yet: the team
	chat and every DM and group I'm in.
]=]
function Mirror.scan()
	if not chat then
		return
	end
	local ids = { "main" }
	for _, conversation in ipairs(chat.Conversations.list()) do
		if conversation.id ~= "main" then
			table.insert(ids, conversation.id)
		end
	end
	for _, id in ipairs(ids) do
		local folder = chat.Conversations.getFolder(id, false)
		if folder then
			for _, message in ipairs(folder:GetChildren()) do
				Mirror.consider(id, message)
			end
		end
	end
end

--[=[
	Uploads waiting messages, up to BATCH per request per conversation.
	Conversations that can't have a channel yet keep theirs. Returns how many
	were stored. Yields.
]=]
function Mirror.flush(): number
	local stored = 0
	for conversation, list in pairs(pending) do
		local channelId, why = Channels.resolve(conversation)
		if not channelId then
			if why ~= "waitingForTeammate" and why ~= "noWorkspace" and why ~= "unreachable" then
				log.warn("Can't store messages of %s yet: %s", conversation, tostring(why))
			end
			continue
		end
		while #list > 0 do
			local batch, uploads, keep = {}, {}, {}
			for _, message in ipairs(list) do
				local thinking = message:GetAttribute("Thinking") == true
				if message.Parent == nil or not storable(message) then
					queued[message] = nil
				elseif thinking and os.time() - (message:GetAttribute("Timestamp") or 0) < THINKING_WAIT then
					table.insert(keep, message) -- wait for the bot's answer
				elseif #batch < BackendConfig.BATCH then
					table.insert(batch, message)
					table.insert(uploads, Mirror.toUpload(message))
				else
					table.insert(keep, message)
				end
			end
			if #batch == 0 then
				pending[conversation] = keep
				list = keep
				break
			end
			local result =
				Client.request("POST", "/channels/" .. channelId .. "/messages/batch", { messages = uploads })
			if result.problem then
				if result.retry or result.problem == "signedOut" then
					for _, message in ipairs(batch) do
						table.insert(keep, message)
					end
					pending[conversation] = keep
					return stored
				end
				log.warn("The backend refused %d messages: %s", #batch, result.problem)
				for _, message in ipairs(batch) do
					message:SetAttribute("BackendSkip", true) -- not retried forever
					queued[message] = nil
				end
			else
				local ids = {}
				for _, item in ipairs(result.data.messages or {}) do
					ids[item.nonce] = item.id
				end
				for _, message in ipairs(batch) do
					queued[message] = nil
					local id = ids[message.Name]
					if id and message.Parent then
						message:SetAttribute("BackendId", id)
						stored += 1
						task.spawn(syncReactions, message)
					end
				end
			end
			pending[conversation] = keep
			list = keep
			if #keep > 0 and #batch < BackendConfig.BATCH then
				break -- only messages still waiting for something
			end
		end
	end
	return stored
end

function Mirror.init(chatFacade: any)
	chat = chatFacade
	startedAt = os.time()
	chat.Conversations.onMessage(function(conversation: string, message: Instance)
		Mirror.consider(conversation, message)
	end)
end

function Mirror.clear()
	table.clear(pending)
end

return Mirror
