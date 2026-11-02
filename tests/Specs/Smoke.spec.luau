--[[
	End-to-end smoke test: boots the whole plugin (see Harness) and drives the
	main features through the same APIs the UI uses.
]]

local Harness = require(script.Parent.Parent.Harness)

local function texts(gui: Instance): string
	local list = gui:FindFirstChild("MessageList", true)
	local rows = {}
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local out = {}
	for _, row in ipairs(rows) do
		local label = row:FindFirstChild("TextContent") or row:FindFirstChild("Body") or row:FindFirstChild("Question")
		table.insert(out, if label then (label :: TextLabel).ContentText else row.Name)
	end
	return table.concat(out, " | ")
end

return function(t)
	-- Record every error/warning Studio prints while the plugin runs and after it stops
	local LogService = game:GetService("LogService")
	local problems = {}
	local logConnection = LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageError or messageType == Enum.MessageType.MessageWarning then
			table.insert(problems, message)
		end
	end)

	local app = Harness.boot()
	local ok, err = pcall(function()
		local gui = app.gui
		Harness.settle()

		t.check(
			"window built (sidebar + message list)",
			gui:FindFirstChild("Sidebar") ~= nil and gui:FindFirstChild("MessageList", true) ~= nil
		)
		t.check(
			"toolbar buttons created",
			app.toolbarButtons.ToggleTeamChat ~= nil and app.toolbarButtons.ToggleTeamChatSettings ~= nil
		)

		-- Text message
		app.chat.sendMessage("hello smoke test")
		Harness.settle()
		t.check("sent message shows: " .. texts(gui), string.find(texts(gui), "hello smoke test", 1, true) ~= nil)

		-- Typed command through the message box (Enter = typed newline)
		local box = app.ui.textBox
		box.Text = "/help"
		Harness.settle(2)
		box.Text = "/help\n"
		Harness.settle()
		local helpCard = false
		for _, label in ipairs(gui:FindFirstChild("MessageList", true):GetDescendants()) do
			if
				label.Name == "Title"
				and label:IsA("TextLabel")
				and string.find(label.Text, "Available commands", 1, true)
			then
				helpCard = true
			end
		end
		t.check("/help typed in the box runs (its command list card shows)", helpCard and box.Text == "")

		-- Poll + vote
		app.chat.sendPoll("Lunch?", { "Pizza", "Sushi" })
		Harness.settle()
		local poll
		for _, child in ipairs(app.chat.getFolder():GetChildren()) do
			if child:GetAttribute("MessageType") == "Poll" then
				poll = child
			end
		end
		t.check("poll stored", poll ~= nil)
		app.chat.castVote(poll:GetAttribute("Timestamp"), 2)
		Harness.settle()
		t.check("vote stored", string.find(poll:GetAttribute("Votes"), app.chat.getUsername(), 1, true) ~= nil)

		-- File card
		app.ui.addFileMessage("Tester", os.time() + 5, "Module.luau", "rbxtemp://1", "Script", "")
		Harness.settle()
		local card = gui:FindFirstChild("FileCard", true)
		t.check("file card renders", card ~= nil and card:FindFirstChild("FileName") ~= nil)

		-- Direct message
		local conversations = app.chat.Conversations
		local dmId = conversations.startDm(156, "builderman")
		t.check("DM started", dmId ~= nil)
		Harness.settle()
		local before = #app.chat.getFolder():GetChildren()
		conversations.setActive(dmId)
		app.chat.sendMessage("psst")
		Harness.settle()
		local dmFolder = conversations.getFolder(dmId, false)
		t.check("DM message stored in the DM folder", dmFolder ~= nil and #dmFolder:GetChildren() == 1)
		t.equal("team chat untouched by the DM", #app.chat.getFolder():GetChildren(), before)
		conversations.setActive(conversations.MAIN)

		-- Shutdown
		local lifetime = require(app.copy.Core.Lifetime) :: any
		app.app.stop()
		t.check("stop() marks the lifetime dead", lifetime.alive == false)
	end)
	app.stop()
	task.wait(0.5) -- deferred work queued before the stop must not print anything
	logConnection:Disconnect()
	t.check(
		"no errors or warnings in Output on load, use and unload: " .. table.concat(problems, " | "),
		#problems == 0
	)
	if not ok then
		error(err, 0)
	end
end
