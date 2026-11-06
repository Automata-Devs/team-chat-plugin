--!
-- PluginController
-- Handles plugin initialization, dockable widget visibility,
-- toolbar buttons, conversations (team chat + DMs), and
-- ChatNetwork <-> ChatUI wiring.
--!

local HttpService = game:GetService("HttpService")

local Badges = require(script.Parent.Parent.Services.Badges)
local Bots = require(script.Parent.Parent.Services.Bots)
local Language = require(script.Parent.Parent.Core.Language)
local Identity = require(script.Parent.Parent.Core.Identity)
local Mentions = require(script.Parent.Parent.Util.Mentions)
local Markdown = require(script.Parent.Parent.Util.Markdown)
local Profiles = require(script.Parent.Parent.Services.Profiles)
local Preferences = require(script.Parent.Parent.UI.Preferences)
local ToolbarIcons = require(script.Parent.Parent.Config.ToolbarIcons)

local NOTIFY_AFTER = 3 -- seconds after loading: the place's messages replicate in first
local NOTIFY_MAX_AGE = 30 -- seconds; older messages arriving don't notify
local Lifetime = require(script.Parent.Parent.Core.Lifetime)

local PluginController = {}

function PluginController.init(pluginRef, ui, chatNetwork, commandHandler)
	local toolbar = pluginRef:CreateToolbar("Team Chat")

	local toggleButton = toolbar:CreateButton("ToggleTeamChat", "Open or close Team Chat", ToolbarIcons.BASE, "Chat")

	local settingsButton = toolbar:CreateButton(
		"ToggleTeamChatSettings",
		"Open or close Team Chat settings",
		"rbxassetid://122184088768566",
		"Settings"
	)

	toggleButton.ClickableWhenViewportHidden = true
	settingsButton.ClickableWhenViewportHidden = true

	local function setChatVisible(visible)
		visible = visible == true

		if ui.setVisible then
			ui.setVisible(visible)
		else
			ui.widget.Enabled = visible
		end

		toggleButton:SetActive(ui.widget.Enabled)
	end

	local function syncSettingsButton()
		settingsButton:SetActive(ui.isSettingsVisible and ui.isSettingsVisible() or false)
	end

	toggleButton:SetActive(ui.widget.Enabled)
	syncSettingsButton()

	toggleButton.Click:Connect(function()
		setChatVisible(not ui.widget.Enabled)
	end)

	if ui.onVisibilityChanged then
		ui.onVisibilityChanged(function(visible)
			toggleButton:SetActive(visible)
			if visible then
				-- Opening the chat reads the open conversation
				task.defer(function()
					local Conversations = chatNetwork.Conversations
					Conversations.markRead(Conversations.getActiveId())
				end)
			end
		end)
	end

	settingsButton.Click:Connect(function()
		-- toggleSettings also handles the case where clicking this toolbar
		-- button already closed Settings (focus left the chat widget)
		if ui.toggleSettings() then
			setChatVisible(true)
		end

		syncSettingsButton()
	end)

	if ui.onSettingsVisibilityChanged then
		ui.onSettingsVisibilityChanged(function(visible)
			settingsButton:SetActive(visible)
		end)
	end

	if ui.setCommandProvider and commandHandler then
		ui.setCommandProvider(function()
			return commandHandler.getCommandList()
		end)
	end

	local Conversations = chatNetwork.Conversations

	-- Only your own messages can be edited
	ui.setCurrentUserId(chatNetwork.getUserId())

	-- Badges next to names (verified, custom, bought) and the Badges dialog.
	-- Lookups finish in the background; the names re-render when they do.
	ui.setBadgeProvider(Badges.get)
	-- Display names and verified flags for names everywhere
	ui.setProfileProvider(Profiles.get)
	Lifetime.add(Profiles.changed:Connect(ui.refreshProfiles))
	ui.setBadgeHandlers({
		myBadges = function()
			return Badges.get(chatNetwork.getUserId())
		end,
		getStore = function()
			return Badges.getStore(chatNetwork.getUserId())
		end,
		purchaseUrl = Badges.purchaseUrl,
		refresh = function()
			Badges.refresh(chatNetwork.getUserId())
		end,
		watchPurchase = function(badgeId, onStatus)
			Badges.watchPurchase(chatNetwork.getUserId(), badgeId, onStatus)
		end,
	})
	Lifetime.add(Badges.changed:Connect(ui.refreshBadges))

	-- Shows one message entry (from chatNetwork.readEntry) in the chat.
	local function decodeJson(json: string): any
		local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
		return if ok then value else nil
	end

	-- Bots show answers that are never saved (a web bot's ephemeral ones)
	-- and short notes straight in this chat
	Bots.ui = {
		showLocal = function(entry)
			return ui.addBotMessage(entry)
		end,
		removeLocal = function(message: Instance)
			message:Destroy()
		end,
		say = function(text: string)
			ui.addSystemMessage(text)
		end,
	}

	local function renderEntry(msg)
		local replyRef

		if msg.replyToTimestamp then
			replyRef = {
				timestamp = msg.replyToTimestamp,
				sender = msg.replyToSender,
				senderId = msg.replyToSenderId,
				content = msg.replyToContent,
			}
		end

		if (msg.sender == "System" or msg.botId) and ui.addBotMessage then
			-- A bot message everyone sees; its card is saved as JSON
			local embed = nil
			if msg.embedJson then
				local ok, decoded = pcall(HttpService.JSONDecode, HttpService, msg.embedJson)
				if ok and type(decoded) == "table" then
					if type(decoded.color) == "string" then
						local okColor, color = pcall(Color3.fromHex, decoded.color)
						decoded.color = if okColor then color else nil
					end
					embed = decoded
				end
			end
			ui.addBotMessage({
				timestamp = msg.timestamp,
				content = msg.content,
				saidBy = msg.saidBy,
				saidByName = msg.saidByName,
				command = msg.command,
				embed = embed,
				-- A user-made bot: its name, owner and avatar
				botId = msg.botId,
				botName = if msg.botId then msg.sender else nil,
				botOwner = msg.botOwner,
				botAvatar = msg.botAvatar,
				components = if msg.componentsJson then decodeJson(msg.componentsJson) else nil,
				visibleTo = msg.visibleTo,
				thinking = msg.thinking,
				instance = msg.instance,
				onDismiss = function()
					chatNetwork.deleteMessage(msg.timestamp)
				end,
			})
		elseif msg.messageType == "Poll" and msg.pollData then
			ui.addPollMessage(msg.sender, msg.timestamp, msg.pollData, replyRef)
		elseif msg.messageType == "File" and msg.fileName then
			ui.addFileMessage(
				msg.sender,
				msg.timestamp,
				msg.fileName,
				msg.fileUrl,
				msg.fileType,
				msg.content,
				replyRef,
				msg.senderId
			)
		elseif msg.messageType == "Broadcast" then
			ui.addAnnouncementMessage(msg.sender, msg.timestamp, msg.content, replyRef)
		else
			ui.addMessage(msg.sender, msg.timestamp, msg.content, msg.imageUrl, replyRef, msg.senderId)
		end
	end

	-- The open conversation: its folder's listeners, and which message
	-- folders are already shown (a message can show up both in the initial
	-- listing and in ChildAdded).
	local boundFolder: Folder? = nil
	local bindings: { RBXScriptConnection } = {}
	local shown: { [Instance]: boolean } = {}

	local function unbind()
		for _, connection in ipairs(bindings) do
			connection:Disconnect()
		end
		table.clear(bindings)
		boundFolder = nil
		shown = {}
	end

	-- The open conversation's pinned messages, for the pin panel (one
	-- refresh per frame however many pins change)
	local pinsQueued = false
	local function refreshPins()
		if pinsQueued then
			return
		end
		pinsQueued = true
		task.defer(function()
			pinsQueued = false
			if boundFolder and ui.setPins then
				ui.setPins(chatNetwork.Pins.list(boundFolder))
			end
		end)
	end

	-- A message's reactions under it (here or added by someone else)
	local function showReactions(child: Instance)
		if ui.setReactions then
			ui.setReactions(child.Name, chatNetwork.Reactions.read(child))
		end
	end

	-- The row just drawn for a saved message knows its name (messages can
	-- share a second; reactions must go on the right one)
	local function tagRow(child: Instance)
		if ui.tagMessage then
			ui.tagMessage(child:GetAttribute("Timestamp"), child.Name)
		end
	end

	local function showMessage(child)
		if shown[child] then
			return
		end
		shown[child] = true
		local entry = chatNetwork.readEntry(child)
		entry.instance = child
		local me = chatNetwork.getUserId()
		if entry.visibleTo and entry.visibleTo ~= me then
			return -- someone else's ephemeral bot answer
		end
		renderEntry(entry)
		tagRow(child)
		if entry.botId then
			-- A bot changed the message (a deferred answer, a button's update):
			-- draw it again where it was
			table.insert(
				bindings,
				Lifetime.connect(child:GetAttributeChangedSignal("Revision"), function()
					ui.removeMessage(child:GetAttribute("Timestamp"))
					local updated = chatNetwork.readEntry(child)
					updated.instance = child
					renderEntry(updated)
					tagRow(child)
					showReactions(child)
				end)
			)
		end
		if entry.editedAt then
			ui.updateMessage(entry.timestamp, entry.content, true)
		end

		-- Pins (here or by someone else)
		table.insert(bindings, Lifetime.connect(child:GetAttributeChangedSignal("Pinned"), refreshPins))

		-- Reactions (here or by someone else)
		if chatNetwork.Reactions.has(child) then
			showReactions(child)
		end
		table.insert(
			bindings,
			Lifetime.connect(child:GetAttributeChangedSignal("Reactions"), function()
				showReactions(child)
			end)
		)

		-- Edits (here or by the author on another computer)
		table.insert(
			bindings,
			Lifetime.connect(child:GetAttributeChangedSignal("Content"), function()
				ui.updateMessage(
					child:GetAttribute("Timestamp"),
					child:GetAttribute("Content") or "",
					child:GetAttribute("EditedAt") ~= nil
				)
			end)
		)

		if child:GetAttribute("MessageType") == "Poll" then
			table.insert(
				bindings,
				Lifetime.connect(child:GetAttributeChangedSignal("Votes"), function()
					local updated = chatNetwork.readEntry(child)
					if updated.pollData then
						ui.updatePollMessage(updated.timestamp, updated.pollData)
					end
				end)
			)
		end
	end

	local function markActiveRead()
		if ui.widget.Enabled then
			Conversations.markRead(Conversations.getActiveId())
		end
	end

	-- Shows a conversation folder's messages and follows changes to it.
	local function bindFolder(folder: Folder)
		unbind()
		boundFolder = folder
		ui.resetMessages()

		local children = folder:GetChildren()
		table.sort(children, function(x, y)
			return (x:GetAttribute("Timestamp") or 0) < (y:GetAttribute("Timestamp") or 0)
		end)
		for _, child in ipairs(children) do
			showMessage(child)
		end
		refreshPins()

		table.insert(
			bindings,
			Lifetime.connect(folder.ChildAdded, function(child)
				showMessage(child)
				markActiveRead()
			end)
		)
		-- Keep the UI in sync when messages are removed, whether deleted
		-- locally or by another collaborator.
		table.insert(
			bindings,
			Lifetime.connect(folder.ChildRemoved, function(child)
				shown[child] = nil
				if child:GetAttribute("Pinned") then
					refreshPins()
				end
				local ts = child:GetAttribute("Timestamp")
				if ts then
					ui.removeMessage(ts)
				end
			end)
		)
	end

	-- The toolbar button shows your unread count, like the chat's badges
	local function showUnreadOnToolbar(entries)
		local total = 0
		for _, entry in ipairs(entries) do
			total += entry.unread or 0
		end
		local icon = ToolbarIcons.forCount(total)
		if toggleButton.Icon ~= icon then
			toggleButton.Icon = icon
		end
	end

	local function refreshConversationList()
		local entries = Conversations.list()
		ui.setConversations(entries, Conversations.getActiveId())
		showUnreadOnToolbar(entries)
	end

	-- Who's typing in the open conversation (the team chat or a DM)
	local function showTypingUsers(names)
		ui.setTypingUsers(names)
	end

	local function openConversation(id: string)
		Conversations.setActive(id)
		-- Read before marking it read: the "New" line goes above it
		local firstUnread = Conversations.firstUnread(id)
		local folder = Conversations.getFolder(id, false)
		if folder then
			bindFolder(folder)
			if ui.showUnreadDivider then
				ui.showUnreadDivider(firstUnread)
			end
		else
			-- A DM with no messages yet: its folder appears with the first one
			unbind()
			ui.resetMessages()
		end
		ui.setConversation(Conversations.describe(id))
		chatNetwork.setTyping(false)
		showTypingUsers(chatNetwork.getTypingUsers())
		markActiveRead()
		refreshConversationList()
	end

	-- Notifications: a toast for each new message you aren't looking at
	-- (Settings > Notifications: All, DMs only or Off)
	local loadedAt = os.clock()
	Conversations.onMessage(function(id, message)
		local mode = Preferences.values.notifications
		-- An @mention of you (username, display name or @everyone), or a reply to
		-- one of your messages, gets through "DMs only"
		local myNames = { Identity.username }
		if Identity.userId > 0 then
			table.insert(myNames, Profiles.get(Identity.userId).displayName)
		end
		local mentioned = Identity.userId > 0 and Mentions.mentions(message:GetAttribute("Content"), myNames)
		local repliedToMe = Identity.userId > 0 and message:GetAttribute("ReplyToSenderId") == Identity.userId
		if mode == "Off" or (mode == "DMs only" and id == Conversations.MAIN and not mentioned and not repliedToMe) then
			return
		end
		local timestamp = message:GetAttribute("Timestamp")
		local senderId = message:GetAttribute("SenderId")
		local sender = message:GetAttribute("Sender")
		local me = chatNetwork.getUserId()
		if
			os.clock() - loadedAt < NOTIFY_AFTER
			or type(timestamp) ~= "number"
			or os.time() - timestamp > NOTIFY_MAX_AGE
			or type(sender) ~= "string"
			or sender == "System"
			or (message:GetAttribute("VisibleTo") ~= nil and message:GetAttribute("VisibleTo") ~= me)
			or (me > 0 and (senderId == me or message:GetAttribute("SaidBy") == me))
			or (ui.widget.Enabled and id == Conversations.getActiveId())
		then
			return
		end
		local messageType = message:GetAttribute("MessageType")
		local text = message:GetAttribute("Content") or ""
		if messageType == "Poll" then
			text = Language.t("notify.poll", { question = message:GetAttribute("Question") or "" })
		elseif messageType == "File" then
			text = Language.t("notify.sentFile", { file = message:GetAttribute("FileName") or "" })
		elseif text == "" then
			text = Language.t("notify.sentImage")
		end
		local name = sender
		if type(senderId) == "number" and senderId > 0 then
			name = Preferences.nameFor(sender, Profiles.get(senderId).displayName)
		end
		ui.notify({
			title = if mentioned
				then Language.t("notify.mentioned", { name = name })
				elseif repliedToMe then Language.t("notify.repliedToYou", { name = name })
				elseif id == Conversations.MAIN then name .. "  ·  " .. Language.t("notify.teamChat")
				else name,
			text = (string.gsub(Markdown.strip(text), "%s+", " ")),
			userId = if type(senderId) == "number" then senderId else nil,
			onClick = function()
				ui.widget.Enabled = true
				if id ~= Conversations.getActiveId() then
					openConversation(id)
				end
			end,
		})
	end)

	Conversations.onFolderAdded(function(id, folder)
		if id == Conversations.getActiveId() and boundFolder ~= folder then
			bindFolder(folder)
			markActiveRead()
		end
	end)

	Conversations.onChanged(function()
		-- Names and online status in the header can change too
		ui.setConversation(Conversations.describe(Conversations.getActiveId()))
		refreshConversationList()
	end)

	ui.onConversationSelected(function(id)
		if id ~= Conversations.getActiveId() then
			openConversation(id)
		end
	end)

	-- Closing a DM hides it; closing the open one goes back to the team chat
	ui.onConversationClosed(function(id)
		Conversations.closeDm(id)
		if id == Conversations.getActiveId() then
			openConversation(Conversations.MAIN)
		end
	end)

	-- New message: friends list, username lookup, and opening the DM
	ui.setNewMessageHandlers({
		getFriends = Conversations.getFriends,
		resolveUser = Conversations.resolveUser,
		isVerified = function(userId)
			return Profiles.get(userId).verified
		end,
		onPick = function(userId, username)
			local id = Conversations.startDm(userId, username)
			if id then
				openConversation(id)
			else
				ui.addSystemMessage("You can't send a direct message to yourself.")
			end
		end,
	})

	openConversation(Conversations.MAIN)

	ui.onCreatePoll(function(question, options)
		chatNetwork.sendPoll(question, options)
	end)

	ui.onVote(function(timestamp, optionIndex)
		chatNetwork.castVote(timestamp, optionIndex)
	end)

	local function findMessage(timestamp)
		local folder = chatNetwork.getActiveFolder()

		for _, child in ipairs(folder:GetChildren()) do
			if child:GetAttribute("Timestamp") == timestamp then
				return child
			end
		end

		return nil
	end

	ui.onReply(function(timestamp)
		local message = findMessage(timestamp)

		if not message then
			return
		end

		local sender = message:GetAttribute("Sender") or "Unknown"
		local content = message:GetAttribute("Content") or ""

		if ui.setReplyReference then
			ui.setReplyReference(timestamp, sender, content, message:GetAttribute("SenderId"))
		end
	end)

	ui.onDelete(function(timestamp)
		chatNetwork.deleteMessage(timestamp)
	end)

	-- Pinning: saved on the message; a pin also posts a notice, like Discord
	if ui.onPin then
		ui.onPin(function(timestamp, pinned)
			local ok, problem = chatNetwork.Pins.set(timestamp, pinned)
			if not ok then
				ui.addSystemMessage(Language.t("pins." .. tostring(problem)))
				return
			end
			if pinned then
				chatNetwork.sendNotice(
					Language.t("pins.notice", { user = "**" .. chatNetwork.getUsername() .. "**" }),
					"pin"
				)
			end
		end)
	end

	-- Reactions: picking an emoji or clicking a reaction adds or removes yours
	if ui.onReact then
		ui.onReact(function(timestamp, emoji)
			local ok, problem = chatNetwork.Reactions.toggle(timestamp, emoji)
			if not ok then
				ui.addSystemMessage(Language.t("reactions." .. tostring(problem)))
			end
		end)
	end

	-- Typing indicator: publish local typing activity for the open
	-- conversation and display others' in it
	if ui.onTypingActivity and chatNetwork.setTyping then
		ui.onTypingActivity(function(isTyping)
			chatNetwork.setTyping(isTyping, Conversations.getActiveId())
		end)
	end

	if chatNetwork.onTypingChanged and ui.setTypingUsers then
		chatNetwork.onTypingChanged(showTypingUsers)
	end

	ui.onCopy(function(timestamp)
		local message = findMessage(timestamp)

		if not message then
			return
		end

		local content = message:GetAttribute("Content") or ""
		local sender = message:GetAttribute("Sender") or "Unknown"
		local textToCopy = sender .. ": " .. content

		pcall(function()
			game:GetService("StudioService"):CopyToClipboard(textToCopy)
		end)
	end)
end

return PluginController
