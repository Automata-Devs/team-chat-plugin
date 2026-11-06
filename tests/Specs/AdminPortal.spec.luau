--[[
	The advanced admin dashboard and developer portal: the audit log,
	blocked words, chat stats, exports, the dashboard's sections, and a
	bot's test console, logs, stats and editing.
]]

local Harness = require(script.Parent.Parent.Harness)

local BOT_SOURCE = [==[
local bot = { name = "Portal Spec", commands = {} }
bot.commands.portalping = {
	description = "Pong",
	options = { { name = "times", type = "integer", required = false } },
	run = function(ctx)
		ctx.reply({ content = "pong x" .. (ctx.options.times or 1), components = { { label = "Again", customId = "again" } } })
	end,
}
function bot.onButton(ctx, customId)
	ctx.update("clicked " .. customId)
end
return bot
]==]

return function(t)
	local app = Harness.boot({ settings = { TeamChatAboutSeen_v1 = true, TeamChatLastSeenVersion_v1 = "x" } })
	local scriptName = "PortalSpec" .. tostring(math.random(10000, 99999))
	local Bots = require(app.copy.Services.Bots) :: any
	local ok, err = pcall(function()
		local ui, chat, gui = app.ui, app.chat, app.gui
		local Admin = require(app.copy.Services.Admin) :: any
		local Stats = require(app.copy.Services.Chat.Stats) :: any

		-- Audit log: actions through the facade are recorded
		Admin.mute(156, "builderman", "spam", os.time() + 300)
		local entries = Admin.AuditLog.list({ targetId = 156, limit = 5 })
		t.check(
			"a mute is in the audit log, with its reason",
			entries[1] ~= nil and entries[1].action == "mute" and entries[1].reason == "spam"
		)
		Admin.unmute(156)
		local unmuted = Admin.AuditLog.list({ action = "unmute", limit = 1 })[1]
		t.equal("…and the unmute too, with the name", unmuted and unmuted.targetName, "builderman")
		t.check("the log can be searched", #Admin.AuditLog.list({ query = "builderman" }) >= 2)
		local slowmodeBefore = Admin.getSlowmode()
		Admin.setSlowmode(7)
		Admin.setSlowmode(0)
		local latest = Admin.AuditLog.list({ action = "slowmode", limit = 2 })
		t.check(
			"…newest first, even in the same second",
			latest[1] ~= nil and latest[1].detail == "off" and latest[2] ~= nil and latest[2].detail == "7s"
		)
		Admin.setSlowmode(slowmodeBefore)

		-- Blocked words
		local rules = Admin.ChatRules
		t.check("a word can be blocked", rules.addBlockedWord("Specword"))
		t.equal("…as a whole word, any case", rules.findBlocked("no SPECWORD here"), "specword")
		t.equal("…not inside other words", rules.findBlocked("specwords"), nil)
		rules.removeBlockedWord("specword")
		t.equal("…and unblocked", rules.findBlocked("specword"), nil)

		-- Stats
		local before = Stats.collect(7)
		chat.sendMessage("counting this one")
		Harness.settle()
		local after = Stats.collect(7)
		t.equal("stats count today's messages", after.perDay[7].count, before.perDay[7].count + 1)
		local hours = 0
		for _, count in ipairs(after.byHour) do
			hours += count
		end
		t.equal("…per hour too", hours, after.recent)
		t.check("…and per person", after.users[chat.getUserId()] ~= nil)
		t.check("the transcript has the message", string.find(Stats.transcript(), "counting this one", 1, true) ~= nil)

		-- The dashboard's sections
		ui.openSettings("Admin")
		Harness.settle(3)
		local dashboard = gui:FindFirstChild("AdminDialog", true)
		if Admin.getMyRank() >= 1 then
			t.check("the dashboard has section tabs", dashboard:FindFirstChild("Tab_audit", true) ~= nil)
			t.check(
				"…and charts on the overview",
				dashboard:FindFirstChild("PerDay", true) ~= nil and dashboard:FindFirstChild("ByHour", true) ~= nil
			)
		else
			t.check("(not a moderator here: the dashboard says so)", dashboard:FindFirstChild("NoAccess", true) ~= nil)
		end
		ui.closeSettings()

		-- A Studio bot in the portal
		local module = Bots.create(scriptName)
		game:GetService("ScriptEditorService"):UpdateSourceAsync(module, function()
			return BOT_SOURCE
		end)
		Bots.reload()
		local id = module:GetAttribute("BotId")
		local result = Bots.test(id, { command = "portalping", args = { "3" } })
		t.check(
			"the test console runs a command" .. (if result.error then ": " .. tostring(result.error) else ""),
			result.ok and result.messages[1] ~= nil and result.messages[1].content == "pong x3"
		)
		local clicked = Bots.test(id, { button = "again" })
		t.check(
			"…and a button (it updates the message)",
			clicked.ok
				and clicked.messages[1] ~= nil
				and clicked.messages[1].update == true
				and clicked.messages[1].content == "clicked again"
		)
		local posted = false
		for _, child in ipairs(chat.getFolder():GetChildren()) do
			posted = posted or child:GetAttribute("Content") == "pong x3"
		end
		t.check("tests don't post in the chat", not posted)
		local log = Bots.logOf(id)
		t.check("tests are logged as tests", log[1] ~= nil and log[1].test == true)
		t.equal("…but don't count as use", Bots.statsOf(id).total, 0)

		-- Real use (typed in the chat) is counted, per command
		app.commands.tryParse("/portalping 2", { addSystemMessage = function() end })
		local deadline = os.clock() + 5
		while os.clock() < deadline and Bots.statsOf(id).total == 0 do
			task.wait(0.1)
		end
		local used = Bots.statsOf(id)
		t.equal("a real command counts as use", used.total, 1)
		t.equal("…for that command", used.commands[1] and used.commands[1].name, "/portalping")
		t.check("…with its time", used.averageMs ~= nil)

		-- Editing
		t.check(
			"a bot can be renamed in the portal",
			Bots.editBot(id, { name = "Renamed Spec", disabledCommands = { "portalping" } })
		)
		local listed
		for _, bot in ipairs(Bots.mine()) do
			if bot.id == id then
				listed = bot
			end
		end
		t.equal("…and shows with that name", listed and listed.name, "Renamed Spec")
		local offered = false
		for _, command in ipairs(Bots.commands()) do
			offered = offered or command.name == "portalping"
		end
		t.check("a command turned off isn't offered", not offered)

		-- The portal's pages
		ui.openSettings("Developer")
		Harness.settle(2)
		local portal = gui:FindFirstChild("DeveloperDialog", true)
		t.check("the portal has Your bots, New bot and Docs", portal:FindFirstChild("Tab_docs", true) ~= nil)
		ui.developerDialog.openBot(id, "logs")
		Harness.settle(2)
		t.check("a bot's logs page shows its log", portal:FindFirstChild("Log", true) ~= nil)
		ui.developerDialog.openBot(id, "edit")
		Harness.settle(2)
		t.check("…and the edit page its commands", portal:FindFirstChild("Command_portalping", true) ~= nil)
		ui.closeSettings()
	end)
	pcall(Bots.remove, scriptName)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
