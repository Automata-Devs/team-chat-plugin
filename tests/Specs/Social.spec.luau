--[[
	Typing in DMs, deleting only your own messages and unread counts (title,
	"New" line).
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui, chat, gui = app.ui, app.chat, app.gui
		local hooks = app.hooks
		local list = gui:FindFirstChild("MessageList", true)
		local folder = chat.getFolder()
		local me = chat.getUserId()
		local Typing = require(app.copy.Services.Chat.Typing) :: any
		local Conversations = require(app.copy.Services.Chat.Conversations) :: any
		local Constants = require(app.copy.Config.Constants) :: any

		local function rowFor(timestamp: number): Frame?
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("GuiObject") and child:GetAttribute("Timestamp") == timestamp then
					return child :: Frame
				end
			end
			return nil
		end
		local function addOther(timestamp: number, content: string, parent: Instance?): Instance
			local other = Instance.new("Folder")
			other.Name = "msg_" .. tostring(timestamp)
			other:SetAttribute("Sender", "builderman")
			other:SetAttribute("SenderId", 156)
			other:SetAttribute("Timestamp", timestamp)
			other:SetAttribute("Content", content)
			other:SetAttribute("MessageType", "Text")
			other.Parent = parent or folder
			return other
		end

		-- Typing: each conversation shows only its own typers
		local dm = Conversations.dmId(me, 156)
		Typing.simulateTyping("DM Tester", 1, dm)
		Harness.settle()
		t.check("typing in a DM shows in that DM", table.find(Typing.getTypingUsers(dm), "DM Tester") ~= nil)
		t.check(
			"…and not in the team chat",
			table.find(Typing.getTypingUsers(Conversations.MAIN), "DM Tester") == nil
		)
		Typing.setTyping(true, dm)
		local typingFolder = folder.Parent:FindFirstChild("TeamChatTyping")
		local mine = typingFolder and typingFolder:FindFirstChild("typing_" .. tostring(me))
		t.equal("my typing says which conversation", mine and mine:GetAttribute("Conversation"), dm)
		Typing.setTyping(true, Conversations.MAIN)
		t.equal("switching conversation moves it", mine and mine:GetAttribute("Conversation"), Conversations.MAIN)
		Typing.setTyping(false)

		-- Delete: only your own messages
		local stamp = os.time() + 500
		local theirs = addOther(stamp, "their message")
		Harness.settle()
		chat.deleteMessage(stamp)
		Harness.settle()
		t.check("someone else's message can't be deleted", theirs.Parent == folder)
		chat.sendMessage("delete me")
		Harness.settle()
		local own
		for _, child in ipairs(folder:GetChildren()) do
			if child:GetAttribute("Content") == "delete me" then
				own = child
			end
		end
		chat.deleteMessage(own:GetAttribute("Timestamp"))
		Harness.settle()
		t.check("my own message can", own.Parent == nil)
		local menu = hooks.contextMenu
		local deleteItem = menu.frame:FindFirstChild("DeleteItem") :: TextButton
		menu.show(stamp, { canEdit = false, canDelete = false })
		t.check(
			"Delete is hidden on others' messages",
			not deleteItem.Visible and not (menu.frame:FindFirstChild("Divider") :: Frame).Visible
		)
		menu.show(stamp, { canEdit = true, canDelete = true })
		t.check("…and shown on mine", deleteItem.Visible)
		menu.hide()

		local row = rowFor(stamp) :: Frame

		-- Unread: the first unread message and the "New" line
		local dmFolder = Conversations.getFolder(dm, true)
		local unreadAt = os.time() + 600
		addOther(unreadAt + 5, "second", dmFolder)
		addOther(unreadAt, "first", dmFolder)
		t.equal("first unread is the oldest one from others", Conversations.firstUnread(dm), unreadAt)
		Conversations.markRead(dm)
		t.equal("nothing unread after reading", Conversations.firstUnread(dm), nil)
		dmFolder:Destroy()

		ui.showUnreadDivider(stamp)
		Harness.settle()
		local divider = list:FindFirstChild("UnreadDivider") :: Frame
		t.check("the New line shows", divider ~= nil)
		t.check(
			"…just above the first unread message",
			divider ~= nil
				and divider.LayoutOrder < row.LayoutOrder
				and divider.AbsolutePosition.Y < row.AbsolutePosition.Y
		)
		t.equal("…and says NEW", divider and (divider:FindFirstChild("Tag") :: TextLabel).Text, "NEW")
		ui.showUnreadDivider(nil)
		t.check("it can be removed", list:FindFirstChild("UnreadDivider") == nil)

		-- The widget's title counts every unread message
		local base = Constants.PLUGIN_TITLE .. " " .. Constants.PLUGIN_VERSION
		local entries = Conversations.list()
		local copies = {}
		for i, entry in ipairs(entries) do
			local copy = table.clone(entry)
			copy.unread = if i == 1 then 4 else 0
			table.insert(copies, copy)
		end
		ui.setConversations(copies, Conversations.getActiveId())
		t.equal("unread messages show in the title", hooks.title, "(4) " .. base)
		copies[1].unread = 0
		ui.setConversations(copies, Conversations.getActiveId())
		t.equal("…and leave it when read", hooks.title, base)

		-- Dragging something that isn't a chat attachment over the window (an
		-- Explorer item, a file) comes with no drag data: nothing happens
		local dragErrors = {}
		local logConnection = game:GetService("LogService").MessageOut:Connect(function(message, kind)
			if kind == Enum.MessageType.MessageError and string.find(message, "__TeamChatUnderTest", 1, true) then
				table.insert(dragErrors, message)
			end
		end)
		hooks.events.PluginDragEntered:Fire(nil)
		hooks.events.PluginDragDropped:Fire(nil)
		hooks.events.PluginDragEntered:Fire({ MimeType = "text/plain" })
		Harness.settle(3)
		logConnection:Disconnect()
		t.check("drags without attachment data are ignored: " .. table.concat(dragErrors, "; "), #dragErrors == 0)

		-- The unread badge is a solid circle: its ring goes round the badge, not
		-- the number (same for the scroll-to-bottom button's outline)
		local badges, textStrokes = 0, {}
		for _, item in ipairs(gui:GetDescendants()) do
			if item.Name == "Badge" and item:IsA("TextLabel") and item.Parent and item.Parent.Name == "Avatar" then
				badges += 1
			end
			if
				item:IsA("UIStroke") and item.Parent and item.Parent:IsA("TextLabel")
				or item:IsA("UIStroke") and item.Parent and item.Parent:IsA("TextButton")
			then
				if item.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Border then
					table.insert(textStrokes, item:GetFullName())
				end
			end
		end
		t.check("the sidebar has unread badges to check (" .. badges .. ")", badges > 0)
		t.check("no outline is drawn round text by mistake: " .. table.concat(textStrokes, ", "), #textStrokes == 0)

		theirs:Destroy()
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
