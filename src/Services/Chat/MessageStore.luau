--[[
	MessageStore

	Handles message collection, text message sending, and file message sending.
	Operates on the shared ChatState module.
]]

local HttpService = game:GetService("HttpService")

local TimeFormatter = require(script.Parent.Parent.Parent.Util.TimeFormat)
local ChatState = require(script.Parent.ChatState)

local MessageStore = {}

--[=[
	Reads one message folder into an entry table (sender, timestamp, content,
	messageType and the reply/poll/file fields).
]=]
function MessageStore.readEntry(child: Instance): table
	local msgType = child:GetAttribute("MessageType") or ChatState.MESSAGE_TYPE_TEXT
	local entry = {
		sender = child:GetAttribute("Sender") or "Unknown",
		senderId = child:GetAttribute("SenderId") or 0,
		timestamp = child:GetAttribute("Timestamp") or 0,
		content = child:GetAttribute("Content") or "",
		imageUrl = child:GetAttribute("ImageUrl"),
		messageType = msgType,
		editedAt = child:GetAttribute("EditedAt"),
	}
	-- Public bot messages: who ran the command, which one, and its card (JSON)
	entry.saidBy = child:GetAttribute("SaidBy")
	entry.saidByName = child:GetAttribute("SaidByName")
	entry.command = child:GetAttribute("Command")
	entry.embedJson = child:GetAttribute("Embed")
	-- Messages from user-made bots (Services/Bots)
	entry.botId = child:GetAttribute("BotId")
	entry.botOwner = child:GetAttribute("BotOwner")
	entry.botAvatar = child:GetAttribute("BotAvatar")
	entry.componentsJson = child:GetAttribute("Components")
	entry.visibleTo = child:GetAttribute("VisibleTo") -- an ephemeral bot answer: only this person
	entry.thinking = child:GetAttribute("Thinking") == true
	local replyToTimestamp = child:GetAttribute("ReplyToTimestamp")
	if replyToTimestamp then
		entry.replyToTimestamp = replyToTimestamp
		entry.replyToSender = child:GetAttribute("ReplyToSender")
		entry.replyToSenderId = child:GetAttribute("ReplyToSenderId")
		entry.replyToContent = child:GetAttribute("ReplyToContent")
	end
	if msgType == ChatState.MESSAGE_TYPE_POLL then
		local question = child:GetAttribute("Question") or ""
		local okOpts, options = pcall(function()
			return HttpService:JSONDecode(child:GetAttribute("Options") or "[]")
		end)
		local okVotes, votes = pcall(function()
			return HttpService:JSONDecode(child:GetAttribute("Votes") or "[]")
		end)
		entry.pollData = {
			question = question,
			options = okOpts and options or {},
			votes = okVotes and votes or {},
		}
	elseif msgType == ChatState.MESSAGE_TYPE_FILE then
		entry.fileName = child:GetAttribute("FileName") or "file"
		entry.fileUrl = child:GetAttribute("FileUrl") or ""
		entry.fileType = child:GetAttribute("FileType") or "Other"
	end
	return entry
end

--[=[
	Collects all messages in a conversation folder (the team chat by
	default), sorted by timestamp ascending.
]=]
function MessageStore.collect(folder: Folder?): { table }
	local messages = {}
	for _, child in ipairs((folder or ChatState.getFolder()):GetChildren()) do
		table.insert(messages, MessageStore.readEntry(child))
	end
	table.sort(messages, function(a, b)
		return a.timestamp < b.timestamp
	end)
	return messages
end

--[=[
	Initializes the message store: restores from settings if needed,
	then collects and returns all existing messages.
]=]
function MessageStore.init(): { table }
	ChatState.restoreFromSettings()
	return MessageStore.collect()
end

--[=[
	Sends a text chat message to the open conversation, optionally as a reply
	to another message.
]=]
function MessageStore.sendMessage(
	content: string,
	imageUrl: string?,
	replyRef: { timestamp: number, sender: string?, content: string? }?
)
	local folder = ChatState.getActiveFolder()
	local message = Instance.new("Folder")
	message.Name = "msg_" .. TimeFormatter.generateId()
	message:SetAttribute("Sender", ChatState.currentUsername)
	message:SetAttribute("SenderId", ChatState.currentUserId)
	message:SetAttribute("Timestamp", os.time())
	message:SetAttribute("Content", content)
	message:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_TEXT)
	if imageUrl and imageUrl ~= "" then
		message:SetAttribute("ImageUrl", imageUrl)
	end
	if replyRef and replyRef.timestamp then
		message:SetAttribute("ReplyToTimestamp", replyRef.timestamp)
		message:SetAttribute("ReplyToSender", replyRef.sender)
		message:SetAttribute("ReplyToSenderId", replyRef.senderId)
		message:SetAttribute("ReplyToContent", replyRef.content)
	end
	message.Parent = folder
	ChatState.saveHistory()
