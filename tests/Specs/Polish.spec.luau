--[[
	Toast notifications, the Settings window's left-side tabs, and the
	animation controller (modals, fades, the Animations setting).
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot({ settings = { TeamChatAboutSeen_v1 = true, TeamChatLastSeenVersion_v1 = "x" } })
	local ok, err = pcall(function()
		local ui, gui = app.ui, app.gui
		local Preferences = require(app.copy.UI.Common.Preferences) :: any
		local Animation = require(app.copy.UI.Common.Animation) :: any
		local Conversations = app.chat.Conversations

		local function toasts(): { Instance }
			local found = {}
			local stack = gui:FindFirstChild("Toasts", true)
			for _, child in ipairs(stack and stack:GetChildren() or {}) do
				if child.Name == "Toast" then
					table.insert(found, child)
				end
			end
			return found
		end

		-- Toasts sit at the bottom-centre of the panel
		local toast = ui.notify({ title = "Hello", text = "A test toast", icon = "badges" })
		Harness.settle()
		local stack = gui:FindFirstChild("Toasts") :: Frame
		t.check("a toast shows in the plugin panel", toast ~= nil and stack ~= nil and toast.Parent == stack)
		local center = stack.AbsolutePosition.X + stack.AbsoluteSize.X / 2
		t.check("toasts are centered in the plugin", math.abs(center - gui.AbsoluteSize.X / 2) <= 2)
		t.check("toasts are at the bottom", stack.AbsolutePosition.Y > gui.AbsoluteSize.Y / 2)
		for i = 1, 4 do
			ui.notify({ title = "Toast " .. i })
		end
		Harness.settle()
		t.check("at most 3 at once", #toasts() <= 3)

		-- A new message in a conversation you're not looking at notifies
		local base = #toasts()
		local dm = Conversations.dmId(app.chat.getUserId(), 156)
		Conversations.startDm(156, "builderman")
		Conversations.setActive(dm)
		task.wait(3.2) -- notifications start a few seconds after loading
		local function incoming(text: string)
			local message = Instance.new("Folder")
			message.Name = "msg_test_" .. text
			message:SetAttribute("Sender", "builderman")
			message:SetAttribute("SenderId", 156)
			message:SetAttribute("Timestamp", os.time())
			message:SetAttribute("Content", text)
			message:SetAttribute("MessageType", "Text")
			message.Parent = app.chat.getFolder()
			task.wait(0.2)
		end
		for _, frame in ipairs(toasts()) do
			frame:Destroy()
		end
		incoming("ping from the team chat")
		local shown = toasts()
		local newest = shown[#shown]
		t.check(
			"a team chat message notifies while you're in a DM",
			newest ~= nil
				and string.find((newest:FindFirstChild("Body") :: TextLabel).Text, "ping from the team chat", 1, true) ~= nil
				and string.find((newest:FindFirstChild("Title") :: TextLabel).Text, "Team chat", 1, true) ~= nil
		)
		local _ = base
		Preferences.set("notifications", "DMs only")
		local function toastFor(text: string): boolean
			for _, frame in ipairs(toasts()) do
				if (frame:FindFirstChild("Body") :: TextLabel).Text == text then
					return true
				end
			end
			return false
		end
		incoming("not a DM")
		t.check("DMs only skips the team chat", not toastFor("not a DM"))
		Preferences.set("notifications", "Off")
		incoming("muted")
		t.check("Off shows nothing", not toastFor("muted"))
		Preferences.set("notifications", "All")
		Conversations.setActive(Conversations.MAIN)
		incoming("you're looking at it")
		t.check("no toast for the open conversation", not toastFor("you're looking at it"))

		-- Settings tabs are on the left of the window
		ui.openSettings()
		Harness.settle(2)
		local overlay = gui:FindFirstChild("SettingsDialog", true) :: Frame
		local nav = overlay:FindFirstChild("SettingsNav") :: Frame
		local card = overlay:FindFirstChild("DialogFrame") :: Frame
		t.check("the tabs are a nav on the left", nav ~= nil and nav.AbsolutePosition.X < card.AbsolutePosition.X)
		t.check(
			"the nav is as tall as the window",
			nav ~= nil and math.abs(nav.AbsoluteSize.Y - card.AbsoluteSize.Y) <= 1
		)
		local general = nav:FindFirstChild("Tab_General") :: TextButton
		t.check("the open tab is highlighted", (general:FindFirstChild("Pill") :: Frame).Visible)
		t.check(
			"tabs have icons and names",
			(general:FindFirstChild("Icon") :: TextLabel).Text ~= ""
				and (general:FindFirstChild("Label") :: TextLabel).Text == "General"
		)
		local window = overlay:FindFirstChild("SettingsWindow") :: Frame
		local function edge(gui: GuiObject): number
			return gui.AbsolutePosition.X + gui.AbsoluteSize.X
		end
		t.check(
			"the tabs and the page are one window",
			window ~= nil
				and math.abs(window.AbsolutePosition.X - nav.AbsolutePosition.X) <= 1
				and math.abs(edge(window) - edge(card)) <= 1
				and math.abs(edge(nav) - card.AbsolutePosition.X) <= 1
		)
		t.check(
			"…with the tabs in groups",
			nav:FindFirstChild("Group_chat") ~= nil
				and nav:FindFirstChild("Group_manage") ~= nil
				and nav:FindFirstChild("Group_info") ~= nil
		)
		local version = window and window:FindFirstChild("Version") :: TextLabel
		t.check("…and the version at the bottom", version ~= nil and string.find(version.Text, "%d+%.%d+") ~= nil)
		t.check(
			"settings has Animations and Notifications",
			gui:FindFirstChild("Setting_notifications", true) ~= nil
				and gui:FindFirstChild("Setting_animations", true) ~= nil
		)
		ui.closeSettings()

		-- Animations: off = instant
		t.check("tests run with animations off", not Animation.enabled())
		local probe = Instance.new("Frame")
		probe.Parent = gui
		Animation.tween(probe, "smooth", { BackgroundTransparency = 0.7 })
		t.equal("off: tweens apply at once", math.floor(probe.BackgroundTransparency * 10 + 0.5), 7)

		-- On: the dialog pops in, then settles
		Preferences.set("animations", true)
		ui.openSettings()
		local startDim = overlay.BackgroundTransparency
		task.wait(0.5)
		t.check("on: the backdrop fades in", startDim > 0.5 and math.abs(overlay.BackgroundTransparency - 0.4) < 0.01)
		local scale = card:FindFirstChild("AnimationScale") :: UIScale
		t.check("on: the window pops up to full size", scale ~= nil and math.abs(scale.Scale - 1) < 0.001)
		ui.closeSettings()
		t.check("on: closing counts at once", not app.ui.isSettingsVisible())
		t.check("…but the window stays while it fades", overlay.Visible)
		task.wait(0.4)
		t.check("…then it's hidden", not overlay.Visible)

		-- fadeIn puts every transparency back where it was
		local label = Instance.new("TextLabel")
		label.TextTransparency = 0.25
		label.BackgroundTransparency = 0.5
		label.Parent = probe
		Animation.fadeIn(probe, "quick")
		t.check("fadeIn starts invisible", label.TextTransparency == 1)
		task.wait(0.3)
		t.check(
			"fadeIn ends where it started",
			math.abs(label.TextTransparency - 0.25) < 0.01 and math.abs(label.BackgroundTransparency - 0.5) < 0.01
		)
		probe:Destroy()
		Preferences.set("animations", false)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
