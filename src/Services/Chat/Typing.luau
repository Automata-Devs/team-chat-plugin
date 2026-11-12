--[[
	Typing

	Syncs "user is typing" presence across Team Create collaborators.
	Each collaborator maintains a single entry in a shared TeamChatTyping
	folder (a sibling of the chat messages folder). Entries carry a
	LastActivity timestamp that is refreshed while the user types and
	expire after a short timeout, so stale entries never linger.
	Each entry also names the conversation it's for (Conversation: "main" or a
	DM's id), so a DM's typing only shows in that DM.
]]

local ChatState = require(script.Parent.ChatState)
local Conversations = require(script.Parent.Conversations)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)

local TypingIndicator = {}

-- Tunables
local TYPING_FOLDER_NAME = "TeamChatTyping"
local PUBLISH_INTERVAL = 2 -- seconds between LastActivity refreshes while typing
local ACTIVE_TIMEOUT = 8 -- entries older than this are no longer "typing"
local CLEANUP_TIMEOUT = 30 -- entries older than this are removed from the folder

local typingFolder: Folder? = nil
local isTyping = false
local typingConversation = Conversations.MAIN
local lastPublish = 0
local changedCallback: (({ string }) -> ())? = nil
local lastNotifiedKey = ""

-- Finds or creates the shared typing-status folder.
local function getTypingFolder(): Folder
	if typingFolder and typingFolder.Parent then
		return typingFolder
	end

	local parent = ChatState.getFolder().Parent
	local folder = parent:FindFirstChild(TYPING_FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = TYPING_FOLDER_NAME
		folder.Parent = parent
	end
	typingFolder = folder
	return folder
end

-- Publishes or refreshes this user's typing entry.
local function publish()
	local folder = getTypingFolder()
	local entryName = "typing_" .. tostring(ChatState.currentUserId)
	local entry = folder:FindFirstChild(entryName)
	if not entry then
		entry = Instance.new("Folder")
		entry.Name = entryName
		entry.Parent = folder
	end
	entry:SetAttribute("UserId", ChatState.currentUserId)
	entry:SetAttribute("Username", ChatState.currentUsername)
	entry:SetAttribute("Conversation", typingConversation)
	entry:SetAttribute("LastActivity", os.time())
	lastPublish = os.clock()
end

-- Removes this user's typing entry.
local function removeOwnEntry()
	if not typingFolder then
		return
	end
	local entry = typingFolder:FindFirstChild("typing_" .. tostring(ChatState.currentUserId))
	if entry then
		entry.Parent = nil
	end
end

--[=[
	Returns the usernames of collaborators currently typing (excluding self)
	in a conversation (default: the open one).
]=]
function TypingIndicator.getTypingUsers(conversation: string?): { string }
	conversation = conversation or Conversations.getActiveId()
	local folder = getTypingFolder()
	local now = os.time()
	local users = {}
	for _, child in ipairs(folder:GetChildren()) do
		local lastActivity = child:GetAttribute("LastActivity") or 0
		local userId = child:GetAttribute("UserId") or 0
		local entryConversation = child:GetAttribute("Conversation") or Conversations.MAIN
		if
			now - lastActivity <= ACTIVE_TIMEOUT
			and userId ~= ChatState.currentUserId
			and entryConversation == conversation
		then
			local username = child:GetAttribute("Username")
			if username and username ~= "" then
				table.insert(users, username)
			end
		end
	end
	table.sort(users)
	return users
end

-- Notifies the subscriber when the set of visible typers changes.
local function notifyIfChanged()
	if not changedCallback then
		return
	end
	local users = TypingIndicator.getTypingUsers()
	local key = Conversations.getActiveId() .. "|" .. table.concat(users, ",")
	if key ~= lastNotifiedKey then
		lastNotifiedKey = key
		changedCallback(users)
	end
end

--[=[
	Updates whether the local user is typing, and in which conversation
	(default: the team chat).
]=]
function TypingIndicator.setTyping(active: boolean, conversation: string?)
	active = active == true
	conversation = conversation or Conversations.MAIN
	if active == isTyping and (not active or conversation == typingConversation) then
		return
	end
	isTyping = active
	typingConversation = conversation :: string
	if active then
		publish()
	else
		removeOwnEntry()
	end
	notifyIfChanged()
end

--[=[
	Registers a callback fired with the list of currently typing usernames
	whenever that list changes (including expiry of stale entries).
]=]
function TypingIndicator.onTypingChanged(callback: ({ string }) -> ())
	changedCallback = callback
end

--[=[
	Simulates a remote user typing for the given duration (testing aid for
	the /typing command). Creates a fake entry under a negative UserId so it
	is never confused with a real collaborator, refreshes it while active,
	and removes it when the duration elapses. It types in the open
	conversation unless `conversation` says otherwise.
]=]
function TypingIndicator.simulateTyping(username: string, duration: number, conversation: string?)
	duration = math.clamp(duration or 5, 1, 60)
	conversation = conversation or Conversations.getActiveId()
	local folder = getTypingFolder()
	local entryName = "typing_sim_" .. tostring(username)

	task.spawn(function()
		local deadline = os.clock() + duration
		while os.clock() < deadline do
			local entry = folder:FindFirstChild(entryName)
			if not entry then
				entry = Instance.new("Folder")
				entry.Name = entryName
				entry.Parent = folder
			end
			entry:SetAttribute("UserId", -1)
			entry:SetAttribute("Username", username)
			entry:SetAttribute("Conversation", conversation)
			entry:SetAttribute("LastActivity", os.time())
			task.wait(2)
		end
		local entry = folder:FindFirstChild(entryName)
		if entry then
			entry.Parent = nil
		end
	end)
end

--[=[
	Initializes the typing indicator: prepares the shared folder and starts
	the background refresh / cleanup / expiry loop.
]=]
function TypingIndicator.init()
	local folder = getTypingFolder()

	Lifetime.connect(folder.ChildAdded, function()
		notifyIfChanged()
	end)
	Lifetime.connect(folder.ChildRemoved, function()
		notifyIfChanged()
	end)

	local function watchEntry(child)
		if child:GetAttribute("UserId") then
			Lifetime.connect(child:GetAttributeChangedSignal("LastActivity"), notifyIfChanged)
		end
	end
	for _, child in ipairs(folder:GetChildren()) do
		watchEntry(child)
	end
	Lifetime.connect(folder.ChildAdded, watchEntry)

	-- Background loop: keeps our own entry fresh while typing, expires
	-- stale entries for display, and removes long-dead entries entirely.
	task.spawn(function()
		while Lifetime.alive do -- stops when the plugin unloads
			task.wait(1)
			if isTyping and os.clock() - lastPublish >= PUBLISH_INTERVAL then
				publish()
			end

			local now = os.time()
			for _, child in ipairs(folder:GetChildren()) do
				local lastActivity = child:GetAttribute("LastActivity") or 0
				if now - lastActivity > CLEANUP_TIMEOUT then
					child.Parent = nil
				end
			end

			notifyIfChanged()
		end
	end)
end

return TypingIndicator
