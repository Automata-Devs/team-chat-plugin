--!strict
--[[
	Restore

	Brings the team chat back from the backend into the place: every stored
	message that isn't in the place any more (after /clear, a lost or reverted
	place, a new copy of it) is rebuilt as it was, from the client data its
	sender's plugin stored. Nothing in the place is changed or removed.

	Stored messages are sealed (end-to-end encrypted): they're opened with the
	place's key, and ones that don't open (another place's key) are left out.
	Readable ones stored by an older Team Chat still come back.
]]

local HttpService = game:GetService("HttpService")

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local ChatState = require(script.Parent.Parent.Chat.ChatState)
local Client = require(script.Parent.Client)
local Connection = require(script.Parent.Connection)
local Logger = require(script.Parent.Parent.Parent.Core.Logger)
local Seal = require(script.Parent.Seal)

local log = Logger.scope("Backend")

local Restore = {}

-- A stored message's text and client data, opened when they're sealed; nil
-- when they don't open with this place's key
local function opened(message: { [string]: any }): (string?, { [string]: any }?)
	local content = if type(message.content) == "string" then message.content else ""
	if Seal.isSealed(content) then
		local text = Seal.open(content)
		if text == nil then
			return nil, nil
		end
		content = text
	end
	local client = if type(message.metadata) == "table" and type(message.metadata.client) == "table"
		then message.metadata.client
		else {}
	if Seal.isSealed(client.e2e) then
		local json = Seal.open(client.e2e)
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json or "")
		if not json or not ok or type(decoded) ~= "table" then
			return nil, nil
		end
		client = decoded
	end
	return content, client
end

-- A saved entry (ChatState.buildMessage) from a stored message
local function entryOf(message: { [string]: any }, content: string, client: { [string]: any }): { [string]: any }
	local author = if type(message.author) == "table" then message.author else {}
	local entry: { [string]: any } = {
		sender = client.sender or author.displayName or author.username or "Unknown",
		senderId = tonumber(client.senderId) or 0,
		timestamp = tonumber(client.timestamp) or os.time(),
		content = content,
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

	if not Seal.ready() then
		return nil, "noWorkspace"
	end
	local restored, unreadable = 0, 0
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
				local content, client = opened(message)
				if content == nil or client == nil then
					unreadable += 1
					present[name] = true
					continue
				end
				local rebuilt = ChatState.buildMessage(entryOf(message, content, client), name)
				rebuilt:SetAttribute("BackendId", message.id)
				local stored = if type(message.metadata) == "table" then message.metadata.client else nil
				if type(stored) == "table" and Seal.isSealed(stored.e2e) then
					rebuilt:SetAttribute("BackendSealed", true) -- else it's sealed again (Mirror)
				end
				local poll = client.pollData
				if type(rebuilt:GetAttribute("Options")) ~= "string" and type(poll) == "table" then
					rebuilt:SetAttribute("Options", HttpService:JSONEncode(poll.options or {}))
					rebuilt:SetAttribute("Votes", HttpService:JSONEncode(poll.votes or {}))
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
	if unreadable > 0 then
		log.warn("%d stored messages couldn't be opened with this place's key and weren't restored", unreadable)
	end
	return restored, nil
end

return Restore
