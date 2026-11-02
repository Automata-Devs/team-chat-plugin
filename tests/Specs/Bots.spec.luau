--[[
	User-made bots: a bot script runs in its owner's Studio, publishes its
	commands, and answers them for everyone. Uses a throwaway bot that is
	removed at the end.
]]

local Harness = require(script.Parent.Parent.Harness)

local BOT_SOURCE = [==[
return {
	name = "Spec Bot",
	description = "A bot made by the test",
	commands = {
		spececho = {
			description = "Says it back",
			args = { { name = "text", description = "What to say" } },
			run = function(ctx)
				ctx.reply("echo: " .. ctx.text)
			end,
		},
		speccard = {
			description = "Answers with a card",
			run = function(ctx)
				ctx.reply({ title = "Card for " .. ctx.user.name, fields = { { name = "Args", value = tostring(#ctx.args) } } })
			end,
		},
	},
}
]==]

return function(t)
	local app = Harness.boot()
	local scriptName = "SpecBot" .. tostring(math.random(10000, 99999))
	local Bots = require(app.copy.Services.Bots) :: any
	local ok, err = pcall(function()
		local ui, chat, gui = app.ui, app.chat, app.gui
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

		-- Making a bot: a script you own, from the template
		local module = Bots.create(scriptName)
		t.check("/bot create makes a bot script you own", module ~= nil and module:GetAttribute("OwnerId") == me)
		t.check(
			"…from the template",
			module ~= nil and string.find(module.Source, "bot.commands.hello", 1, true) ~= nil
		)

		-- Give it the test commands and load it
		game:GetService("ScriptEditorService"):UpdateSourceAsync(module, function()
			return BOT_SOURCE
		end)
		local names = Bots.reload()
		t.check("reloading starts your bots: " .. table.concat(names, ", "), table.find(names, "Spec Bot") ~= nil)
		local offered = {}
		for _, command in ipairs(Bots.commands()) do
			offered[command.name] = command
		end
		t.check("its commands are published", offered.spececho ~= nil and offered.speccard ~= nil)
		t.equal("…with their arguments", offered.spececho and offered.spececho.args[1].name, "text")
		local inList = false
		for _, command in ipairs(app.commands.getCommandList()) do
			inList = inList or command.name == "spececho"
		end
		t.check("bot commands show in autocomplete", inList)

		-- Using a command: the bot answers for everyone
		local before = {}
		for _, child in ipairs(folder:GetChildren()) do
			before[child] = true
		end
		ui.textBox.Text = "/spececho hi there"
		Harness.settle()
		ui.textBox.Text = "/spececho hi there\n"
		local answer
		waitFor(function()
			for _, child in ipairs(folder:GetChildren()) do
				if not before[child] and child:GetAttribute("BotId") then
					answer = child
				end
			end
			return answer ~= nil
		end, 6)
		t.check("the bot answers in the chat", answer ~= nil)
		if answer then
			t.equal("…with what it says", answer:GetAttribute("Content"), "echo: hi there")
			t.equal("…as the bot", answer:GetAttribute("Sender"), "Spec Bot")
			t.equal("…for the person who used it", answer:GetAttribute("SaidBy"), me)
			t.equal("…naming the command", answer:GetAttribute("Command"), "/spececho")
			local row
			waitFor(function()
				for _, child in ipairs(list:GetChildren()) do
					if
						child:GetAttribute("Timestamp") == answer:GetAttribute("Timestamp")
						and child:GetAttribute("BotMessage")
					then
						row = child
					end
				end
				return row ~= nil
			end, 3)
			local tag = row and row:FindFirstChild("BotTag", true) :: TextLabel
			t.check("it shows with a plain BOT tag (no check)", tag ~= nil and tag.Text == "BOT")
			local used = row and row:FindFirstChild("ReplyLabel", true) :: TextLabel
			t.check(
				'…under "<you> used /spececho"',
				used ~= nil and string.find(used.ContentText, "used /spececho", 1, true) ~= nil
			)
			answer:Destroy()
		end

		-- A card answer
		app.commands.tryParse("/speccard a b", { addSystemMessage = function() end })
		local card
		waitFor(function()
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("BotId") and child:GetAttribute("Embed") then
					card = child
				end
			end
			return card ~= nil
		end, 6)
		t.check(
			"bots can answer with cards",
			card ~= nil and string.find(card:GetAttribute("Embed"), "Card for", 1, true) ~= nil
		)
		if card then
			card:Destroy()
		end

		-- Offline: the owner isn't here, so you're told instead
		local manifestFolder
		for _, manifest in ipairs(game:GetService("ServerStorage"):GetDescendants()) do
			if manifest:GetAttribute("Manifest") and manifest:GetAttribute("Name") == "Spec Bot" then
				manifestFolder = manifest
			end
		end
		local said = ""
		if manifestFolder then
			manifestFolder:SetAttribute("LastSeen", 0)
		end
		app.commands.tryParse("/spececho anyone?", {
			addSystemMessage = function(text)
				said = text
			end,
		})
		t.check("an offline bot's command says it's offline: " .. said, string.find(said, "offline", 1, true) ~= nil)

		-- Removing it
		t.check("you can remove your bot", Bots.remove(scriptName))
		local gone = true
		for _, command in ipairs(Bots.commands()) do
			gone = gone and command.name ~= "spececho"
		end
		t.check("…and its commands go with it", gone)
	end)
	pcall(Bots.remove, scriptName)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
