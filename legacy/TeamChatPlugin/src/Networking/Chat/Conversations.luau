--!
-- Conversations
-- The team chat for this place (always pinned first) plus one direct-message
-- conversation per pair of collaborators.
--
-- DMs use the same message folders as the team chat, one folder per pair:
-- ServerStorage.TeamChatData.DirectMessages.dm_<lowUserId>_<highUserId>.
-- The folder is created with the first message. Like the team chat, DMs are
-- saved in the place, so anyone who can open the place in Studio could read
-- them in ServerStorage; the plugin only shows them to the two people in them.
--
-- Read state (for unread badges) is kept per person in plugin settings.
--
-- A new DM can be started with anyone (from your Roblox friends or by
-- username); they see it when they open this place with Team Chat.
--
-- Closing a DM only hides it from your list (like Discord): it comes back
-- when a newer message arrives or you start it again. Messages are kept.
--!

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

local ChatState = require(script.Parent.ChatState)
local PlaceStorage = require(script.Parent.Parent.PlaceStorage)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)

local Conversations = {}

Conversations.MAIN = "main"

local DM_FOLDER_NAME = "DirectMessages"
local READ_SETTING_KEY = "TeamChatLastRead_v1"
local READ_SINCE_SETTING_KEY = "TeamChatReadSince_v1"
local CLOSED_SETTING_KEY = "TeamChatClosedDms_v1"

local activeId = Conversations.MAIN
local lastRead: {[string]: number} = {}
local closed: {[string]: number} = {} -- DM id -> newest message timestamp when it was closed
local readSince = 0 -- messages from before the plugin first ran in this place count as read
local names: {[number]: string} = {}
local placeName = game.Name
local placeIcon: string? = nil -- only when the game has its own icon (see init)
local started: {[number]: boolean} = {} -- DMs opened this session that have no messages yet
local friends: {table}? = nil
local friendIds: {[number]: boolean} = {}
local friendsLoading = false
local friendsWaiting: {({table}) -> ()} = {}
local MAX_FRIENDS = 200
local changedCallbacks: {() -> ()} = {}
local folderAddedCallbacks: {(string, Folder) -> ()} = {}
local changePending = false

local function myId(): number
	return ChatState.currentUserId
end

local function getSetting(key: string): any
	local ok, value = pcall(function()
		return ChatState.pluginRef:GetSetting(PlaceStorage.settingKey(key))
	end)
	return if ok then value else nil
end

local function setSetting(key: string, value: any)
	pcall(function()
		ChatState.pluginRef:SetSetting(PlaceStorage.settingKey(key), value)
	end)
end

local function fireChanged()
	if changePending then return end
	changePending = true
	task.defer(function()
		changePending = false
		for _, callback in ipairs(changedCallbacks) do
			task.spawn(callback)
		end
	end)
end

--!
-- Conversation id for a DM between two users ("dm_<low>_<high>").
--!
function Conversations.dmId(userA: number, userB: number): string
	return string.format("dm_%d_%d", math.min(userA, userB), math.max(userA, userB))
end

--!
-- The other person in one of my DM conversations (nil for the team chat or
-- a DM between two other people).
--!
function Conversations.otherUserId(id: string): number?
	local a, b = string.match(id, "^dm_(%d+)_(%d+)$")
	local userA, userB = tonumber(a), tonumber(b)
	if userA == myId() then
		return userB
	elseif userB == myId() then
		return userA
	end
	return nil
end

local function dmRoot(): Folder
	return PlaceStorage.getFolder(DM_FOLDER_NAME)
end

--!
-- Display name for a user id. Unknown names are looked up in the background
-- and the list refreshes once they arrive.
--!
function Conversations.nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.Name
		return player.Name
	end
	names[userId] = "User " .. tostring(userId)
	task.spawn(function()
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if ok and name then
			names[userId] = name
			fireChanged()
		end
	end)
	return names[userId]
end

local function rememberName(userId: any, name: any)
	if type(userId) == "number" and userId > 0 and type(name) == "string" and name ~= "" and name ~= "Unknown" then
		names[userId] = name
	end
