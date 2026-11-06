--[[
	Emoji reactions (Add Reaction in the right-click menu, the picker, the
	pills under a message) and the unread count in the window's title and on
	the toolbar button.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot({ settings = { TeamChatAboutSeen_v1 = true, TeamChatLastSeenVersion_v1 = "x" } })
	local ok, err = pcall(function()
		local ui, chat, gui, hooks = app.ui, app.chat, app.gui, app.hooks
		local ChatNetwork = require(app.copy.Services.Chat) :: any
		local ChatState = require(app.copy.Services.Chat.ChatState) :: any
		local Constants = require(app.copy.Config.Constants) :: any
		local ToolbarIcons = require(app.copy.Config.ToolbarIcons) :: any
		local Reactions = ChatNetwork.Reactions
		local Conversations = ChatNetwork.Conversations
		local HttpService = game:GetService("HttpService")
		local folder = chat.getFolder()

		local function messageWith(content: string): Instance?
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("Content") == content then
					return child
				end
			end
			return nil
		end
		local function rowOf(message: Instance): Frame?
			for _, row in ipairs(gui:GetDescendants()) do
				if row:IsA("Frame") and row:GetAttribute("MessageId") == message.Name then
					return row
				end
			end
			return nil
		end

		-- Two messages in the same second
		chat.sendMessage("react to me")
		chat.sendMessage("not me")
		Harness.settle(2)
		local target = messageWith("react to me") :: Instance
		local other = messageWith("not me") :: Instance
		local row = rowOf(target) :: Frame
		t.check("each message's row knows its message", row ~= nil and rowOf(other) ~= nil)

		-- Add Reaction in the right-click menu opens the picker
		local menu = hooks.contextMenu
		local timestamp = target:GetAttribute("Timestamp")
		menu.show(timestamp, { canReact = true, messageId = row:GetAttribute("MessageId") })
		t.check("the menu has Add Reaction", (menu.frame:FindFirstChild("Add ReactionItem") :: GuiObject).Visible)
		menu.show(timestamp, {})
		t.check(
			"…but not where you can't react",
			not (menu.frame:FindFirstChild("Add ReactionItem") :: GuiObject).Visible
		)
		menu.hide()
		menu.handlers.react(timestamp, row:GetAttribute("MessageId"))
		t.check("…which opens the emoji picker", ui.emojiPicker.isOpen())
		local picker = ui.emojiPicker.frame
		local grid = picker:FindFirstChild("Grid") :: ScrollingFrame
		local search = picker:FindFirstChild("Search") :: TextBox
		search.Text = "fire"
		Harness.settle()
		t.check(
			"searching shows only the matches",
			(grid:FindFirstChild("Emoji_fire") :: GuiObject).Visible
				and not (grid:FindFirstChild("Emoji_smile") :: GuiObject).Visible
		)
		search.Text = "nothingmatchesthis"
		Harness.settle()
		t.check("…and says when nothing does", (picker:FindFirstChild("Empty") :: GuiObject).Visible)
		ui.emojiPicker.pick("thumbsup")
		Harness.settle()
		t.check("picking one closes the picker", not ui.emojiPicker.isOpen())
		local saved = Reactions.read(target)
		t.check("…and reacts to that message", saved[1] ~= nil and saved[1].emoji == "👍" and saved[1].mine)
		t.check("…not the one sent in the same second", not Reactions.has(other))
		local bar = row:FindFirstChild("Reactions")
		t.check("the reaction shows under the message", bar ~= nil and bar:FindFirstChild("Reaction_1") ~= nil)
		t.check("…with a button to add another", bar ~= nil and bar:FindFirstChild("AddReaction") ~= nil)

		-- Someone else reacts with the same emoji: one pill, counted twice
		local list = HttpService:JSONDecode(target:GetAttribute("Reactions"))
		table.insert(list[1].u, 156)
		table.insert(list[1].n, "builderman")
		target:SetAttribute("Reactions", HttpService:JSONEncode(list))
		Harness.settle()
		local pill = row:FindFirstChild("Reactions") and row.Reactions:FindFirstChild("Reaction_1")
		t.equal("reactions from others count too", pill and pill:GetAttribute("Count"), 2)
		t.check("…and yours is marked", pill ~= nil and pill:GetAttribute("Mine") == true)

		-- Reacting again with it takes yours back
		local changed, added = Reactions.toggle(target.Name, "👍")
		Harness.settle()
		t.check("the same emoji again removes yours", changed and added == false)
		saved = Reactions.read(target)
		t.check("…and leaves theirs", saved[1] ~= nil and saved[1].count == 1 and not saved[1].mine)

		-- Saved with the history; emoji only
		Reactions.toggle(target.Name, "🔥")
		t.check(
			"reactions are saved with the chat history",
			string.find(ChatState.serializeMessages() or "", "reactions", 1, true) ~= nil
		)
		local refused, why = Reactions.toggle(target.Name, "lol")
		t.check("text isn't a reaction", not refused and why == "invalid")

		-- The last one gone: no bar
		target:SetAttribute("Reactions", nil)
		Harness.settle()
		t.check("no reactions, no bar", row:FindFirstChild("Reactions") == nil)

		-- Unread messages: in the window's title...
		local base = Constants.PLUGIN_TITLE .. " " .. Constants.PLUGIN_VERSION
		local copies = {}
		for i, entry in ipairs(Conversations.list()) do
			local copy = table.clone(entry)
			copy.unread = if i == 1 then 3 else 0
			table.insert(copies, copy)
		end
		ui.setConversations(copies, Conversations.getActiveId())
		t.equal("the title ends with the unread count", hooks.title, base .. " (3)")

		-- ...and on the toolbar button
		t.equal("the toolbar badge counts to 9", ToolbarIcons.forCount(4), ToolbarIcons.COUNTS[4])
		t.equal("…then shows 9+", ToolbarIcons.forCount(23), ToolbarIcons.MORE)
		t.equal("…and nothing when all is read", ToolbarIcons.forCount(0), ToolbarIcons.BASE)
		local me = chat.getUserId()
		local dm = Conversations.dmId(me, 156)
		local dmFolder = Conversations.getFolder(dm, true)
		for i = 1, 2 do
			local message = Instance.new("Folder")
			message.Name = "msg_unread_" .. i
			message:SetAttribute("Sender", "builderman")
			message:SetAttribute("SenderId", 156)
			message:SetAttribute("Timestamp", os.time() + 700 + i)
			message:SetAttribute("Content", "unread " .. i)
			message:SetAttribute("MessageType", "Text")
			message.Parent = dmFolder
		end
		Harness.settle(2)
		local button = app.toolbarButtons.ToggleTeamChat
		t.equal("a DM from someone puts the count on the toolbar button", button.Icon, ToolbarIcons.forCount(2))
		Conversations.markRead(dm)
		Harness.settle(2)
		t.equal("…which goes when it's read", button.Icon, ToolbarIcons.BASE)
		dmFolder:Destroy()
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
