--[[
	Discord-style bot interactions: typed command options, buttons under
	bot messages, ephemeral ("only you can see this") and deferred
	("is thinking…") answers, web bots, and the Developer and Admin tabs in
	Settings. Uses a throwaway Studio bot and web bot, removed at the end.
]]

local Harness = require(script.Parent.Parent.Harness)

local BOT_SOURCE = [==[
local bot = {
	name = "Spec Interactions",
	commands = {
		specroll = {
			description = "Rolls",
			options = {
				{ name = "dice", type = "integer" },
				{ name = "speed", type = "string", choices = { "fast", "slow" } },
			},
			run = function(ctx)
				ctx.reply("rolled " .. ctx.options.dice .. " " .. ctx.options.speed)
			end,
		},
		specsecret = {
			description = "Only for you",
			run = function(ctx)
				ctx.reply({ content = "secret", ephemeral = true })
			end,
		},
		specslow = {
			description = "Takes a while",
			run = function(ctx)
				ctx.defer()
				task.wait(0.5)
				ctx.reply("done")
			end,
		},
		specbuttons = {
			description = "Has buttons",
			run = function(ctx)
				ctx.reply({
					content = "pick one",
					components = {
						{ label = "Go", style = "primary", customId = "go" },
						{ label = "Docs", url = "https://create.roblox.com" },
					},
				})
			end,
		},
	},
}

function bot.onButton(ctx, customId)
	ctx.update("went " .. customId .. " by " .. ctx.user.name)
end

return bot
]==]