end

--!
-- The folder holding a conversation's messages. DM folders only exist after
-- the first message; pass create = true to make it.
--!
function Conversations.getFolder(id: string, create: boolean?): Folder?
	if id == Conversations.MAIN then
		return ChatState.getFolder()
	end
	local root = dmRoot()
	local folder = root:FindFirstChild(id)
	if not folder and create then
		local other = Conversations.otherUserId(id)
		if not other then return nil end
		folder = Instance.new("Folder")
		folder.Name = id
		-- Names are stored so the list can show them while that person is offline.
		folder:SetAttribute("Name_" .. myId(), ChatState.currentUsername)
		folder:SetAttribute("Name_" .. other, Conversations.nameOf(other))
		folder.Parent = root
	end
	return folder :: Folder?
end

function Conversations.getActiveId(): string
	return activeId
end

function Conversations.setActive(id: string)
	activeId = id
end

local function newestMessage(folder: Folder): Instance?
	local newest, newestTime = nil, -math.huge
	for _, child in ipairs(folder:GetChildren()) do
		local timestamp = child:GetAttribute("Timestamp") or 0
		if timestamp >= newestTime then
			newest, newestTime = child, timestamp
		end
	end
	return newest
end

--!
-- Marks everything currently in a conversation as read. Uses the newest
-- message's own timestamp, so collaborators' clocks don't matter.
--!
function Conversations.markRead(id: string)
	local folder = Conversations.getFolder(id, false)
	local newest = folder and newestMessage(folder)
	local timestamp = if newest then newest:GetAttribute("Timestamp") or 0 else 0
	if (lastRead[id] or 0) >= timestamp then return end
	lastRead[id] = timestamp
	local ok, json = pcall(HttpService.JSONEncode, HttpService, lastRead)
	if ok then
		setSetting(READ_SETTING_KEY, json)
	end
	fireChanged()
end

--!
-- Messages from others newer than what I've read.
--!
function Conversations.unreadCount(id: string): number
	local folder = Conversations.getFolder(id, false)
	if not folder then return 0 end
	local since = math.max(lastRead[id] or 0, readSince)
	local count = 0
	for _, child in ipairs(folder:GetChildren()) do
		local senderId = child:GetAttribute("SenderId")
		if (child:GetAttribute("Timestamp") or 0) > since and senderId ~= myId() and child:GetAttribute("Sender") ~= "System" then
			count += 1
		end
	end
	return count
end

local function previewOf(message: Instance): string
	local messageType = message:GetAttribute("MessageType")
	local text = message:GetAttribute("Content") or ""
	if messageType == "Poll" then
		text = "Poll: " .. (message:GetAttribute("Question") or "")
	elseif messageType == "File" then
		text = message:GetAttribute("FileName") or "File"
	elseif text == "" and message:GetAttribute("ImageUrl") then
		text = "Image"
	end
	text = string.gsub(text, "%s+", " ")
	if message:GetAttribute("SenderId") == myId() then
		text = "You: " .. text
	end
	return text
end

