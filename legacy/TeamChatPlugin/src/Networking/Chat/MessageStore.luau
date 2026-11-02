--!
-- MessageStore
-- Handles message collection, text message sending, and file message sending.
-- Operates on the shared ChatState module.
--!

local HttpService = game:GetService("HttpService")

local TimeFormatter = require(script.Parent.Parent.Parent.Utils.TimeFormatter)
local ChatState = require(script.Parent.ChatState)

local MessageStore = {}

--!
-- Reads one message folder into an entry table (sender, timestamp, content,
-- messageType and the reply/poll/file fields).
--!
function MessageStore.readEntry(child: Instance): table
	local msgType = child:GetAttribute("MessageType") or ChatState.MESSAGE_TYPE_TEXT
	local entry = {
		sender = child:GetAttribute("Sender") or "Unknown",
		senderId = child:GetAttribute("SenderId") or 0,
		timestamp = child:GetAttribute("Timestamp") or 0,
		content = child:GetAttribute("Content") or "",
		imageUrl = child:GetAttribute("ImageUrl"),
		messageType = msgType,
	}
	local replyToTimestamp = child:GetAttribute("ReplyToTimestamp")
	if replyToTimestamp then
		entry.replyToTimestamp = replyToTimestamp
		entry.replyToSender = child:GetAttribute("ReplyToSender")
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

--!
-- Collects all messages in a conversation folder (the team chat by
-- default), sorted by timestamp ascending.
--!
function MessageStore.collect(folder: Folder?): {table}
	local messages = {}
	for _, child in ipairs((folder or ChatState.getFolder()):GetChildren()) do
		table.insert(messages, MessageStore.readEntry(child))
	end
	table.sort(messages, function(a, b)
		return a.timestamp < b.timestamp
	end)
	return messages
end

--!
-- Initializes the message store: restores from settings if needed,
-- then collects and returns all existing messages.
--!
function MessageStore.init(): {table}
	ChatState.restoreFromSettings()
	return MessageStore.collect()
end

--!
-- Sends a text chat message to the open conversation, optionally as a reply
-- to another message.
--!
function MessageStore.sendMessage(content: string, imageUrl: string?, replyRef: {timestamp: number, sender: string?, content: string?}?)
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
		message:SetAttribute("ReplyToContent", replyRef.content)
	end
	message.Parent = folder
	ChatState.saveHistory()
end

--!
-- Sends a file message with file metadata to the open conversation.
--!
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

--!
-- Deletes a message by timestamp.
--!
function MessageStore.deleteMessage(timestamp: number)
	ChatState.deleteMessage(timestamp)
end

return MessageStore