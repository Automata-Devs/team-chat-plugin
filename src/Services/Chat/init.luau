--[[
	Chat

	The chat's public API. Controllers and Commands use this facade; its
	sub-modules are internal:
	  ChatState      shared state, folders and the local history backup
	  MessageStore   reading and sending messages and files
	  Polls          polls and votes
	  Typing         who is typing
	  Conversations  the pinned team chat and direct messages
	  Pins           pinned messages
	  Reactions      emoji reactions
	  Stats          the admin dashboard's numbers and exports
	  VersionHistory backups of the team chat
]]

local PluginConfig = require(script.Parent.Parent.Config.Constants)

local ChatState = require(script.ChatState)
local MessageStore = require(script.MessageStore)
local PollManager = require(script.Polls)
local TypingIndicator = require(script.Typing)
local Conversations = require(script.Conversations)
local Pins = require(script.Pins)
local Reactions = require(script.Reactions)
local Stats = require(script.Stats)
local VersionHistory = require(script.VersionHistory)

local AdminNetwork = require(script.Parent.Admin)

local ChatNetwork = {}

--[=[
	Initializes the chat network and returns message history.
]=]
function ChatNetwork.init(): { any }
	ChatState.init()
	TypingIndicator.init()
	local history = MessageStore.init()
	Conversations.init()
	return history
end

-- Message Sending
ChatNetwork.sendMessage = MessageStore.sendMessage
ChatNetwork.sendMessageAs = MessageStore.sendMessageAs
ChatNetwork.sendFile = MessageStore.sendFile

-- Poll Management
ChatNetwork.sendPoll = PollManager.sendPoll
ChatNetwork.castVote = PollManager.castVote
ChatNetwork.deleteMessage = MessageStore.deleteMessage
ChatNetwork.sendBotMessage = MessageStore.sendBotMessage
ChatNetwork.sendNotice = MessageStore.sendNotice
ChatNetwork.editMessage = MessageStore.editMessage
ChatNetwork.getFolder = ChatState.getFolder
ChatNetwork.getActiveFolder = ChatState.getActiveFolder
ChatNetwork.readEntry = MessageStore.readEntry
ChatNetwork.collect = MessageStore.collect

-- Conversations (team chat + DMs)
ChatNetwork.Conversations = Conversations

-- Pinned messages
ChatNetwork.Pins = Pins

-- Emoji reactions
ChatNetwork.Reactions = Reactions
ChatNetwork.Stats = Stats
ChatNetwork.VersionHistory = VersionHistory

-- Typing Indicator
ChatNetwork.setTyping = TypingIndicator.setTyping
ChatNetwork.onTypingChanged = TypingIndicator.onTypingChanged
ChatNetwork.getTypingUsers = TypingIndicator.getTypingUsers
ChatNetwork.simulateTyping = TypingIndicator.simulateTyping

-- Online Users
function ChatNetwork.getOnlineUsers(): { table }
	local Players = game:GetService("Players")
	local users = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(users, {
			name = player.Name,
			userId = player.UserId,
			rank = AdminNetwork.getRank(player.UserId),
		})
	end
	return users
end

-- Whisper
--[=[
	Sends a direct message (it shows up in your DMs with that person).
]=]
function ChatNetwork.sendWhisper(targetUserId: number, message: string): boolean
	if ChatState.currentUserId <= 0 or targetUserId == ChatState.currentUserId then
		return false
	end
	local folder = Conversations.getFolder(Conversations.dmId(ChatState.currentUserId, targetUserId), true)
	if not folder then
		return false
	end
	local msg = Instance.new("Folder")
	msg.Name = "msg_" .. tostring(os.time()) .. "_" .. math.random(100000, 999999)
	msg:SetAttribute("Sender", ChatState.currentUsername)
	msg:SetAttribute("SenderId", ChatState.currentUserId)
	msg:SetAttribute("Timestamp", os.time())
	msg:SetAttribute("Content", message)
	msg:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_TEXT)
	msg.Parent = folder
	return true
end

-- Broadcast
function ChatNetwork.broadcast(message: string)
	local folder = ChatState.getFolder()
	local msg = Instance.new("Folder")
	msg.Name = "broadcast_" .. tostring(os.time()) .. "_" .. math.random(100000, 999999)
	msg:SetAttribute("Sender", ChatState.currentUsername)
	msg:SetAttribute("SenderId", ChatState.currentUserId)
	msg:SetAttribute("Timestamp", os.time())
	msg:SetAttribute("Content", message)
	msg:SetAttribute("MessageType", "Broadcast")
	msg:SetAttribute("IsBroadcast", true)
	msg.Parent = folder
	ChatState.saveHistory()
end

-- User Info
function ChatNetwork.getUsername(): string
	return ChatState.currentUsername
end

function ChatNetwork.getUserId(): number
	return ChatState.currentUserId
end

function ChatNetwork.getPluginAuthor(): string
	return PluginConfig.PLUGIN_AUTHOR
end

return ChatNetwork
