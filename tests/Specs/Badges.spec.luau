--[[
	Badges next to names (verified, custom), System messages, tooltips, the
	command argument panel and the Badges / About dialogs.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui, gui = app.ui, app.gui
		local list = gui:FindFirstChild("MessageList", true)
		local RichText = require(app.copy.Util.RichText) :: any

		local function rowAt(timestamp: number): Instance?
			for _, child in ipairs(list:GetChildren()) do
				if child:GetAttribute("Timestamp") == timestamp then
					return child
				end
			end
			return nil
		end
		-- The badge icons after a message's name ("verified,developer")
		local function badgesOf(row: Instance?): string
			local frame = row and row:FindFirstChild("Badges", true)
			local names = {}
			for _, icon in ipairs(frame and frame:GetChildren() or {}) do
				if icon:IsA("TextLabel") then
					table.insert(names, (string.gsub(icon.Name, "^BadgeIcon_", "")))
				end
			end
			table.sort(names)
			return table.concat(names, ",")
		end
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

		-- The plugin's own messages are from Team Chat (code icon), a verified bot
		ui.addSystemMessage("hello from the plugin")
		Harness.settle()
		local systemRow
		for _, child in ipairs(list:GetChildren()) do
			if child:GetAttribute("IsSystem") then
				systemRow = child
			end
		end
		local systemAuthor = (systemRow:FindFirstChild("AuthorLabel", true) :: TextLabel).Text
		t.check("system messages are from Team Chat", string.find(systemAuthor, ">Team Chat<", 1, true) ~= nil)
		t.equal("Team Chat has no badge icons", badgesOf(systemRow), "")
		local botTag = systemRow:FindFirstChild("BotTag", true) :: TextLabel
		t.check(
			"…but a verified BOT tag (a check, then BOT)",
			botTag ~= nil
				and string.find(botTag.Text, "BOT", 1, true) ~= nil
				and string.find(botTag.Text, "<font", 1, true) ~= nil
		)
		t.equal("System avatar is the code icon", (systemRow:FindFirstChild("Badge", true) :: TextLabel).Text, "code")

		-- A verified Roblox user gets the badge once the lookup finishes
		local Icons = require(app.copy.Config.Icons) :: any
		local BadgeConfig = require(app.copy.Config.Badges) :: any
		local base = os.time() + 100
		ui.addMessage("builderman", base, "hi", nil, nil, 156)
		t.check(
			"verified user gets the verified badge",
			waitFor(function()
				return badgesOf(rowAt(base)) == "verified"
			end, 8)
		)

		-- The verified badge: backplate in the verified color, white check on top
		local verifiedIcon = (rowAt(base) :: Instance):FindFirstChild("BadgeIcon_verified", true) :: TextLabel
		local check = verifiedIcon:FindFirstChild("Check") :: TextLabel
		t.check(
			"verified badge is the backplate + check from the icon config",
			verifiedIcon.Text == Icons.NAMES.verified
				and verifiedIcon.TextColor3 == BadgeConfig.VERIFIED_COLOR
				and check ~= nil
				and check.Text == Icons.NAMES.verifiedCheck
				and check.TextColor3 == Color3.new(1, 1, 1)
		)
		t.check("verified badge is small", verifiedIcon.AbsoluteSize.X <= 14)

		-- Custom badges from Config/Badges (the plugin developer)
		ui.addMessage("D3veloperHac", base + 1, "hey", nil, nil, 7091790691)
		t.check(
			"custom badge shows",
			waitFor(function()
				return string.find(badgesOf(rowAt(base + 1)), "developer", 1, true) ~= nil
			end, 8)
		)

		-- No user id: no badges
		ui.addMessage("NoId", base + 2, "hm", nil, nil, nil)
		Harness.settle()
		t.equal("no badges without a user id", badgesOf(rowAt(base + 2)), "")
		t.equal("buildBadges with nothing", RichText.buildBadges(nil), "")

		-- Tooltips: just the badge's name, above it, centered
		local Author = require(app.copy.UI.Messages.Author) :: any
		local tooltip = gui:FindFirstChild("Tooltip", true) :: TextLabel
		-- Let profile lookups finish first: they redraw the badges (hiding a tooltip)
		local Profiles = require(app.copy.Services.Profiles) :: any
		waitFor(function()
			return Profiles.get(7091790691).loaded and Profiles.get(156).loaded
		end, 8)
		Harness.settle(3)
		local devIcon = (rowAt(base + 1) :: Instance):FindFirstChild("BadgeIcon_developer", true) :: TextLabel
		t.check("the chat has a badge tooltip", tooltip ~= nil and not tooltip.Visible and Author.tooltip ~= nil)
		t.equal("tooltip is just the badge name", Author.tooltipText({ name = "Plugin Developer" }), "Plugin Developer")
		Author.tooltip.show(devIcon, Author.tooltipText({ name = "Plugin Developer" }), true)
		Harness.settle()
		local tipCenter = tooltip.AbsolutePosition.X + tooltip.AbsoluteSize.X / 2
		local iconCenter = devIcon.AbsolutePosition.X + devIcon.AbsoluteSize.X / 2
		t.check(
			"tooltip shows above the badge",
			tooltip.Visible and tooltip.AbsolutePosition.Y + tooltip.AbsoluteSize.Y <= devIcon.AbsolutePosition.Y
		)
		t.check("tooltip is centered on the badge", math.abs(tipCenter - iconCenter) <= 2)
		Author.tooltip.hide(verifiedIcon)
		t.check("hiding another badge's tooltip leaves it", tooltip.Visible)
		Author.tooltip.hide(devIcon)
		t.check("leaving the badge hides it", not tooltip.Visible)

		-- Command argument panel
		local box = ui.textBox
		local menu = gui:FindFirstChild("Autocomplete", true) :: Frame
		box.Text = "/ban "
		Harness.settle()
		local userRow = menu:FindFirstChild("Item_1") :: TextButton
		local reasonRow = menu:FindFirstChild("Item_2") :: TextButton
		t.check("typing /ban shows its arguments", menu.Visible and userRow ~= nil and reasonRow ~= nil)
		t.equal("first argument is user", userRow and (userRow:FindFirstChild("CmdName") :: TextLabel).Text, "user")
		t.check("reason is marked optional", reasonRow and reasonRow:FindFirstChild("CmdRank") ~= nil)
		t.check("the argument being typed is highlighted", userRow.BackgroundTransparency == 0)
		t.check(
			"title names the command",
			string.find((menu:FindFirstChild("Title") :: TextLabel).Text, "/BAN", 1, true) ~= nil
		)
		box.Text = "/ban builderman "
		Harness.settle()
		t.check(
			"moves on to the next argument",
			(menu:FindFirstChild("Item_2") :: TextButton).BackgroundTransparency == 0
		)
		box.Text = "/ban builderman being mean"
		Harness.settle()
		t.check(
			"the last argument takes the rest",
			(menu:FindFirstChild("Item_2") :: TextButton).BackgroundTransparency == 0
		)
		box.Text = "/b"
		Harness.settle()
		t.equal(
			"command suggestions come back",
			(menu:FindFirstChild("Hint") :: TextLabel).Text,
			"Tab or click to pick"
		)
		box.Text = "/clear "
		Harness.settle()
		t.check("commands without arguments show nothing", not menu.Visible)
		box.Text = ""
		Harness.settle()

		-- /help <command> replies with a card: usage, each argument, rank
		local helpCard
		app.commands.tryParse("/help ban", {
			addSystemMessage = function() end,
			addEmbed = function(spec)
				helpCard = spec
			end,
		})
		local helpFields = {}
		for _, field in ipairs(helpCard and helpCard.fields or {}) do
			helpFields[field.name] = field.value
		end
		t.check(
			"help shows usage: " .. tostring(helpFields.Usage),
			helpCard ~= nil and helpCard.title == "/ban" and helpFields.Usage == "/ban <user> [reason]"
		)
		t.check("…each argument", helpFields.user ~= nil and helpFields["reason (optional)"] ~= nil)
		t.check("…and the rank it needs", helpFields["Required rank"] == "Admin")

		-- /whois replies with one card: avatar, name, fields
		local before = #list:GetChildren()
		box.Text = "/whois 156"
		Harness.settle()
		box.Text = "/whois 156\n"
		local card
		waitFor(function()
			for _, child in ipairs(list:GetChildren()) do
				if child:GetAttribute("HasCommandEmbed") then
					card = child
				end
			end
			return card ~= nil
		end, 8)
		t.check("/whois sends a card", card ~= nil)
		if card then
			local names = {}
			for _, item in ipairs(card:GetDescendants()) do
				if item.Name == "FieldName" and item:IsA("TextLabel") then
					table.insert(names, item.Text)
				end
			end
			t.check("…with their avatar", card:FindFirstChild("Thumbnail", true) ~= nil)
			t.check(
				"…and labelled fields: " .. table.concat(names, ", "),
				table.find(names, "User ID") ~= nil and table.find(names, "Chat rank") ~= nil
			)
			t.check("…as one message, not five", #list:GetChildren() - before <= 2)
		end

		-- Dialogs
		ui.openAbout()
		local about = gui:FindFirstChild("AboutDialog", true) :: Frame
		local aboutText = ""
		for _, label in ipairs(about:GetDescendants()) do
			if label:IsA("TextLabel") then
				aboutText ..= label.Text .. "\n"
			end
		end
		t.check("About is open", about.Visible)
		t.check(
			"About says it isn't affiliated with Roblox",
			string.find(aboutText, "not made, endorsed", 1, true) ~= nil
		)
		t.check("About has terms of use", string.find(string.lower(aboutText), "terms of use", 1, true) ~= nil)

		-- A test badge without a game pass (added to this copy only) shows
		-- "Coming soon", whatever badges the real config has
		local BadgeDefinitions = require(app.copy.Config.Badges) :: any
		BadgeDefinitions.DEFINITIONS.testbadge =
			{ name = "Test", description = "Test badge", icon = "star", color = Color3.new(1, 1, 1), gamePassId = 0 }
		table.insert(BadgeDefinitions.ORDER, "testbadge")
		ui.openBadges()
		local badges = gui:FindFirstChild("BadgesDialog", true) :: Frame
		t.check("Badges is open", badges.Visible)
		local store = badges:FindFirstChild("Store", true) :: Frame
		t.check(
			"store lists the badges for sale",
			waitFor(function()
				return store:FindFirstChild("Badge_testbadge") ~= nil
			end, 8)
		)
		local buy = store:FindFirstChild("Badge_testbadge")
			and store.Badge_testbadge:FindFirstChild("Buy") :: TextButton
		t.equal("unconfigured badges say Coming soon", buy and buy.Text, "Coming soon")
		t.check("Premium is in the store", store:FindFirstChild("Badge_premium") ~= nil)

		-- One Settings window with tabs; the sidebar only has the Settings button
		local footerNames = {}
		for _, child in ipairs((gui:FindFirstChild("Footer", true) :: Frame):GetChildren()) do
			if child:IsA("TextButton") then
				table.insert(footerNames, child.Name)
			end
		end
		table.sort(footerNames)
		t.equal("sidebar has just Settings and the toggle", table.concat(footerNames, ","), "SettingsButton,Toggle")
		local function visible(name: string): boolean
			return (gui:FindFirstChild(name, true) :: Frame).Visible
		end
		local function selectedTab(dialogName: string): string?
			local nav = (gui:FindFirstChild(dialogName, true) :: Frame):FindFirstChild("SettingsNav")
			for _, item in ipairs(nav and nav:GetChildren() or {}) do
				local pill = item:FindFirstChild("Pill")
				if pill and pill.Visible then
					return (string.gsub(item.Name, "^Tab_", ""))
				end
			end
			return nil
		end
		ui.openSettings()
		t.check("Settings opens on General", visible("SettingsDialog") and selectedTab("SettingsDialog") == "General")
		t.check("Badges is a tab", visible("BadgesDialog") == false)
		ui.openBadges()
		t.check(
			"switching tabs shows one page",
			visible("BadgesDialog") and not visible("SettingsDialog") and selectedTab("BadgesDialog") == "Badges"
		)
		ui.openChangelog()
		t.check("What's New is a tab", visible("ChangelogDialog") and selectedTab("ChangelogDialog") == "What's New")
		ui.openAbout()
		t.check("About is a tab", visible("AboutDialog") and not visible("ChangelogDialog"))
		t.check(
			"each tab has its own title",
			((gui:FindFirstChild("AboutDialog", true) :: Frame):FindFirstChild("Title", true) :: TextLabel).Text
					== "About Team Chat"
				and ((gui:FindFirstChild("BadgesDialog", true) :: Frame):FindFirstChild("Title", true) :: TextLabel).Text == "Badges"
				and (
						(gui:FindFirstChild("SettingsDialog", true) :: Frame):FindFirstChild("Title", true) :: TextLabel
					).Text
					== "Settings"
		)
		ui.closeSettings()
		t.check(
			"closing closes every tab",
			not visible("AboutDialog") and not visible("BadgesDialog") and not visible("SettingsDialog")
		)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