--!
-- The pinned team chat entry followed by a DM entry for every collaborator
-- I know of (online now, in an existing DM, or seen in the team chat),
-- most recent conversation first.
--!
function Conversations.list(): {table}
	local entries = {}
	local onlineCount = 0
	local users: {[number]: boolean} = {}
	for _, player in ipairs(Players:GetPlayers()) do
		onlineCount += 1
		rememberName(player.UserId, player.Name)
		if player.UserId > 0 and player.UserId ~= myId() then
			users[player.UserId] = true
		end
	end

	table.insert(entries, {
		id = Conversations.MAIN,
		kind = "place",
		name = placeName,
		icon = placeIcon,
		onlineCount = onlineCount,
		unread = Conversations.unreadCount(Conversations.MAIN),
	})

	if myId() <= 0 then
		return entries -- not signed in: no DMs
	end

	local root = dmRoot()
	for _, folder in ipairs(root:GetChildren()) do
		local other = Conversations.otherUserId(folder.Name)
		if other then
			users[other] = true
			rememberName(other, folder:GetAttribute("Name_" .. other))
		end
	end
	for userId in pairs(started) do
		users[userId] = true
	end
	for _, message in ipairs(ChatState.getFolder():GetChildren()) do
		local senderId = message:GetAttribute("SenderId")
		if type(senderId) == "number" and senderId > 0 and senderId ~= myId() then
			users[senderId] = true
			rememberName(senderId, message:GetAttribute("Sender"))
		end
	end

	local dms = {}
	for userId in pairs(users) do
		local id = Conversations.dmId(myId(), userId)
		local folder = root:FindFirstChild(id)
		local newest = folder and newestMessage(folder)
		local newestTime = if newest then newest:GetAttribute("Timestamp") or 0 else 0
		local isClosed = closed[id] ~= nil and newestTime <= closed[id] and id ~= activeId
		if isClosed then
			continue
		end
		table.insert(dms, {
			id = id,
			kind = "dm",
			userId = userId,
			name = Conversations.nameOf(userId),
			online = Players:GetPlayerByUserId(userId) ~= nil,
			isFriend = friendIds[userId] == true,
			unread = Conversations.unreadCount(id),
			lastTimestamp = newestTime,
			preview = if newest then previewOf(newest) else nil,
		})
	end
	table.sort(dms, function(a, b)
		if a.lastTimestamp ~= b.lastTimestamp then
			return a.lastTimestamp > b.lastTimestamp
		end
		if a.online ~= b.online then
			return a.online
		end
		return string.lower(a.name) < string.lower(b.name)
	end)
	for _, entry in ipairs(dms) do
		table.insert(entries, entry)
	end
	return entries
end

local function saveClosed()
	local ok, json = pcall(HttpService.JSONEncode, HttpService, closed)
	if ok then
		setSetting(CLOSED_SETTING_KEY, json)
	end
end

--!
-- Opens a DM with someone new: it shows in the list right away, and its
-- folder is made when the first message is sent.
--!
function Conversations.startDm(userId: number, name: string?): string?
	if myId() <= 0 or userId <= 0 or userId == myId() then
		return nil
	end
	rememberName(userId, name)
	started[userId] = true
	local id = Conversations.dmId(myId(), userId)
	if closed[id] then
		closed[id] = nil
		saveClosed()
	end
	fireChanged()
	return id
end

--!
-- Removes a DM from my list until a newer message arrives or I start it
-- again. Nothing is deleted.
--!
function Conversations.closeDm(id: string)
	local other = Conversations.otherUserId(id)
	if not other then return end
	local folder = Conversations.getFolder(id, false)
	local newest = folder and newestMessage(folder)
	closed[id] = if newest then newest:GetAttribute("Timestamp") or 0 else 0
	started[other] = nil
	saveClosed()
	fireChanged()
end

--!
-- Calls back with my Roblox friends ({ userId, username, displayName },
-- sorted by display name). Loaded once, up to MAX_FRIENDS.
--!
function Conversations.getFriends(callback: ({table}) -> ())
	if friends then
		task.spawn(callback, friends)
		return
	end
	table.insert(friendsWaiting, callback)
	if friendsLoading then return end
	friendsLoading = true
	task.spawn(function()
		local list = {}
		pcall(function()
			local pages = Players:GetFriendsAsync(myId())
			while true do
				for _, friend in ipairs(pages:GetCurrentPage()) do
					table.insert(list, { userId = friend.Id, username = friend.Username, displayName = friend.DisplayName })
					friendIds[friend.Id] = true
					rememberName(friend.Id, friend.Username)
				end
				if pages.IsFinished or #list >= MAX_FRIENDS then break end
				pages:AdvanceToNextPageAsync()
			end
		end)
		table.sort(list, function(a, b)
			return string.lower(a.displayName or a.username) < string.lower(b.displayName or b.username)
		end)
		friends = list
		friendsLoading = false
		for _, waiting in ipairs(friendsWaiting) do
			task.spawn(waiting, list)
		end
		table.clear(friendsWaiting)
		fireChanged()
	end)
end

