--!strict
--[[
	Channels

	Which backend channel each conversation is stored in:
	  main             the workspace's team chat channel (TeamChatData.Backend)
	  dm_<a>_<b>       a backend DM with the other person's account
	  group conversations  a backend group with the members' accounts; its id
	                   is saved on the group's folder (BackendChannel), so every
	                   member's plugin uses the same one

	Teammates are found by their Roblox account in the workspace. Someone who
	hasn't signed in yet has no account: their DMs wait until they have one,
	and they're added to groups once they do.
]]

local HttpService = game:GetService("HttpService")

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)
local Client = require(script.Parent.Client)
local Connection = require(script.Parent.Connection)

local Channels = {}

local conversations: any = nil -- Services/Chat/Conversations
local accountOf: { [number]: string } = {} -- Roblox user id -> backend user id
local missingUntil: { [number]: number } = {} -- Roblox user id -> when to ask again
local addedToGroup: { [string]: { [number]: boolean } } = {}

function Channels.init(chatConversations: any)
	conversations = chatConversations
end

local function key(): string
	return Settings.placeKey(BackendConfig.SETTING_KEY_CHANNELS)
end

local function saved(): { [string]: string }
	local map = Settings.getJson(key(), {})
	return if type(map) == "table" then map else {}
end

local function remember(conversationId: string, channelId: string)
	local map = saved()
	map[conversationId] = channelId
	Settings.setJson(key(), map)
end

function Channels.forget()
	Settings.setJson(key(), {})
	table.clear(accountOf)
	table.clear(missingUntil)
	table.clear(addedToGroup)
end

--[=[
	The backend account of a teammate (by Roblox user id), or nil while they
	haven't signed in. Yields.
]=]
function Channels.account(robloxUserId: number): string?
	if accountOf[robloxUserId] then
		return accountOf[robloxUserId]
	end
	if (missingUntil[robloxUserId] or 0) > os.clock() then
		return nil
	end
	local info = Connection.get()
	if not info or not info.workspaceId then
		return nil
	end
	local result =
		Client.request("GET", "/workspaces/" .. info.workspaceId .. "/members/roblox/" .. tostring(robloxUserId))
	if result.problem or type(result.data) ~= "table" or type(result.data.user) ~= "table" then
		if result.status == 404 then
			missingUntil[robloxUserId] = os.clock() + BackendConfig.LOOKUP_RETRY
		end
		return nil
	end
	accountOf[robloxUserId] = result.data.user.id
	return accountOf[robloxUserId]
end

local function groupMembers(folder: Instance): { number }
	local ok, members = pcall(HttpService.JSONDecode, HttpService, folder:GetAttribute("GroupMembers") or "[]")
	local list = {}
	if ok and type(members) == "table" then
		for _, userId in ipairs(members) do
			if type(userId) == "number" and userId ~= Identity.userId then
				table.insert(list, userId)
			end
		end
	end
	return list
end

-- Adds members who have signed in since the group was stored
local function addLateMembers(conversationId: string, channelId: string, members: { number })
	local added = addedToGroup[conversationId] or {}
	addedToGroup[conversationId] = added
	for _, robloxUserId in ipairs(members) do
		if not added[robloxUserId] then
			local account = Channels.account(robloxUserId)
			if account then
				local result = Client.request("PUT", "/conversations/" .. channelId .. "/recipients/" .. account)
				if not result.problem or result.status == 400 or result.status == 403 then
					added[robloxUserId] = true -- in it, or it's full or they don't accept DMs
				end
			end
		end
	end
end

--[=[
	The backend channel for a conversation, or nil (and why) while it can't
	have one yet. Yields.
]=]
function Channels.resolve(conversationId: string): (string?, string?)
	local info = Connection.get()
	if not info or not info.channelId then
		return nil, "noWorkspace"
	end
	if conversationId == "main" then
		return info.channelId, nil
	end
	local folder = conversations and conversations.getFolder(conversationId, false)
	local known = saved()[conversationId]
		or (folder and type(folder:GetAttribute("BackendChannel")) == "string" and folder:GetAttribute("BackendChannel"))
		or nil

	local other = conversations and conversations.otherUserId(conversationId)
	if other then
		if known then
			return known, nil
		end
		local account = Channels.account(other)
		if not account then
			return nil, "waitingForTeammate"
		end
		local result = Client.request("POST", "/conversations", { recipients = { account } })
		if result.problem or type(result.data) ~= "table" then
			return nil, result.problem
		end
		remember(conversationId, result.data.conversation.id)
		return result.data.conversation.id, nil
	end

	if not folder then
		return nil, "unknownConversation"
	end
	local members = groupMembers(folder)
	if known then
		remember(conversationId, known)
		addLateMembers(conversationId, known, members)
		return known, nil
	end
	local accounts = {}
	for _, robloxUserId in ipairs(members) do
		local account = Channels.account(robloxUserId)
		if account then
			table.insert(accounts, account)
		end
	end
	if #accounts == 0 then
		return nil, "waitingForTeammate"
	end
	local result = Client.request("POST", "/conversations", { recipients = accounts, name = "Group" })
	if result.problem or type(result.data) ~= "table" then
		return nil, result.problem
	end
	local channelId = result.data.conversation.id
	folder:SetAttribute("BackendChannel", channelId)
	remember(conversationId, channelId)
	addLateMembers(conversationId, channelId, members)
	return channelId, nil
end

return Channels
