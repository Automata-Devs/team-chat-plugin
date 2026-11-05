--[[
	Pinned messages: pinning from the right-click menu (saved on the
	message, with a notice), the pin button and panel in the header,
	unpinning, and pins surviving a history backup.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui, chat, gui, hooks = app.ui, app.chat, app.gui, app.hooks
		local folder = chat.getFolder()

		local function stored(content: string): Instance?
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("Content") == content then
					return child
				end
			end
			return nil
		end

		chat.sendMessage("the plan: **ship it** on friday")
		Harness.settle()
		local message = stored("the plan: **ship it** on friday") :: Instance
		local timestamp = message:GetAttribute("Timestamp")
		task.wait(1.1) -- messages are found by their time (to the second)

		-- The right-click menu offers Pin Message, then Unpin Message
		local menu = hooks.contextMenu
		menu.show(timestamp, { canPin = true, pinned = false })
		local pinItem = menu.frame:FindFirstChild("Pin MessageItem") :: TextButton
		local unpinItem = menu.frame:FindFirstChild("Unpin MessageItem") :: TextButton
		t.check("Pin Message shows in the menu", pinItem ~= nil and pinItem.Visible and not unpinItem.Visible)
		menu.show(timestamp, { canPin = true, pinned = true })
		t.check("…Unpin Message once it's pinned", unpinItem.Visible and not pinItem.Visible)
		menu.hide()

		-- Pinning (as the menu does)
		local before = #folder:GetChildren()
		menu.handlers.pin(timestamp, true)
		Harness.settle()
		t.check("pinning saves it on the message", message:GetAttribute("Pinned") == true)
		t.equal("…with who pinned it", message:GetAttribute("PinnedBy"), chat.getUserId())
		t.equal("…and posts a notice", #folder:GetChildren(), before + 1)
		local notice
		for _, child in ipairs(folder:GetChildren()) do
			if child:GetAttribute("Notice") == "pin" then
				notice = child
			end
		end
		t.check(
			"…from Team Chat, saying who pinned",
			notice ~= nil
				and notice:GetAttribute("Sender") == "System"
				and string.find(notice:GetAttribute("Content"), "pinned a message", 1, true) ~= nil
		)

		-- The header's pin button opens the list
		local button = gui:FindFirstChild("PinsButton", true) :: TextButton
		t.check("the header has a pin button", button ~= nil and button.Visible)
		ui.pinsPanel.open()
		Harness.settle(4)
		local panel = gui:FindFirstChild("PinsPanel", true) :: Frame
		local card = panel and panel:FindFirstChild("Pin_" .. tostring(timestamp), true)
		t.check("the pin panel lists the pinned message", panel ~= nil and panel.Visible and card ~= nil)
		local text = card and card:FindFirstChild("TextContent", true) :: TextLabel
		t.check("…with its markdown", text ~= nil and string.find(text.Text, "<b>ship it</b>", 1, true) ~= nil)
		t.check(
			"…and Jump and Unpin",
			card ~= nil and card:FindFirstChild("Jump", true) ~= nil and card:FindFirstChild("Unpin", true) ~= nil
		)

		-- Pins survive a history backup
		local ChatState = require(app.copy.Services.Chat.ChatState) :: any
		local json = ChatState.serializeMessages()
		t.check("pins are kept in the backup", json ~= nil and string.find(json, '"pinned":true', 1, true) ~= nil)

		-- Unpinning (as the panel's Unpin does)
		menu.handlers.pin(timestamp, false)
		Harness.settle(4)
		t.check(
			"unpinning clears it",
			message:GetAttribute("Pinned") == nil and message:GetAttribute("PinnedBy") == nil
		)
		t.check(
			"…and the panel shows it's empty",
			panel:FindFirstChild("Pin_" .. tostring(timestamp), true) == nil
				and panel:FindFirstChild("Empty", true) ~= nil
		)
		ui.pinsPanel.close()
		t.check("the panel closes", not panel.Visible)

		-- Only saved messages can be pinned
		local pinned, problem = chat.Pins.set(12345, true)
		t.check(
			"a message that isn't saved can't be pinned: " .. tostring(problem),
			not pinned and problem == "notFound"
		)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
