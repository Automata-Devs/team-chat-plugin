--[[
	UI tests for the message list: every kind of row renders, polls update,
	reply lines jump to the original, and theme / text size changes reach
	existing rows.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui = app.ui
		local gui = app.gui
		local list = gui:FindFirstChild("MessageList", true)
		local base = os.time() + 100

		local function row(timestamp: number): Frame?
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("GuiObject") and child:GetAttribute("Timestamp") == timestamp then
					return child :: Frame
				end
			end
			return nil
		end

		ui.addMessage("Alice", base, "original message", nil, nil)
		ui.addAnnouncementMessage("Alice", base + 1, "Server restart at 5", nil)
		ui.addPollMessage(
			"Alice",
			base + 2,
			{ question = "Tabs or spaces?", options = { "Tabs", "Spaces" }, votes = { {}, {} } },
			nil
		)
		ui.addMessage(
			"Bob",
			base + 3,
			"replying",
			nil,
			{ timestamp = base, sender = "Alice", content = "original message" }
		)
		Harness.settle()

		local announcement = row(base + 1)
		t.check(
			"announcement renders with its body",
			announcement ~= nil
				and announcement:FindFirstChild("Body", true) ~= nil
				and (announcement:FindFirstChild("Body", true) :: TextLabel).Text == "Server restart at 5"
		)

		local poll = row(base + 2)
		t.check(
			"poll card renders its question",
			poll ~= nil and (poll:FindFirstChild("Question", true) :: TextLabel).Text == "Tabs or spaces?"
		)
		ui.updatePollMessage(
			base + 2,
			{ question = "Tabs or spaces?", options = { "Tabs", "Spaces" }, votes = { { "Alice", "Bob" }, {} } }
		)
		Harness.settle()
		local summary = poll and poll:FindFirstChild("VoteSummary", true)
		t.check(
			"poll summary updates on votes: " .. (if summary then (summary :: TextLabel).Text else "?"),
			summary ~= nil and string.find((summary :: TextLabel).Text, "2", 1, true) ~= nil
		)

		local reply = row(base + 3)
		t.check("reply line shows above the reply", reply ~= nil and reply:FindFirstChild("ReplyReference") ~= nil)
		local Shared = require(app.copy.UI.Messages.Shared) :: any
		t.check("jump handler is wired", Shared.jumpToMessage ~= nil)
		Shared.jumpToMessage(base)
		task.wait(0.1)
		local original = row(base) :: Frame
		t.check("jumping flashes the original", original.BackgroundTransparency < 1)

		-- Discord-style author header with avatar
		ui.addMessage("D3veloperHac", base + 4, "This is a message", nil, nil, 7091790691)
		ui.addMessage("NoId", base + 5, "", "rbxassetid://1", nil, nil)
		ui.addSystemMessage("system note")
		Harness.settle()
		local mine = row(base + 4) :: Frame
		local author = mine:FindFirstChild("Author")
		local authorLabel = author and author:FindFirstChild("AuthorLabel", true) :: TextLabel
		local timeLabel = author and author:FindFirstChild("TimeLabel", true) :: TextLabel
		t.check(
			"author header shows name and time: " .. (if authorLabel then authorLabel.ContentText else "?"),
			authorLabel ~= nil
				-- The display name once the profile is loaded, else the username
				and authorLabel.ContentText == (require(app.copy.UI.Messages.Author) :: any).nameOf(
					"D3veloperHac",
					7091790691
				)
				and timeLabel ~= nil
				and string.find(timeLabel.Text, "%d") ~= nil
		)
		t.equal(
			"text label holds only the message",
			(mine:FindFirstChild("TextContent") :: TextLabel).ContentText,
			"This is a message"
		)
		local avatar = author and author:FindFirstChild("Avatar") :: ImageLabel
		t.check(
			"avatar is the sender's headshot",
			avatar ~= nil and string.find(avatar.Image, "AvatarHeadShot&id=7091790691", 1, true) ~= nil
		)
		t.check(
			"avatar sits left of the text, inside the row",
			avatar ~= nil
				and avatar.AbsolutePosition.X < (mine:FindFirstChild("TextContent") :: TextLabel).AbsolutePosition.X
				and avatar.AbsolutePosition.X >= mine.AbsolutePosition.X
		)
		local imageOnly = row(base + 5) :: Frame
		t.check(
			"image-only message hides the empty text line",
			not (imageOnly:FindFirstChild("TextContent") :: TextLabel).Visible
		)
		t.check(
			"unknown sender gets an initial badge",
			(imageOnly:FindFirstChild("Badge", true) :: TextLabel).Text == "N"
		)
		local systemBadge
		for _, child in ipairs(list:GetChildren()) do
			if child:GetAttribute("Sender") == "System" then
				systemBadge = child:FindFirstChild("Badge", true)
			end
		end
		t.check("system messages get the code badge", systemBadge ~= nil and systemBadge.Text == "code")

		-- Reply line: curved line + mini avatar of the original author
		ui.addMessage(
			"Bob",
			base + 6,
			"reply with id",
			nil,
			{ timestamp = base + 4, sender = "D3veloperHac", content = "This is a message", senderId = 7091790691 },
			156
		)
		Harness.settle()
		local replyRow = (row(base + 6) :: Frame):FindFirstChild("ReplyReference") :: Frame
		t.check(
			"reply line has the curved line",
			replyRow:FindFirstChild("Spine") ~= nil and replyRow:FindFirstChild("ReplyIcon") == nil
		)
		local mini = replyRow:FindFirstChild("MiniAvatar") :: ImageLabel
		t.check("mini avatar shows the original author", string.find(mini.Image, "id=7091790691", 1, true) ~= nil)
		local nameColor = (require(app.copy.Util.UsernameColors) :: any).getNameColor("D3veloperHac")
		t.check(
			"behind the headshot is the plain avatar background, not the name colour",
			mini.BackgroundColor3 ~= nameColor
		)
		t.check(
			"the mini avatar is a little see-through",
			mini.ImageTransparency > 0 and mini.ImageTransparency <= 0.3 and mini.BackgroundTransparency > 0
		)
		local spine = replyRow:FindFirstChild("Spine") :: Frame
		local bigAvatar = (row(base + 6) :: Frame):FindFirstChild("Avatar", true) :: ImageLabel
		local avatarCenter = bigAvatar.AbsolutePosition.X + bigAvatar.AbsoluteSize.X / 2
		t.check(
			("curved line starts above the avatar (line x %d, avatar center %d)"):format(
				spine.AbsolutePosition.X,
				avatarCenter
			),
			math.abs(spine.AbsolutePosition.X - avatarCenter) <= 1
		)
		local spineBottom = spine.AbsolutePosition.Y + spine.AbsoluteSize.Y
		t.check(
			("it stops just above the avatar (gap %d)"):format(bigAvatar.AbsolutePosition.Y - spineBottom),
			bigAvatar.AbsolutePosition.Y - spineBottom >= 2 and bigAvatar.AbsolutePosition.Y - spineBottom <= 4
		)
		local spineEnd = spine.AbsolutePosition.X + spine.AbsoluteSize.X
		t.check(
			("…and just before the mini avatar (gap %d)"):format(mini.AbsolutePosition.X - spineEnd),
			mini.AbsolutePosition.X - spineEnd >= 2 and mini.AbsolutePosition.X - spineEnd <= 6
		)
		t.check(
			"the line is level with the mini avatar",
			math.abs(spine.AbsolutePosition.Y - (mini.AbsolutePosition.Y + mini.AbsoluteSize.Y / 2)) <= 1
		)
		t.check("the line is a Path2D", spine:FindFirstChild("Line") ~= nil and spine.Line:IsA("Path2D"))
		-- Older reply without the id: filled in from the original message
		ui.addMessage(
			"Bob",
			base + 7,
			"old style reply",
			nil,
			{ timestamp = base + 4, sender = "D3veloperHac", content = "This is a message" },
			156
		)
		task.wait(1.3)
		local oldMini = (row(base + 7) :: Frame):FindFirstChild("MiniAvatar", true) :: ImageLabel
		t.check(
			"old replies get the avatar from the original",
			string.find(oldMini.Image, "id=7091790691", 1, true) ~= nil
		)

		-- Theme: Light palette reaches existing rows
		local Theme = require(app.copy.Config.Theme) :: any
		ui.openSettings()
		app.setSetting("theme", "Light")
		ui.closeSettings()
		Harness.settle()
		local text = original:FindFirstChild("TextContent") :: TextLabel
		t.check("light theme recolors existing messages", text.TextColor3 == Theme.PALETTES.Light.messageText)
		app.setSetting("theme", "Dark")

		-- Text size: Large reaches existing rows
		app.setSetting("textSize", 16)
		Harness.settle()
		t.equal("text size applied to existing messages", text.TextSize, 16)
		app.setSetting("textSize", 14)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
