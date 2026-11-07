--[[
	Display names and verified badges outside messages (DM header, sidebar,
	reply lines), the version in the widget title, display settings, the new
	commands, the first-run About, the checkout and the full icon list.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui, gui, hooks = app.ui, app.gui, app.hooks
		local Preferences = require(app.copy.UI.Preferences) :: any
		local Icons = require(app.copy.Config.Icons) :: any
		local Constants = require(app.copy.Config.Constants) :: any

		-- First install: About opens instead of What's New, once
		Harness.settle(3)
		t.check("About opens on first install", (gui:FindFirstChild("AboutDialog", true) :: Frame).Visible)
		t.check("What's New doesn't also pop up", not (gui:FindFirstChild("ChangelogDialog", true) :: Frame).Visible)
		t.equal("About is remembered", app.settings[Constants.SETTING_KEY_ABOUT_SEEN], true)
		ui.closeSettings();
		(gui:FindFirstChild("AboutDialog", true) :: Frame).Visible = false

		-- Version: in the widget title, not the header
		t.equal(
			"widget title has the version",
			hooks.title,
			"Team Chat "
				.. Constants.PLUGIN_VERSION
				.. (if Constants.DEVELOPMENT_MODE then " \u{00B7} Development Mode" else "")
		)
		local headerText = ""
		for _, label in ipairs((gui:FindFirstChild("TopBar", true) :: Frame):GetDescendants()) do
			if label:IsA("TextLabel") then
				headerText ..= label.Text
			end
		end
		t.check("header has no version", not string.find(headerText, Constants.PLUGIN_VERSION, 1, true))

		-- A known profile for user 156 (display name differs from the username)
		ui.setProfileProvider(function(userId)
			if userId == 156 then
				return { displayName = "Cool Builder", verified = true }
			end
			return { verified = false }
		end)

		-- DM header: display name, verified badge, @username. The DM is made the
		-- active conversation, so the controller's own header refreshes (on any
		-- conversation change) keep showing it.
		local Conversations = require(app.copy.Services.Chat.Conversations) :: any
		local dmId = Conversations.dmId(app.chat.getUserId(), 156)
		-- Its name is looked up in the background: wait for it, as the
		-- controller's header shows that name
		for _ = 1, 50 do
			if Conversations.nameOf(156) == "builderman" then
				break
			end
			task.wait(0.1)
		end
		Conversations.setActive(dmId)
		ui.setConversation({ id = dmId, kind = "dm", userId = 156, name = "builderman" })
		local topBar = gui:FindFirstChild("TopBar", true) :: Frame
		local title = topBar:FindFirstChild("Title", true) :: TextLabel
		local subtitle = topBar:FindFirstChild("Subtitle", true) :: TextLabel
		local badgeSlot = topBar:FindFirstChild("Badges", true) :: Frame
		t.equal("DM header shows the display name", title.Text, "Cool Builder")
		t.check("DM header shows the verified badge", badgeSlot.Visible)
		t.check("DM header shows the @username", subtitle.Visible and subtitle.Text == "@builderman")
		t.equal("message box placeholder uses it", ui.textBox.PlaceholderText, "Message Cool Builder")

		Preferences.set("names", "Username")
		Harness.settle(2)
		t.equal("Names: Username shows the username", title.Text, "builderman")
		t.check("no @username next to the same name", not subtitle.Visible)
		Preferences.set("names", "Display name")
		Harness.settle(2)
		Conversations.setActive(Conversations.MAIN)
		ui.setConversation(Conversations.describe(Conversations.MAIN))

		-- Sidebar row: display name + inline verified badge
		ui.setConversations({
			{ id = "main", kind = "place", name = "Place", onlineCount = 1, unread = 0 },
			{ id = "dm_test", kind = "dm", userId = 156, name = "builderman", unread = 0 },
		}, "dm_test")
		local rowName
		for _, label in ipairs(gui:GetDescendants()) do
			if
				label.Name == "NameLabel"
				and label:IsA("TextLabel")
				and string.find(label.Text, "Cool Builder", 1, true)
			then
				rowName = label
			end
		end
		t.check(
			"sidebar shows display name + verified badge",
			rowName ~= nil and string.find(rowName.Text, Icons.NAMES.verifiedInline, 1, true) ~= nil
		)

		-- Messages and reply lines use the display name and verified badge
		local base = os.time() + 200
		ui.addMessage("builderman", base, "hello", nil, nil, 156)
		ui.addMessage(
			"Bob",
			base + 1,
			"a reply",
			nil,
			{ timestamp = base, sender = "builderman", senderId = 156, content = "hello" },
			nil
		)
		Harness.settle(2)
		local list = gui:FindFirstChild("MessageList", true)
		local authorText, replyText = "", ""
		for _, child in ipairs(list:GetChildren()) do
			if child:GetAttribute("Timestamp") == base then
				authorText = (child:FindFirstChild("AuthorLabel", true) :: TextLabel).Text
			elseif child:GetAttribute("Timestamp") == base + 1 then
				replyText = (child:FindFirstChild("ReplyLabel", true) :: TextLabel).Text
			end
		end
		t.check("message header shows the display name", string.find(authorText, "Cool Builder", 1, true) ~= nil)
		t.check(
			"reply line shows display name + verified",
			string.find(replyText, "Cool Builder", 1, true) ~= nil
				and string.find(replyText, Icons.NAMES.verifiedInline, 1, true) ~= nil
		)

		-- Settings rows exist for the new preferences
		for _, key in ipairs({ "names", "badges", "badgeTooltips", "linkPreviews", "typingIndicator" }) do
			t.check("settings has " .. key, gui:FindFirstChild("Setting_" .. key, true) ~= nil)
		end

		-- Typing indicator setting
		local typing = gui:FindFirstChild("TypingIndicator", true) :: GuiObject
		ui.setTypingUsers({ "Alice" })
		Harness.settle()
		local shownWhenOn = typing == nil or typing.Visible
		Preferences.set("typingIndicator", false)
		Harness.settle()
		t.check("typing indicator hides when turned off", shownWhenOn and (typing == nil or not typing.Visible))
		Preferences.set("typingIndicator", true)
		ui.setTypingUsers({})

		-- Link previews setting
		Preferences.set("linkPreviews", false)
		ui.addMessage("Alice", base + 2, "see www.roblox.com", nil, nil, nil)
		Harness.settle(6)
		local linkRow
		for _, child in ipairs(list:GetChildren()) do
			if child:GetAttribute("Timestamp") == base + 2 then
				linkRow = child
			end
		end
		t.check("no link preview when turned off", linkRow ~= nil and linkRow:FindFirstChild("Embed") == nil)
		Preferences.set("linkPreviews", true)

		-- New commands are registered
		local names = {}
		for _, name in ipairs(app.commands.getCommandNames()) do
			names[name] = true
		end
		for _, name in ipairs({
			"say",
			"me",
			"shrug",
			"roll",
			"coinflip",
			"whois",
			"select",
			"stats",
			"about",
			"badges",
		}) do
			t.check("command /" .. name .. " exists", names[name] == true)
		end

		-- /roll and /coinflip post a card everyone sees (a public bot message)
		local folder = app.chat.getFolder()
		local before = #folder:GetChildren()
		local publicCards = 0
		local ctx = {
			addSystemMessage = function() end,
			addEmbed = function(spec, options)
				if options and options.public then
					publicCards += 1
					app.chat.sendBotMessage(
						"",
						game:GetService("HttpService"):JSONEncode({ title = spec.title }),
						"/test"
					)
				end
			end,
			sendMessage = app.chat.sendMessage,
			getUsername = app.chat.getUsername,
		}
		app.commands.tryParse("/roll 20", ctx)
		app.commands.tryParse("/coinflip", ctx)
		Harness.settle()
		t.equal("/roll and /coinflip post for everyone", publicCards, 2)
		t.equal("…saved in the chat", #folder:GetChildren(), before + 2)

		-- /say: shows as the other user, records who sent it
		local Admin = require(app.copy.Services.Admin) :: any
		local myRank = Admin.getMyRank()
		local said
		if myRank >= 2 then
			app.commands.tryParse("/say builderman I like pizza", ctx)
			Harness.settle()
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("Content") == "I like pizza" then
					said = child
				end
			end
			t.check(
				"/say sends as that user",
				said ~= nil
					and said:GetAttribute("Sender") == "builderman"
					and said:GetAttribute("SenderId") == 156
					and said:GetAttribute("SaidBy") == app.chat.getUserId()
			)
		else
			local reply = ""
			app.commands.tryParse("/say builderman hi", {
				addSystemMessage = function(text)
					reply ..= text
				end,
			})
			t.check("/say needs Admin: " .. reply, string.find(reply, "permission", 1, true) ~= nil)
		end

		-- Checkout
		local opened, watched = nil, nil
		ui.setBadgeHandlers({
			myBadges = function()
				return {}
			end,
			getStore = function()
				return {}
			end,
			purchaseUrl = function(id)
				opened = id
				return "https://www.roblox.com/game-pass/" .. id
			end,
			refresh = function() end,
			watchPurchase = function(badgeId, onStatus)
				watched = badgeId
				onStatus("waiting")
				task.delay(0.2, onStatus, "owned")
			end,
		})
		ui.openPurchase({
			badge = { id = "premium", name = "Premium", description = "Team Chat Premium", icon = "crown" },
			gamePassId = 123,
			price = 100,
			forSale = true,
			owned = false,
		})
		local checkout = gui:FindFirstChild("PurchaseDialog", true) :: Frame
		local continue = checkout:FindFirstChild("Continue", true) :: TextButton
		local status = checkout:FindFirstChild("Status", true) :: TextLabel
		t.check("checkout opens", checkout.Visible and continue.Visible and continue.Text == "Continue to Roblox")
		t.check(
			"checkout shows the price in Robux",
			string.find((checkout:FindFirstChild("Price", true) :: TextLabel).Text, "100", 1, true) ~= nil
		)
		-- "Click" Continue (the harness records the button's handler)
		hooks.clicks[continue]()
		t.equal("Continue opens the game pass page", hooks.opened, "https://www.roblox.com/game-pass/123")
		t.equal("it asks for the game pass page", opened, 123)
		t.equal("it watches for the purchase", watched, "premium")
		t.check("shows it's waiting", status.Visible and string.find(status.Text, "Waiting", 1, true) ~= nil)
		task.wait(0.4)
		t.check("shows when the purchase is done", string.find(status.Text, "Purchase complete", 1, true) ~= nil)
		t.check("Continue hides once bought", not continue.Visible)

		-- Every Builder Icons name is listed in the icon config
		t.equal("icon config lists all icons", #Icons.ALL, 781)
		t.check(
			"the list has the verified icons",
			table.find(Icons.ALL, "verified-backplate") ~= nil and table.find(Icons.ALL, "verified-check") ~= nil
		)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