end

--[=[
	Sends a text message to the open conversation that shows as written by
	someone else (/say). `SaidBy` records who really sent it.
]=]
function MessageStore.sendMessageAs(username: string, userId: number, content: string)
	local folder = ChatState.getActiveFolder()
	local message = Instance.new("Folder")
	message.Name = "msg_" .. TimeFormatter.generateId()
	message:SetAttribute("Sender", username)
	message:SetAttribute("SenderId", userId)
	message:SetAttribute("SaidBy", ChatState.currentUserId)
	message:SetAttribute("Timestamp", os.time())
	message:SetAttribute("Content", content)
	message:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_TEXT)
	message.Parent = folder
	ChatState.saveHistory()
end

--[=[
	Sends a bot message everyone sees to the open conversation: from Team
	Chat ("System"), recording who ran `command` (SaidBy, SaidByName).
	`embedJson` is a CommandEmbed spec as JSON (optional).
]=]
function MessageStore.sendBotMessage(content: string, embedJson: string?, command: string?)
	local folder = ChatState.getActiveFolder()
	local message = Instance.new("Folder")
	message.Name = "bot_" .. TimeFormatter.generateId()
	message:SetAttribute("Sender", "System")
	message:SetAttribute("SenderId", 0)
	message:SetAttribute("SaidBy", ChatState.currentUserId)
	message:SetAttribute("SaidByName", ChatState.currentUsername)
	message:SetAttribute("Timestamp", os.time())
	message:SetAttribute("Content", content)
	message:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_TEXT)
	if command then
		message:SetAttribute("Command", command)
	end
	if embedJson then
		message:SetAttribute("Embed", embedJson)
	end
	message.Parent = folder
	ChatState.saveHistory()
end

--[=[
	A Team Chat notice everyone sees in the open conversation, about
	something the current user did ("d3v_c pinned a message"). Unlike
	sendBotMessage it has no "used /command" line.
]=]
function MessageStore.sendNotice(content: string, kind: string)
	local folder = ChatState.getActiveFolder()
	local message = Instance.new("Folder")
	message.Name = "bot_" .. TimeFormatter.generateId()
	message:SetAttribute("Sender", "System")
	message:SetAttribute("SenderId", 0)
	message:SetAttribute("SaidBy", ChatState.currentUserId) -- they can delete it
	message:SetAttribute("Notice", kind)
	message:SetAttribute("Timestamp", os.time())
	message:SetAttribute("Content", content)
	message:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_TEXT)
	message.Parent = folder
	ChatState.saveHistory()
end

--[=[
	Sends a file message with file metadata to the open conversation.
]=]
function MessageStore.sendFile(fileName: string, fileUrl: string, fileType: string, content: string?)
	local folder = ChatState.getActiveFolder()
	local message = Instance.new("Folder")
	message.Name = "file_" .. TimeFormatter.generateId()
	message:SetAttribute("Sender", ChatState.currentUsername)
	message:SetAttribute("SenderId", ChatState.currentUserId)
	message:SetAttribute("Timestamp", os.time())
	message:SetAttribute("Content", content or "")
	message:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_FILE)
	message:SetAttribute("FileName", fileName)
	message:SetAttribute("FileUrl", fileUrl)
	message:SetAttribute("FileType", fileType)
	message.Parent = folder
	ChatState.saveHistory()
end

--[=[
	Replaces the text of one of the current user's own text messages in the
	open conversation and marks it edited (EditedAt). Returns false when the
	message isn't found or isn't theirs.
]=]
function MessageStore.editMessage(timestamp: number, content: string): boolean
	local folder = ChatState.getActiveFolder()
	for _, child in ipairs(folder:GetChildren()) do
		local messageType = child:GetAttribute("MessageType") or ChatState.MESSAGE_TYPE_TEXT
		if
			child:GetAttribute("Timestamp") == timestamp
			and child:GetAttribute("SenderId") == ChatState.currentUserId
			and ChatState.currentUserId > 0
			and messageType == ChatState.MESSAGE_TYPE_TEXT
		then
			child:SetAttribute("Content", content)
			child:SetAttribute("EditedAt", os.time())
			ChatState.saveHistory()
			return true
		end
	end
	return false
end

--[=[
	Deletes a message by timestamp.
]=]
function MessageStore.deleteMessage(timestamp: number)
	ChatState.deleteMessage(timestamp)
end

return MessageStore
