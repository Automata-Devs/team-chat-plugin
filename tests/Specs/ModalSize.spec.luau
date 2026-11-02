--[[
	Modal sizes: every dialog stays between a minimum and maximum width and
	is at least a minimum height (unless the panel itself is smaller); the
	Settings window has one height for all its tabs.
]]

local Harness = require(script.Parent.Parent.Harness)

local MIN_WIDTH, MAX_WIDTH, MIN_HEIGHT, MAX_HEIGHT = 300, 520, 200, 540
local SETTINGS_MIN_HEIGHT = 540

return function(t)
	local app = Harness.boot({ settings = { TeamChatAboutSeen_v1 = true, TeamChatLastSeenVersion_v1 = "x" } })
	local ok, err = pcall(function()
		local ui, gui = app.ui, app.gui

		local function cardOf(name: string): ScrollingFrame
			return (gui:FindFirstChild(name, true) :: Frame):FindFirstChild("DialogFrame") :: ScrollingFrame
		end
		local function check(label: string, card: ScrollingFrame, minHeight: number)
			local size = card.AbsoluteSize
			t.check(
				("%s: width between %d and %d (%d)"):format(label, MIN_WIDTH, MAX_WIDTH, size.X),
				size.X >= MIN_WIDTH - 1 and size.X <= MAX_WIDTH + 1
			)
			t.check(
				("%s: height between %d and %d (%d)"):format(label, minHeight, MAX_HEIGHT, size.Y),
				size.Y >= minHeight - 1 and size.Y <= MAX_HEIGHT + 1
			)
		end

		-- The Settings window: at least its own minimum height, whatever the tab
		ui.openSettings()
		Harness.settle(3)
		check("Settings", cardOf("SettingsDialog"), SETTINGS_MIN_HEIGHT)
		local backdrop = gui:FindFirstChild("SettingsDialog", true) :: Frame
		t.check(
			"the backdrop covers the whole plugin, sidebar included",
			backdrop.AbsolutePosition.X <= gui.AbsolutePosition.X + 1
				and math.abs(backdrop.AbsoluteSize.X - gui.AbsoluteSize.X) <= 1
		)
		local sidebar = gui:FindFirstChild("Sidebar") :: Frame
		t.check("the backdrop is above the sidebar", backdrop.ZIndex > sidebar.ZIndex)
		ui.openAbout()
		Harness.settle(3)
		check("About", cardOf("AboutDialog"), SETTINGS_MIN_HEIGHT)
		local aboutHeight = cardOf("AboutDialog").AbsoluteSize.Y
		ui.openChangelog()
		Harness.settle(3)
		t.equal(
			"Settings tabs share one height",
			math.floor(cardOf("ChangelogDialog").AbsoluteSize.Y + 0.5),
			math.floor(aboutHeight + 0.5)
		)
		ui.closeSettings()

		-- Other dialogs (sized when created, open or not)
		check("Create a Poll", cardOf("PollDialog"), MIN_HEIGHT)
		check("New message", cardOf("NewMessageDialog"), MIN_HEIGHT)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
