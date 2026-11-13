--[[
	Team Chat Premium perks (Config/Premium, Services/Premium): longer
	messages, more poll answers, and the Midnight and Gold themes, which only
	Premium can pick (and which fall back to Studio's theme without it).
]]

local Harness = require(script.Parent.Parent.Harness)

local function waitFor(condition: () -> boolean, seconds: number?): boolean
	local deadline = os.clock() + (seconds or 3)
	while os.clock() < deadline do
		if condition() then
			return true
		end
		task.wait(0.05)
	end
	return condition()
end

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui = app.ui
		local gui = app.gui
		local Premium = require(app.copy.Services.Premium) :: any
		local PremiumConfig = require(app.copy.Config.Premium) :: any
		local Theme = require(app.copy.Config.Theme) :: any
		local ChatState = require(app.copy.Services.Chat.ChatState) :: any
		local Identity = require(app.copy.Core.Identity) :: any

		-- Who has Premium is up to the spec
		local premium = false
		Premium.has = function()
			return premium
		end

		-- Limits
		t.equal("messages without Premium: 2000 characters", Premium.messageLength(1), 2000)
		t.equal("polls without Premium: 10 answers", Premium.pollOptions(1), 10)
		premium = true
		t.equal("messages with Premium: 4000 characters", Premium.messageLength(1), 4000)
		t.equal("polls with Premium: 20 answers", Premium.pollOptions(1), 20)
		t.check(
			"Midnight and Gold are Premium themes",
			Premium.isPremiumTheme("Midnight") and Premium.isPremiumTheme("Gold")
		)
		t.check("Dark isn't", not Premium.isPremiumTheme("Dark"))
		t.equal("Premium is the premium badge", PremiumConfig.BADGE, "premium")

		-- Sending: too long stays in the box
		local folder = ChatState.getFolder()
		local function sent(text: string): boolean
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("Content") == text then
					return true
				end
			end
			return false
		end
		local function send(text: string)
			ui.textBox.Text = text
			Harness.settle()
			ui.textBox.Text = text .. "\n"
			Harness.settle(3)
		end
		premium = false
		local long = string.rep("a", 2001)
		send(long)
		t.check("a 2001-character message isn't sent without Premium", not sent(long))
		t.check("...and stays in the box to shorten", #ui.textBox.Text >= 2001)
		premium = true
		send(long)
		t.check(
			"...but is with Premium",
			waitFor(function()
				return sent(long)
			end)
		)
		local longest = string.rep("b", 4001)
		send(longest)
		t.check("over 4000 isn't sent even with Premium", not sent(longest))
		ui.textBox.Text = ""

		-- Themes
		local function colored(color: Color3): boolean
			for _, gui2 in ipairs(gui:GetDescendants()) do
				if gui2:IsA("GuiObject") and gui2.Visible and gui2.BackgroundColor3 == color then
					return true
				end
			end
			return false
		end
		ui.setBadgeHandlers({
			myBadges = function()
				return {}
			end,
			getStore = function()
				return {}
			end,
			purchaseUrl = function(id)
				return "https://www.roblox.com/game-pass/" .. id
			end,
			refresh = function() end,
			watchPurchase = function() end,
			isPremium = function()
				return premium
			end,
			pollOptions = function()
				return Premium.pollOptions(1)
			end,
		})
		premium = false
		ui.applySetting("theme", "Dark")
		ui.applySetting("theme", "Midnight")
		t.equal("Premium themes need Premium", ui.getSetting("theme"), "Dark")
		Harness.settle(2)
		local store = gui:FindFirstChild("BadgesDialog", true)
		t.check("...and the Badges store opens instead", store ~= nil and (store :: GuiObject).Visible)
		ui.closeSettings()

		premium = true
		ui.applySetting("theme", "Midnight")
		t.equal("with Premium, Midnight can be picked", ui.getSetting("theme"), "Midnight")
		Harness.settle()
		t.check("Midnight colors the chat", colored(Theme.PALETTES.Midnight.scrollBack))
		ui.applySetting("theme", "Gold")
		Harness.settle()
		t.check("Gold colors the chat", colored(Theme.PALETTES.Gold.scrollBack))

		premium = false
		ui.refreshBadges(Identity.userId) -- my badges changed: Premium is gone
		Harness.settle()
		t.check("losing Premium falls back to Studio's theme", not colored(Theme.PALETTES.Gold.scrollBack))
		t.equal("...but the choice is kept for when it's back", ui.getSetting("theme"), "Gold")
		premium = true
		ui.refreshBadges(Identity.userId)
		Harness.settle()
		t.check("...and applies again", colored(Theme.PALETTES.Gold.scrollBack))
		ui.applySetting("theme", "Auto")
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
