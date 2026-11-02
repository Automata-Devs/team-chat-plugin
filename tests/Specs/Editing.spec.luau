--[[
	Editing your own messages: the right-click item, the composer flow,
	"(edited)", links after an edit, ownership checks and remote edits.
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

		local function rowFor(timestamp: number): Frame?
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("GuiObject") and child:GetAttribute("Timestamp") == timestamp then
					return child :: Frame
				end
			end
			return nil
		end
		local function stored(content: string): Instance?
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("Content") == content then
					return child
				end
			end
			return nil
		end

		chat.sendMessage("first version")
		Harness.settle()
		local message = stored("first version") :: Instance
		local timestamp = message:GetAttribute("Timestamp")
		t.check("own message stored with my id", message:GetAttribute("SenderId") == me and me > 0)

		-- Context menu: the Edit item only shows when allowed
		local menu = hooks.contextMenu
		menu.show(timestamp, { canEdit = true })
		local editItem = menu.frame:FindFirstChild("Edit MessageItem") :: TextButton
		t.check("Edit Message shows for my messages", editItem ~= nil and editItem.Visible)
		menu.show(timestamp, { canEdit = false })
		t.check("and is hidden otherwise", not editItem.Visible)
		menu.hide()

		-- Start editing: the text goes into the message box
		hooks.editing.start(timestamp)
		local box = ui.textBox
		local replyBar = gui:FindFirstChild("ReplyBar", true) :: Frame
		t.equal("message box holds the message", box.Text, "first version")
		t.check(
			"bar says Editing message",
			replyBar ~= nil
				and replyBar.Visible
				and string.find(
						(replyBar:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel).ContentText,
						"Editing message",
						1,
						true
					)
					~= nil
		)

		-- Save with Enter (a typed newline)
		local before = #folder:GetChildren()
		box.Text = "second version"
		Harness.settle(2)
		box.Text = "second version\n"
		Harness.settle()
		t.equal("edit saved", message:GetAttribute("Content"), "second version")
		t.check("edit time recorded", message:GetAttribute("EditedAt") ~= nil)
		t.equal("no new message sent", #folder:GetChildren(), before)
		t.check("box cleared and bar hidden", box.Text == "" and not replyBar.Visible)
		local row = rowFor(timestamp) :: Frame
		local text = (row:FindFirstChild("TextContent") :: TextLabel).ContentText
		t.check("row shows the new text with (edited): " .. text, text == "second version (edited)")

		-- A link added by an edit gets a preview
		hooks.editing.start(timestamp)
		box.Text = "now with www.roblox.com"
		Harness.settle(2)
		box.Text = "now with www.roblox.com\n"
		Harness.settle(6)
		t.check("link preview appears after the edit", row:FindFirstChild("Embed") ~= nil)

		-- Someone else's message can't be edited
		local other = Instance.new("Folder")
		other.Name = "msg_other"
		other:SetAttribute("Sender", "builderman")
		other:SetAttribute("SenderId", 156)
		other:SetAttribute("Timestamp", timestamp + 10)
		other:SetAttribute("Content", "not yours")
		other:SetAttribute("MessageType", "Text")
		other.Parent = folder
		Harness.settle()
		t.check("editing someone else's message is refused", chat.editMessage(timestamp + 10, "hacked") == false)
		t.equal("their text is unchanged", other:GetAttribute("Content"), "not yours")

		-- An edit made on another computer shows up live
		other:SetAttribute("EditedAt", os.time())
		other:SetAttribute("Content", "edited by builderman")
		Harness.settle()
		local otherText = ((rowFor(timestamp + 10) :: Frame):FindFirstChild("TextContent") :: TextLabel).ContentText
		t.equal("remote edit shows", otherText, "edited by builderman (edited)")

		-- Cancelling keeps the original
		hooks.editing.start(timestamp)
		box.Text = "never saved"
		ui.clearEditing()
		box.Text = ""
		t.equal("cancelled edit isn't saved", message:GetAttribute("Content"), "now with www.roblox.com")
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
