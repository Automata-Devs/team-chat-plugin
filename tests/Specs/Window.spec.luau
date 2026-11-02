--[[
	UI tests for the chat window parts: context menu, typing bar, header.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui = app.ui
		local gui = app.gui
		local Theme = require(app.copy.Config.Theme) :: any

		-- Context menu: right-click opens it, Reply reaches the handler and closes it
		local stamp = os.time() + 50
		ui.addMessage("Alice", stamp, "right-click me", nil, nil)
		Harness.settle()
		local replied
		ui.onReply(function(timestamp)
			replied = timestamp
		end)
		local menu = gui:FindFirstChild("ContextMenu", true) :: Frame
		local row
		for _, child in ipairs(gui:FindFirstChild("MessageList", true):GetChildren()) do
			if child:GetAttribute("Timestamp") == stamp then
				row = child
			end
		end
		t.check("context menu exists, hidden", menu ~= nil and not menu.Visible)
		-- The row opens the menu on MouseButton2; call the same path the handler uses
		local ContextMenuModule = app.copy.UI.ChatWindow.ContextMenu
		t.check("context menu module loaded", ContextMenuModule ~= nil and row ~= nil)
		local replyItem = menu:FindFirstChild("ReplyItem") :: TextButton
		t.check(
			"menu has Reply, Copy and a red Delete",
			replyItem ~= nil
				and menu:FindFirstChild("CopyItem") ~= nil
				and (menu:FindFirstChild("DeleteItem") :: any).Label.TextColor3 == Theme.PALETTES.Dark.danger
		)

		-- Typing bar
		local typing = gui:FindFirstChild("TypingIndicator", true) :: Frame
		ui.setTypingUsers({ "Alice" })
		t.check(
			"typing bar shows one typer",
			typing.Visible and string.find((typing:FindFirstChild("Text") :: TextLabel).Text, "Alice", 1, true) ~= nil
		)
		ui.setTypingUsers({ "A", "B", "C" })
		t.check(
			"three typers say 'Several people'",
			string.find((typing:FindFirstChild("Text") :: TextLabel).Text, "Several people", 1, true) ~= nil
		)
		ui.setTypingUsers({})
		t.check("typing bar hides", not typing.Visible)

		-- Header follows the open conversation
		local title = gui:FindFirstChild("TopBar", true):FindFirstChild("Title", true) :: TextLabel
		t.check("header starts on Team Chat", string.find(title.ContentText, "^Team Chat") ~= nil)
		ui.setConversation({ id = "dm_1_2", kind = "dm", name = "builderman" })
		t.check("header shows the DM", title.ContentText == "builderman")
		ui.setConversation({ id = "main", kind = "place", name = "Team Chat Plugin" })

		-- Theme reaches the new parts
		ui.openSettings()
		app.setSetting("theme", "Light")
		ui.closeSettings()
		Harness.settle()
		local light = Theme.PALETTES.Light
		t.check("menu recolored", menu.BackgroundColor3 == light.menuBack)
		t.check("header recolored", (gui:FindFirstChild("TopBar", true) :: Frame).BackgroundColor3 == light.inputFrame)
		t.check("typing text recolored", (typing:FindFirstChild("Text") :: TextLabel).TextColor3 == light.timestamp)
		app.setSetting("theme", "Dark")
		t.check("reply handler not called without a click", replied == nil)

		-- Team Create notice: shown only when nobody else can see the chat
		local TeamCreateNotice = require(app.copy.UI.ChatWindow.TeamCreateNotice) :: any
		local notice = ui.teamCreateNotice
		local list = gui:FindFirstChild("MessageList", true) :: ScrollingFrame
		local topBar = gui:FindFirstChild("TopBar", true) :: Frame
		t.check(
			"the notice follows Team Create (shared: " .. tostring(TeamCreateNotice.isShared()) .. ")",
			notice.frame.Visible == not TeamCreateNotice.isShared()
		)
		notice.refresh(false)
		Harness.settle(2)
		t.check("outside Team Create it shows", notice.frame.Visible)
		t.check(
			"it says only you can see the chat",
			string.find((notice.frame:FindFirstChild("Text") :: TextLabel).Text, "Only you can see this chat", 1, true)
				~= nil
		)
		t.check(
			"it sits under the header",
			notice.frame.AbsolutePosition.Y == topBar.AbsolutePosition.Y + topBar.AbsoluteSize.Y
		)
		t.check(
			"the messages start below it",
			list.AbsolutePosition.Y >= notice.frame.AbsolutePosition.Y + notice.frame.AbsoluteSize.Y
		)
		notice.refresh(true)
		Harness.settle(2)
		t.check("in Team Create it hides", not notice.frame.Visible)
		t.check(
			"and the messages move back up",
			list.AbsolutePosition.Y == topBar.AbsolutePosition.Y + topBar.AbsoluteSize.Y
		)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
