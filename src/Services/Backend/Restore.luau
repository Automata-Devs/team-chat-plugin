--!strict
--[[
	Restore

	Brings the team chat back from the backend into the place: every stored
	message that isn't in the place any more (after /clear, a lost or reverted
	place, a new copy of it) is rebuilt as it was, from the client data its
	sender's plugin stored. Nothing in the place is changed or removed.
]]

local HttpService = game:GetService("HttpService")

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local ChatState = require(script.Parent.Parent.Chat.ChatState)
local Client = require(script.Parent.Client)
local Connection = require(script.Parent.Connection)

local Restore = {}

-- A saved entry (ChatState.buildMessage) from a stored message
local function entryOf(message: { [string]: any }): { [string]: any }
	local client = if type(message.metadata) == "table" and type(message.metadata.client) == "table"
		then message.metadata.client
		else {}
	local author = if type(message.author) == "table" then message.author else {}
	local entry: { [string]: any } = {
		sender = client.sender or author.displayName or author.username or "Unknown",
		senderId = tonumber(client.senderId) or 0,
		timestamp = tonumber(client.timestamp) or os.time(),
		content = message.content or "",
		messageType = client.messageType,
		editedAt = client.editedAt,
		imageUrl = client.imageUrl,
		saidBy = client.saidBy,
		saidByName = client.saidByName,
		command = client.command,
		embed = client.embedJson,
		botId = client.botId,
		botOwner = client.botOwner,
		botAvatar = client.botAvatar,
		components = client.componentsJson,
		replyToTimestamp = client.replyToTimestamp,
		replyToSender = client.replyToSender,
		replyToSenderId = client.replyToSenderId,
		replyToContent = client.replyToContent,
		fileName = client.fileName,
		fileUrl = client.fileUrl,
		fileType = client.fileType,
	}
	if type(client.pollData) == "table" then
		entry.content = ""
		entry.question = client.pollData.question
		entry.options = client.pollData.options
		entry.votes = client.pollData.votes
	elseif client.fileName then
		entry.content = ""
	end
	return entry
end

--[=[
	Restores the team chat. Returns how many messages came back, or nil and a
	problem. Yields.
]=]
function Restore.teamChat(): (number?, string?)
	local info = Connection.get()
	if not info or not info.channelId then
		return nil, "noWorkspace"
	end
	local folder = ChatState.getFolder()
	local present: { [string]: boolean } = {}
	for _, child in ipairs(folder:GetChildren()) do
		present[child.Name] = true
		local id = child:GetAttribute("BackendId")
		if type(id) == "string" then
			present[id] = true
		end
	end

	local restored = 0
	local before: string? = nil
	for _ = 1, BackendConfig.RESTORE_PAGES do
		local path = "/channels/"
			.. info.channelId
			.. "/messages?limit=100"
			.. (if before then "&before=" .. before else "")
		local result = Client.request("GET", path)
		if result.problem then
			return if restored > 0 then restored else nil, result.problem
		end
		local page = if type(result.data) == "table" then result.data.messages or {} else {}
		for _, message in ipairs(page) do
			local name = if type(message.nonce) == "string" and message.nonce ~= ""
				then message.nonce
				else "msg_backend_" .. message.id
			-- System messages (pins, renames) belong to the backend, not the place
			if
				not present[name]
				and not present[message.id]
				and (message.type == "default" or message.type == "reply" or message.type == "command")
			then
				local rebuilt = ChatState.buildMessage(entryOf(message), name)
				rebuilt:SetAttribute("BackendId", message.id)
				if type(rebuilt:GetAttribute("Options")) ~= "string" and type(message.metadata) == "table" then
					local poll = type(message.metadata.client) == "table" and message.metadata.client.pollData
					if type(poll) == "table" then
						rebuilt:SetAttribute("Options", HttpService:JSONEncode(poll.options or {}))
						rebuilt:SetAttribute("Votes", HttpService:JSONEncode(poll.votes or {}))
					end
				end
				rebuilt.Parent = folder
				present[name] = true
				restored += 1
			end
		end
		if #page < 100 then
			break
		end
		before = page[#page].id
	end
	if restored > 0 then
		ChatState.saveHistory()
	end
	return restored, nil
end

return Restore
