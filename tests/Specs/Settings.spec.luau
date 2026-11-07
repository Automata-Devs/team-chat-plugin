--[[
	The Settings page (setting cards with toggles, sliders, dropdowns and a
	search box) and the tooltip delay.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot({ settings = { TeamChatAboutSeen_v1 = true, TeamChatLastSeenVersion_v1 = "x" } })
	local ok, err = pcall(function()
		local ui, gui = app.ui, app.gui
		local Preferences = require(app.copy.UI.Common.Preferences) :: any
		local Constants = require(app.copy.Config.Constants) :: any
		ui.openSettings()
		Harness.settle(2)
		local page = gui:FindFirstChild("SettingsDialog", true) :: Frame

		local function card(key: string): Frame
			return page:FindFirstChild("Setting_" .. key, true) :: Frame
		end

		-- Cards: title, control on the right, divider, description
		local theme = card("theme")
		t.check(
			"settings are cards with title, divider and description",
			theme ~= nil
				and theme:FindFirstChild("Title", true) ~= nil
				and theme:FindFirstChild("Divider") ~= nil
				and (theme:FindFirstChild("Description") :: TextLabel).Text ~= ""
		)
		t.check("sections have headings", page:FindFirstChild("AppearanceSection", true) ~= nil)

		-- Toggle
		local toggle = card("timestamps"):FindFirstChild("Toggle", true) :: TextButton
		t.check("on/off settings are toggles", toggle ~= nil and toggle:GetAttribute("On") == true)
		app.setSetting("timestamps", false)
		t.check("toggle follows the setting", toggle:GetAttribute("On") == false)
		t.equal("and it's saved", app.settings[Constants.SETTING_KEY_TIMESTAMPS], false)
		app.setSetting("timestamps", true)

		-- Dropdown
		local dropdownFrame = card("theme"):FindFirstChild("Dropdown", true) :: TextButton
		t.equal("choices are dropdowns", dropdownFrame and dropdownFrame:GetAttribute("Value"), "Auto")
		local controls = ui.getSettingControls()
		local themeControl = controls and controls.theme
		t.check("dropdown control exists", themeControl ~= nil)
		themeControl.open()
		Harness.settle()
		local list = page:FindFirstChild("DropdownList", true) :: Frame
		t.check(
			"opening shows the options",
			list ~= nil and list:FindFirstChild("Option_Light") ~= nil and list:FindFirstChild("Option_Dark") ~= nil
		)
		themeControl.choose("Light")
		Harness.settle()
		t.equal("choosing an option changes the setting", ui.getSetting("theme"), "Light")
		t.equal("and saves it", app.settings[Constants.SETTING_KEY_THEME], "Light")
		t.check("the list closes", page:FindFirstChild("DropdownList", true) == nil)
		app.setSetting("theme", "Dark")

		-- Slider
		local sizeControl = controls.textSize
		local sliderFrame = card("textSize"):FindFirstChild("Slider", true) :: Frame
		t.equal("sizes are sliders", sliderFrame and sliderFrame:GetAttribute("Value"), 14)
		sizeControl.dragTo(1)
		t.equal("dragging to the end picks the maximum", ui.getSetting("textSize"), 20)
		t.equal(
			"the value shows next to the title",
			(card("textSize"):FindFirstChild("Value", true) :: TextLabel).Text,
			"20px"
		)
		sizeControl.dragTo(0)
		t.equal("and the start the minimum", ui.getSetting("textSize"), 11)
		app.setSetting("textSize", 14)
		local durationControl = controls.notificationDuration
		durationControl.dragTo(0.5)
		t.equal("notification duration slider steps in seconds", Preferences.values.notificationDuration, 6)
		app.setSetting("notificationDuration", 5)

		-- Search
		local searchBox = page:FindFirstChild("SearchBox", true) :: TextBox
		searchBox.Text = "badge"
		Harness.settle()
		t.check(
			"search shows matching settings",
			card("badges").Visible and card("badgeTooltips").Visible and not card("theme").Visible
		)
		t.check(
			"…and hides empty sections",
			not (page:FindFirstChild("AppearanceSection", true) :: TextLabel).Visible
		)
		searchBox.Text = "zzzz"
		Harness.settle()
		t.check("no matches says so", (page:FindFirstChild("NoResults", true) :: TextLabel).Visible)
		searchBox.Text = ""
		Harness.settle()
		t.check("clearing shows everything again", card("theme").Visible)
		ui.closeSettings()

		-- Older saved text sizes ("Large") still load
		local Messages = require(app.copy.UI.Messages) :: any
		Messages.setTextSize("Large")
		t.equal("named text sizes still work", Messages.getTextSize(), 16)
		Messages.setTextSize(14)

		-- Tooltips wait a moment
		local Author = require(app.copy.UI.Messages.Author) :: any
		local tooltip = gui:FindFirstChild("Tooltip", true) :: TextLabel
		local target = Instance.new("Frame")
		target.Size = UDim2.fromOffset(20, 20)
		target.Position = UDim2.fromOffset(300, 300)
		target.Parent = gui
		local delay = Constants.TOOLTIP_DELAY
		t.equal("tooltip delay is 0.3s", delay, 0.3)
		Author.tooltip.show(target, "Hello")
		task.wait(delay * 0.5)
		t.check("tooltip waits before showing", not tooltip.Visible)
		task.wait(delay * 0.5 + 0.15)
		t.check("tooltip shows after the delay", tooltip.Visible)
		Author.tooltip.hide(target)
		Author.tooltip.show(target, "Hello")
		task.wait(delay * 0.4)
		Author.tooltip.hide(target)
		task.wait(delay + 0.2)
		t.check("leaving before the delay cancels it", not tooltip.Visible)
		target:Destroy()

		-- Focus leaving the plugin (another window, alt-tab) keeps windows open
		ui.openBadges()
		Harness.settle()
		app.hooks.events.WindowFocusReleased:Fire()
		Harness.settle()
		t.check("losing focus keeps the window open", (gui:FindFirstChild("BadgesDialog", true) :: Frame).Visible)
		ui.closeSettings()

		-- Images are sized to their shape, so they line up with the text
		local stamp = os.time() + 500
		ui.addMessage("D3veloperHac", stamp, "", "rbxassetid://103525899533376", nil, 7091790691)
		local image
		local deadline = os.clock() + 8
		repeat
			task.wait(0.2)
			for _, row in ipairs(gui:FindFirstChild("MessageList", true):GetChildren()) do
				if row:GetAttribute("Timestamp") == stamp then
					image = row:FindFirstChild("ImageAttachment", true)
				end
			end
		until (image and image.AbsoluteSize.X ~= 200) or os.clock() > deadline
		t.check(
			"a square image gets a square box (" .. (image and tostring(image.AbsoluteSize) or "none") .. ")",
			image ~= nil and image.AbsoluteSize.X >= 100 and math.abs(image.AbsoluteSize.X - image.AbsoluteSize.Y) <= 1
		)
		local author = image and image.Parent:FindFirstChild("AuthorLabel", true)
		t.check(
			"images line up with the name",
			author ~= nil and math.abs(image.AbsolutePosition.X - author.AbsolutePosition.X) <= 1
		)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
