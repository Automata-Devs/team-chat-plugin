--[[
	Team Chat's bot messages: private ones only you see ("Only you can see
	this · Dismiss message") and public ones saved for everyone, under
	"<name> used /command", with their card.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui, chat, gui = app.ui, app.chat, app.gui
		local list = gui:FindFirstChild("MessageList", true)
		local folder = chat.getFolder()
		local me = chat.getUserId()
		local ChatState = require(app.copy.Services.Chat.ChatState) :: any

		local function waitFor(condition: () -> boolean, seconds: number): boolean
			local deadline = os.clock() + seconds
			while os.clock() < deadline do
				if condition() then
					return true
				end
				task.wait(0.1)
			end
			return condition()
		end

		-- Private: only you see it, and it says so
		local private = ui.addSystemMessage("just for you")
		Harness.settle()
		local note = private:FindFirstChild("OnlyYouNote")
		t.check("a private bot message says only you can see it", note ~= nil)
		t.check(
			"…with a Dismiss message link",
			note ~= nil and (note:FindFirstChild("Dismiss") :: TextButton).Text == "Dismiss message"
		)
		local savedPrivate = false
		for _, child in ipairs(folder:GetChildren()) do
			savedPrivate = savedPrivate or child:GetAttribute("Content") == "just for you"
		end
		t.check("…and isn't saved", not savedPrivate)

		-- Public: /coinflip posts for everyone
		local before = {}
		for _, child in ipairs(folder:GetChildren()) do
			before[child] = true
		end
		ui.textBox.Text = "/coinflip"
		Harness.settle()
		ui.textBox.Text = "/coinflip\n"
		local saved
		waitFor(function()
			for _, child in ipairs(folder:GetChildren()) do
				if not before[child] and child:GetAttribute("Sender") == "System" then
					saved = child
				end
			end
			return saved ~= nil
		end, 5)
		t.check("a public bot message is saved in the chat", saved ~= nil)
		if saved then
			t.equal("…from Team Chat, run by you", saved:GetAttribute("SaidBy"), me)
			t.equal("…naming the command", saved:GetAttribute("Command"), "/coinflip")
			t.check("…with its card", type(saved:GetAttribute("Embed")) == "string")

			local timestamp = saved:GetAttribute("Timestamp")
			local row
			waitFor(function()
				for _, child in ipairs(list:GetChildren()) do
					if child:GetAttribute("BotMessage") and child:GetAttribute("Timestamp") == timestamp then
						row = child
					end
				end
				return row ~= nil
			end, 3)
			t.check("it shows in the chat", row ~= nil)
			if row then
				local used = row:FindFirstChild("ReplyLabel", true) :: TextLabel
				t.check(
					'…under "<you> used /coinflip": ' .. (if used then used.ContentText else "?"),
					used ~= nil and string.find(used.ContentText, "used /coinflip", 1, true) ~= nil
				)
				t.check("…with the card", row:FindFirstChild("Embed") ~= nil)
				t.check("…and no Only you line", row:FindFirstChild("OnlyYouNote") == nil)
			end

			t.check(
				"it's kept in the chat history",
				string.find(ChatState.serializeMessages() or "", "/coinflip", 1, true) ~= nil
			)

			chat.deleteMessage(timestamp)
			Harness.settle()
			t.check("whoever ran it can delete it", saved.Parent == nil)
		end
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