--!
-- Looks up a username; calls back with (userId, exact username) or nil.
--!
function Conversations.resolveUser(username: string, callback: (number?, string?) -> ())
	task.spawn(function()
		local ok, userId = pcall(function()
			return Players:GetUserIdFromNameAsync(username)
		end)
		if not ok or not userId then
			callback(nil, nil)
			return
		end
		local nameOk, exactName = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		local name = if nameOk and exactName then exactName else username
		rememberName(userId, name)
		callback(userId, name)
	end)
end

--!
-- Header/empty-state text for a conversation.
--!
function Conversations.describe(id: string): table
	if id == Conversations.MAIN then
		return { id = id, kind = "place", name = placeName }
	end
	local other = Conversations.otherUserId(id)
	return {
		id = id,
		kind = "dm",
		userId = other,
		name = if other then Conversations.nameOf(other) else "Direct message",
		online = other ~= nil and Players:GetPlayerByUserId(other) ~= nil,
	}
end

--!
-- Called (batched, once per frame) whenever the list or unread counts may
-- have changed: new or deleted messages, new DMs, people joining or leaving.
--!
function Conversations.onChanged(callback: () -> ())
	table.insert(changedCallbacks, callback)
end

--!
-- Called when one of my DM folders appears (its first message was sent).
--!
function Conversations.onFolderAdded(callback: (string, Folder) -> ())
	table.insert(folderAddedCallbacks, callback)
end

local watched: {[Instance]: boolean} = setmetatable({}, { __mode = "k" }) :: any

local function watchFolder(folder: Instance)
	if watched[folder] then return end
	watched[folder] = true
	Lifetime.connect(folder.ChildAdded, fireChanged)
	Lifetime.connect(folder.ChildRemoved, fireChanged)
end

--!
-- Loads read state, routes new messages to the open conversation, and
-- watches the place for anything that changes the list.
--!
function Conversations.init()
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(getSetting(READ_SETTING_KEY) or "{}")
	end)
	lastRead = if ok and type(decoded) == "table" then decoded else {}
	local closedOk, closedDecoded = pcall(function()
		return HttpService:JSONDecode(getSetting(CLOSED_SETTING_KEY) or "{}")
	end)
	closed = if closedOk and type(closedDecoded) == "table" then closedDecoded else {}
	readSince = getSetting(READ_SINCE_SETTING_KEY) or 0
	if readSince == 0 then
		readSince = os.time()
		setSetting(READ_SINCE_SETTING_KEY, readSince)
	end

	ChatState.activeFolderResolver = function()
		return Conversations.getFolder(activeId, true) or ChatState.getFolder()
	end

	if game.PlaceId ~= 0 then
		task.spawn(function()
			local infoOk, info = pcall(function()
				return MarketplaceService:GetProductInfo(game.PlaceId)
			end)
			if infoOk and info and info.Name then
				placeName = info.Name
				-- Games without their own icon get Roblox's gray default, so
				-- the sidebar shows its initials tile instead.
				if (info.IconImageAssetId or 0) ~= 0 and game.GameId ~= 0 then
					placeIcon = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=150&h=150"
				end
				fireChanged()
			end
		end)
	end

	if myId() > 0 then
		Conversations.getFriends(function() end) -- marks friends in the list
	end

	watchFolder(ChatState.getFolder())
	local root = dmRoot()
	for _, folder in ipairs(root:GetChildren()) do
		if Conversations.otherUserId(folder.Name) then
			watchFolder(folder)
		end
	end
	Lifetime.connect(root.ChildAdded, function(folder)
		if not Conversations.otherUserId(folder.Name) then return end
		watchFolder(folder)
		fireChanged()
		for _, callback in ipairs(folderAddedCallbacks) do
			task.spawn(callback, folder.Name, folder)
		end
	end)
	Lifetime.connect(root.ChildRemoved, fireChanged)
	Lifetime.connect(Players.PlayerAdded, fireChanged)
	Lifetime.connect(Players.PlayerRemoving, function()
		task.defer(fireChanged) -- after the player is gone
	end)
end

return Conversations
