--!
-- PluginController
-- Handles plugin initialization, dockable widget visibility,
-- toolbar buttons, conversations (team chat + DMs), and
-- ChatNetwork <-> ChatUI wiring.
--!

local Lifetime = require(script.Parent.Lifetime)

local PluginController = {}

function PluginController.init(pluginRef, ui, history, chatNetwork, commandHandler)
	local toolbar = pluginRef:CreateToolbar("Team Chat")

	local toggleButton = toolbar:CreateButton(
		"ToggleTeamChat",
		"Open or close Team Chat",
		"rbxassetid://104410097861078",
		"Chat"
	)

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
		settingsButton:SetActive(
			ui.isSettingsVisible and ui.isSettingsVisible() or false
		)
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

	-- Shows one message entry (from chatNetwork.readEntry) in the chat.
	local function renderEntry(msg)
		local replyRef

		if msg.replyToTimestamp then
			replyRef = {
				timestamp = msg.replyToTimestamp,
				sender = msg.replyToSender,
				content = msg.replyToContent,
			}
		end

		if msg.messageType == "Poll" and msg.pollData then
			ui.addPollMessage(
				msg.sender,
				msg.timestamp,
				msg.pollData,
				replyRef
			)
		elseif msg.messageType == "File" and msg.fileName then
			ui.addFileMessage(
				msg.sender,
				msg.timestamp,
				msg.fileName,
				msg.fileUrl,
				msg.fileType,
				msg.content,
				replyRef
			)
		elseif msg.messageType == "Broadcast" then
			ui.addAnnouncementMessage(
				msg.sender,
				msg.timestamp,
				msg.content,
				replyRef
			)
		else
			ui.addMessage(
				msg.sender,
				msg.timestamp,
				msg.content,
				msg.imageUrl,
				replyRef
			)
		end
	end

	-- The open conversation: its folder's listeners, and which message
	-- folders are already shown (a message can show up both in the initial
	-- listing and in ChildAdded).
	local boundFolder: Folder? = nil
	local bindings: {RBXScriptConnection} = {}
	local shown: {[Instance]: boolean} = {}

	local function unbind()
		for _, connection in ipairs(bindings) do
			connection:Disconnect()
		end
		table.clear(bindings)
		boundFolder = nil
		shown = {}
	end

	local function showMessage(child)
		if shown[child] then return end
		shown[child] = true
		renderEntry(chatNetwork.readEntry(child))

		if child:GetAttribute("MessageType") == "Poll" then
			table.insert(bindings, Lifetime.connect(child:GetAttributeChangedSignal("Votes"), function()
				local entry = chatNetwork.readEntry(child)
				if entry.pollData then
					ui.updatePollMessage(entry.timestamp, entry.pollData)
				end
			end))
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

		table.insert(bindings, Lifetime.connect(folder.ChildAdded, function(child)
			showMessage(child)
			markActiveRead()
		end))
		-- Keep the UI in sync when messages are removed, whether deleted
		-- locally or by another collaborator.
		table.insert(bindings, Lifetime.connect(folder.ChildRemoved, function(child)
			shown[child] = nil
			local ts = child:GetAttribute("Timestamp")
			if ts then
				ui.removeMessage(ts)
			end
		end))
	end

	local function refreshConversationList()
		ui.setConversations(Conversations.list(), Conversations.getActiveId())
	end

	-- Typing status is only shared in the team chat.
	local function showTypingUsers(names)
		if Conversations.getActiveId() == Conversations.MAIN then
			ui.setTypingUsers(names)
		else
			ui.setTypingUsers({})
		end
	end

	local function openConversation(id: string)
		Conversations.setActive(id)
		local folder = Conversations.getFolder(id, false)
		if folder then
			bindFolder(folder)
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
			ui.setReplyReference(timestamp, sender, content)
		end
	end)

	ui.onDelete(function(timestamp)
		chatNetwork.deleteMessage(timestamp)
	end)

	-- Typing indicator: publish local typing activity (team chat only) and
	-- display others'
	if ui.onTypingActivity and chatNetwork.setTyping then
		ui.onTypingActivity(function(isTyping)
			chatNetwork.setTyping(isTyping and Conversations.getActiveId() == Conversations.MAIN)
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