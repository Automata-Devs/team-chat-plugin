--[[
	@mentions: finding them in text, their highlight in messages, the gold
	look on messages that mention you, and the Members picker in the
	message box.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui, chat, gui = app.ui, app.chat, app.gui
		local list = gui:FindFirstChild("MessageList", true)
		local folder = chat.getFolder()
		local Mentions = require(app.copy.Util.Mentions) :: any
		local RichText = require(app.copy.Util.RichText) :: any
		local Identity = require(app.copy.Core.Identity) :: any
		local Theme = require(app.copy.Config.Theme) :: any
		local me = Identity.username

		-- Finding mentions
		local found = Mentions.find("hi @builderman and @Roblox!")
		t.equal("finds each mention", #found, 2)
		t.equal("…with its name", found[1] and found[1].name, "builderman")
		t.equal("an email address isn't a mention", #Mentions.find("mail me at someone@site.com"), 0)
		t.equal("too short isn't a mention", #Mentions.find("@ab"), 0)
		t.check("mentions are any case", Mentions.mentions("hey @BUILDERMAN", "builderman"))
		t.check("@everyone mentions everyone", Mentions.mentions("@everyone look", "builderman"))
		t.check("someone else isn't you", not Mentions.mentions("hi @roblox", "builderman"))
		local at, partial = Mentions.typing("hello @bui")
		t.check("an @name being typed is found", at == 7 and partial == "bui")
		t.check("…but not in the middle of a word", Mentions.typing("hello a@bui") == nil)

		-- The highlight in message text
		local styled = RichText.styleContent("hi @builderman see www.roblox.com", Theme.PALETTES.Dark)
		local mentionColor = RichText.toHex(Theme.PALETTES.Dark.mentionText)
		t.check("a mention is coloured", string.find(styled, mentionColor, 1, true) ~= nil)
		t.check("…and links still are", string.find(styled, "<u>", 1, true) ~= nil)
		t.check(
			"no highlight without a mention",
			string.find(RichText.styleContent("mail@site.com"), mentionColor, 1, true) == nil
		)

		-- Messages that mention you get the gold look; others don't
		local function addOther(timestamp: number, content: string): Instance
			local message = Instance.new("Folder")
			message.Name = "msg_" .. tostring(timestamp)
			message:SetAttribute("Sender", "builderman")
			message:SetAttribute("SenderId", 156)
			message:SetAttribute("Timestamp", timestamp)
			message:SetAttribute("Content", content)
			message:SetAttribute("MessageType", "Text")
			message.Parent = folder
			return message
		end
		local function rowFor(timestamp: number): Frame?
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("GuiObject") and child:GetAttribute("Timestamp") == timestamp then
					return child :: Frame
				end
			end
			return nil
		end
		local stamp = os.time() + 700
		local mentioning = addOther(stamp, "hey @" .. me .. " look at this")
		local plain = addOther(stamp + 1, "hey @someoneelse")
		Harness.settle()
		local mentionRow = rowFor(stamp) :: Frame
		t.check(
			"a message mentioning you is marked",
			mentionRow ~= nil and mentionRow:GetAttribute("Mentioned") == true
		)
		t.check(
			"…with the gold tint and bar",
			mentionRow ~= nil
				and mentionRow:FindFirstChild("MentionGradient") ~= nil
				and mentionRow.BackgroundTransparency == 0
				and mentionRow.BackgroundColor3 == Theme.PALETTES.Dark.mentionRow -- the same gold in both themes
		)
		local plainRow = rowFor(stamp + 1) :: Frame
		t.check(
			"other messages aren't",
			plainRow ~= nil
				and plainRow:GetAttribute("Mentioned") ~= true
				and plainRow:FindFirstChild("MentionGradient") == nil
		)
		local mentionText = mentionRow:FindFirstChild("TextContent") :: TextLabel
		local pill
		for _ = 1, 30 do
			pill = mentionText:FindFirstChild("MentionPill") :: Frame
			if pill then
				break
			end
			task.wait(0.1)
		end
		t.check("the mention gets a rounded highlight", pill ~= nil and pill:FindFirstChildOfClass("UICorner") ~= nil)
		t.check(
			('…over the mention, after "hey " (x %d, width %d)'):format(
				pill and pill.Position.X.Offset or -1,
				pill and pill.Size.X.Offset or -1
			),
			pill ~= nil and pill.Position.X.Offset > 10 and pill.Size.X.Offset > 20
		)
		mentioning:SetAttribute("EditedAt", os.time())
		mentioning:SetAttribute("Content", "never mind")
		Harness.settle()
		t.check(
			"editing the mention out removes the look",
			mentionRow:GetAttribute("Mentioned") == false and mentionRow:FindFirstChild("MentionGradient") == nil
		)

		-- Display names count, and so do replies to your messages
		t.check(
			"a display name counts as a mention",
			Mentions.mentions("hey @Builder", { "builderman", "Builder" })
				and not Mentions.mentions("hey @Builder", "builderman")
		)
		local Shared = require(app.copy.UI.Messages.Shared) :: any
		local myNames = Shared.myNames()
		if #myNames > 1 then
			local byDisplay = addOther(stamp + 20, "hi @" .. myNames[2])
			Harness.settle()
			t.check(
				"a message mentioning your display name (@" .. myNames[2] .. ") is marked",
				(rowFor(stamp + 20) :: Frame):GetAttribute("Mentioned") == true
			)
			byDisplay:Destroy()
		end
		local myMessage = Instance.new("Folder")
		myMessage.Name = "msg_mine"
		myMessage:SetAttribute("Sender", me)
		myMessage:SetAttribute("SenderId", Identity.userId)
		myMessage:SetAttribute("Timestamp", stamp + 30)
		myMessage:SetAttribute("Content", "my message")
		myMessage:SetAttribute("MessageType", "Text")
		myMessage.Parent = folder
		local reply = Instance.new("Folder")
		reply.Name = "msg_reply"
		reply:SetAttribute("Sender", "builderman")
		reply:SetAttribute("SenderId", 156)
		reply:SetAttribute("Timestamp", stamp + 31)
		reply:SetAttribute("Content", "replying to @someoneelse and you")
		reply:SetAttribute("MessageType", "Text")
		reply:SetAttribute("ReplyToTimestamp", stamp + 30)
		reply:SetAttribute("ReplyToSender", me)
		reply:SetAttribute("ReplyToSenderId", Identity.userId)
		reply:SetAttribute("ReplyToContent", "my message, @" .. me)
		reply.Parent = folder
		Harness.settle()
		local replyRow = rowFor(stamp + 31) :: Frame
		t.check("a reply to your message gets the gold look", replyRow and replyRow:GetAttribute("Mentioned") == true)
		local replyLine = replyRow and replyRow:FindFirstChild("ReplyLabel", true) :: TextLabel
		t.check(
			"…and mentions in its reply line are coloured",
			replyLine ~= nil and string.find(replyLine.Text, "#5865F2", 1, true) ~= nil
		)
		local botReply = ui.addBotMessage({
			timestamp = stamp + 32,
			content = "bot says hi",
			saidBy = Identity.userId,
			saidByName = me,
			command = "/test",
		})
		t.check("a bot's \"you used /command\" line isn't a reply ping", botReply:GetAttribute("Mentioned") ~= true)
		botReply:Destroy()
		reply:Destroy()
		myMessage:Destroy()

		-- The Members picker
		local box = ui.textBox
		local menu = gui:FindFirstChild("Autocomplete", true) :: Frame
		local function rows(): { TextButton }
			local found = {}
			for _, child in ipairs(menu:GetChildren()) do
				if child:IsA("TextButton") and child.Name:match("^Item_%d+$") then
					table.insert(found, child)
				end
			end
			return found
		end
		box.Text = "hello @"
		Harness.settle()
		t.check("typing @ opens the Members list", menu.Visible)
		t.equal("…titled Members", (menu:FindFirstChild("Title") :: TextLabel).Text, "MEMBERS")
		local everyoneRow
		for _, row in ipairs(rows()) do
			if (row:FindFirstChild("CmdName") :: TextLabel).Text == "@everyone" then
				everyoneRow = row
			end
		end
		t.check("it offers @everyone", everyoneRow ~= nil)
		box.Text = "hello @" .. string.sub(me, 1, 3)
		Harness.settle()
		local mine
		for _, row in ipairs(rows()) do
			if (row:FindFirstChild("CmdDesc") :: TextLabel).Text == "@" .. me then
				mine = row
			end
		end
		t.check("typing a name finds people in the session", mine ~= nil)
		box.Text = "hello @" .. string.sub(me, 1, 3) .. "\t"
		Harness.settle()
		t.equal("Tab puts the mention in", box.Text, "hello @" .. me .. " ")
		box.Text = "hello @ever"
		Harness.settle()
		box.Text = "hello @ever\t"
		Harness.settle()
		t.equal("…and @everyone", box.Text, "hello @everyone ")
		local boxPill
		for _ = 1, 30 do
			boxPill = box:FindFirstChild("MentionPill")
			if boxPill then
				break
			end
			task.wait(0.1)
		end
		t.check("the message box highlights the mention while typing", boxPill ~= nil)
		box.Text = ""
		Harness.settle()
		t.check("the list closes", not menu.Visible)
		t.check("…and the highlight goes", box:FindFirstChild("MentionPill") == nil)

		mentioning:Destroy()
		plain:Destroy()
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