return function(t)
	local app = Harness.boot()
	local scriptName = "SpecInteractions" .. tostring(math.random(10000, 99999))
	local Bots = require(app.copy.Services.Bots) :: any
	local webId: string? = nil
	local ok, err = pcall(function()
		local ui, chat, gui, hooks = app.ui, app.chat, app.gui, app.hooks
		local folder = chat.getFolder()
		local me = chat.getUserId()
		local list = gui:FindFirstChild("MessageList", true)

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
		local said = ""
		local ctx = {
			addSystemMessage = function(text)
				said = text
			end,
		}
		-- The bot's newest answer to a command
		local function answerTo(command: string): Instance?
			local found
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("BotId") and child:GetAttribute("Command") == command then
					found = child
				end
			end
			return found
		end
		local function rowOf(saved: Instance): Instance?
			for _, child in ipairs(list:GetChildren()) do
				-- Several answers can share a second: match the text too
				local text = child:FindFirstChild("TextContent", true) :: TextLabel?
				if
					child:GetAttribute("Timestamp") == saved:GetAttribute("Timestamp")
					and child:GetAttribute("BotMessage")
					and text
					and string.find(text.ContentText, saved:GetAttribute("Content") or "", 1, true)
				then
					return child
				end
			end
			return nil
		end

		-- Options: typed, checked before the bot sees them
		local options = {
			{ name = "count", type = "integer", required = true },
			{ name = "loud", type = "boolean", required = true },
			{ name = "mode", type = "string", required = true, choices = { { name = "fast", value = "f" } } },
			{ name = "note", type = "string", required = false },
		}
		local values = Bots.parseOptions("x", options, { "3", "yes", "FAST", "a", "long", "note" })
		t.check(
			"options are read by type",
			values ~= nil and values.count == 3 and values.loud == true and values.mode == "f"
		)
		t.equal("…and the last text option takes the rest", values and values.note, "a long note")
		local _, problem = Bots.parseOptions("x", options, { "three" })
		t.check(
			"a number option rejects words: " .. tostring(problem),
			problem ~= nil and string.find(problem, "count", 1, true) ~= nil
		)
		_, problem = Bots.parseOptions("x", options, { "3", "yes", "medium" })
		t.check(
			"a choice option lists the choices: " .. tostring(problem),
			problem ~= nil and string.find(problem, "fast", 1, true) ~= nil
		)
		_, problem = Bots.parseOptions("x", options, {})
		t.check(
			"a missing option shows the usage: " .. tostring(problem),
			problem ~= nil and string.find(problem, "/x <count>", 1, true) ~= nil
		)

		-- Buttons: tidied into rows of at most 5
		local many = {}
		for index = 1, 7 do
			table.insert(many, { label = "B" .. index, customId = tostring(index) })
		end
		local rows = Bots.cleanComponents(many)
		t.check("a flat list of buttons is one row, at most 5", rows ~= nil and #rows == 1 and #rows[1] == 5)
		rows = Bots.cleanComponents({
			{ label = "Site", url = "https://example.com" },
			{ label = "Bad", url = "http://x.com", style = "danger" },
		})
		t.check("an https url makes a link button", rows ~= nil and rows[1][1].style == "link")
		t.check("…other urls are dropped", rows ~= nil and rows[1][2].url == nil and rows[1][2].style == "danger")

		-- A Studio bot using all of it
		local module = Bots.create(scriptName)
		t.check("a Studio bot is made", module ~= nil)
		game:GetService("ScriptEditorService"):UpdateSourceAsync(module, function()
			return BOT_SOURCE
		end)
		Bots.reload()

		app.commands.tryParse("/specroll 2 fast", ctx)
		local rolled
		waitFor(function()
			rolled = answerTo("/specroll")
			return rolled ~= nil
		end, 6)
		t.equal("the bot gets its options' values", rolled and rolled:GetAttribute("Content"), "rolled 2 fast")
		said = ""
		app.commands.tryParse("/specroll two fast", ctx)
		t.check("bad options are caught before the bot runs: " .. said, string.find(said, "dice", 1, true) ~= nil)
		app.commands.tryParse("/specroll 2 medium", ctx)
		t.check("…and wrong choices: " .. said, string.find(said, "slow", 1, true) ~= nil)

		-- Ephemeral: saved for you only, with "Only you can see this"
		app.commands.tryParse("/specsecret", ctx)
		local secret
		waitFor(function()
			secret = answerTo("/specsecret")
			return secret ~= nil
		end, 6)
		t.equal("an ephemeral answer is only for you", secret and secret:GetAttribute("VisibleTo"), me)
		local secretRow
		waitFor(function()
			secretRow = secret and rowOf(secret)
			return secretRow ~= nil
		end, 3)
		t.check("…and says so", secretRow ~= nil and secretRow:FindFirstChild("OnlyYouNote", true) ~= nil)

		-- Deferred: "is thinking…", then the answer in the same place
		app.commands.tryParse("/specslow", ctx)
		local slow
		waitFor(function()
			slow = answerTo("/specslow")
			return slow ~= nil
		end, 6)
		t.check("a deferred answer starts as thinking", slow ~= nil and slow:GetAttribute("Thinking") == true)
		waitFor(function()
			return slow ~= nil and slow:GetAttribute("Content") == "done"
		end, 6)
		t.check(
			"…then the answer replaces it",
			slow ~= nil and slow:GetAttribute("Content") == "done" and slow:GetAttribute("Thinking") == nil
		)
		local slowRow
		waitFor(function()
			slowRow = slow and rowOf(slow)
			local text = slowRow and slowRow:FindFirstChild("TextContent", true)
			return text ~= nil and string.find((text :: any).ContentText or "", "done", 1, true) ~= nil
		end, 3)
		t.check("…and the chat draws it again", slowRow ~= nil)

		-- Buttons: drawn under the message; a click goes to the bot
		app.commands.tryParse("/specbuttons", ctx)
		local picked
		waitFor(function()
			picked = answerTo("/specbuttons")
			return picked ~= nil
		end, 6)
		local pickedRow
		waitFor(function()
			pickedRow = picked and rowOf(picked)
			return pickedRow ~= nil
		end, 3)
		local buttons = pickedRow and pickedRow:FindFirstChild("Components", true)
		t.check("buttons show under the message", buttons ~= nil and buttons:FindFirstChild("Button_go", true) ~= nil)
		Bots.clickButton({ botId = picked and picked:GetAttribute("BotId"), customId = "go", message = picked })
		waitFor(function()
			return picked ~= nil and string.find(picked:GetAttribute("Content") or "", "went go", 1, true) ~= nil
		end, 6)
		t.check(
			"clicking one lets the bot update the message: " .. tostring(picked and picked:GetAttribute("Content")),
			picked ~= nil and string.find(picked:GetAttribute("Content"), "went go by", 1, true) ~= nil
		)

		-- Turned off: its commands say so
		local studioId = picked and picked:GetAttribute("BotId")
		Bots.setDisabled(studioId, true)
		said = ""
		app.commands.tryParse("/specroll 1 slow", ctx)
		t.check("a turned-off bot says it's off: " .. said, string.find(said, "turned off", 1, true) ~= nil)
		Bots.setDisabled(studioId, false)

		-- Web bots
		local badId, badProblem = Bots.createWeb("SpecWeb", "http://example.com/bot")
		t.check("a web bot needs an https url", badId == nil and badProblem == "badUrl")
		webId = Bots.createWeb("SpecWeb", "https://example.com/teamchat")
		t.check("a web bot is made with a token", webId ~= nil and #(Bots.tokenOf(webId) or "") >= 32)
		local oldToken = Bots.tokenOf(webId)
		t.check("…which can be replaced", Bots.regenerateToken(webId) ~= oldToken)
		t.check("…its url can't become plain http", not Bots.updateWeb(webId, { url = "http://example.com" }))
		local listed
		for _, bot in ipairs(Bots.mine()) do
			if bot.id == webId then
				listed = bot
			end
		end
		t.check("it's listed as yours, online", listed ~= nil and listed.kind == "web" and listed.online)

		-- Settings > Developer: your bots and the new-bot form
		ui.openSettings("Developer")
		Harness.settle()
		local portal = gui:FindFirstChild("DeveloperDialog", true)
		t.check("Settings has a Developer tab", portal ~= nil and portal.Visible)
		local webBox = portal and portal:FindFirstChild("Bot_" .. tostring(webId), true)
		t.check(
			"…listing your bots",
			webBox ~= nil and portal:FindFirstChild("Bot_" .. tostring(studioId), true) ~= nil
		)
		local tokenShown = false
		for _, child in ipairs(webBox and webBox:GetDescendants() or {}) do
			if child:IsA("TextBox") and child.Text == Bots.tokenOf(webId) then
				tokenShown = true
			end
		end
		t.check("…with the token hidden", webBox ~= nil and not tokenShown)
		local newTab = portal and portal:FindFirstChild("Tab_new", true)
		if newTab and hooks.clicks[newTab] then
			hooks.clicks[newTab]()
			Harness.settle()
		end
		local kindWeb = portal and portal:FindFirstChild("KindWeb", true)
		if kindWeb and hooks.clicks[kindWeb] then
			hooks.clicks[kindWeb]()
		end
		t.check("picking Web asks for a URL", portal ~= nil and portal:FindFirstChild("UrlInput", true) ~= nil)
		local nameInput = portal and portal:FindFirstChild("NameInput", true) :: TextBox
		local create = portal and portal:FindFirstChild("CreateButton", true)
		if nameInput and create and hooks.clicks[create] then
			nameInput.Text = "bad name!"
			hooks.clicks[create]()
		end
		local status = portal and portal:FindFirstChild("Status", true) :: TextLabel
		t.check("a bad bot name is refused", status ~= nil and string.find(status.Text, "letters", 1, true) ~= nil)

		-- Settings > Admin: the dashboard (or a note for people without a rank)
		ui.openSettings("Admin")
		Harness.settle()
		local dashboard = gui:FindFirstChild("AdminDialog", true)
		t.check("Settings has an Admin tab", dashboard ~= nil and dashboard.Visible)
		local Admin = require(app.copy.Services.Admin) :: any
		if Admin.getMyRank() >= 1 then
			local overview = dashboard:FindFirstChild("Overview", true)
			t.check("…with an overview", overview ~= nil and overview:FindFirstChild("admin.statOnline") ~= nil)
			local function openSection(key: string)
				local tab = dashboard:FindFirstChild("Tab_" .. key, true)
				if tab and hooks.clicks[tab] then
					hooks.clicks[tab]()
					Harness.settle()
				end
			end
			openSection("members")
			t.check("…members", dashboard:FindFirstChild("Members", true) ~= nil)
			openSection("moderation")
			t.check("…slowmode presets", dashboard:FindFirstChild("Slowmode_10", true) ~= nil)
			t.check("…the place's bots", dashboard:FindFirstChild("Bots", true) ~= nil)
			local slow10 = dashboard:FindFirstChild("Slowmode_10", true)
			local before = Admin.getSlowmode()
			if slow10 and hooks.clicks[slow10] then
				hooks.clicks[slow10]()
			end
			t.equal("a slowmode preset sets slowmode", Admin.getSlowmode(), 10)
			Admin.setSlowmode(before)
		else
			t.check("…which says it's for moderators", dashboard:FindFirstChild("NoAccess", true) ~= nil)
		end
		ui.closeSettings()
	end)
	pcall(Bots.remove, scriptName)
	if webId then
		pcall(Bots.remove, webId)
	end
	app.stop()
	if not ok then
		error(err, 0)
	end
end
