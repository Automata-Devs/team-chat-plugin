--!strict
--[[
	DeveloperDialog

	The developer portal (Settings > Developer), like Discord's: your bots,
	a new bot form, and the docs. Each bot has its own page:
	  - Overview: status and a health check, its commands, URL and token
	    (web bots) or script (Studio bots), turn off and delete;
	  - Console: run its commands and click its buttons without posting in
	    the chat, and see exactly what it answers (Services/Bots.test);
	  - Logs: its recent interactions with errors and response times, and
	    how much each command is used;
	  - Edit: its name, description and avatar as Team Chat shows them, and
	    which commands people can use (over what the script or server says).
	The Docs tab has a quick start, the web bot payloads and starter
	servers to copy. docs/BOTS.md explains bots in full.
]]

local Bots = require(script.Parent.Parent.Parent.Services.Bots)
local Browser = require(script.Parent.Parent.Parent.Core.Browser)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Markdown = require(script.Parent.Parent.Parent.Util.Markdown)
local PanelKit = require(script.Parent.PanelKit)

local Z = 32
local MASKED = string.rep("\u{2022}", 12)
local DOCS_URL = "https://github.com/Automata-Devs/team-chat-plugin/blob/main/docs/BOTS.md"
local CONSOLE_KEEP = 10 -- results kept in a bot's console

local SECTIONS = { "bots", "new", "docs" }
local PAGES = { "overview", "console", "logs", "edit" }

local NODE_STARTER = [==[// A Team Chat web bot (Node.js + Express)
// npm install express, then: TEAMCHAT_TOKEN=... node bot.js
const express = require("express");
const app = express();
app.use(express.json());
const TOKEN = process.env.TEAMCHAT_TOKEN; // from the portal

app.post("/teamchat", (req, res) => {
  if (req.get("X-TeamChat-Token") !== TOKEN) {
    return res.sendStatus(401);
  }
  const body = req.body;
  if (body.type === "ping") {
    return res.json({
      type: "pong",
      name: "Starter",
      description: "Says hello",
      commands: [{
        name: "hello",
        description: "Say hello",
        options: [{ name: "name", type: "string", required: false }],
      }],
    });
  }
  if (body.type === "command" && body.command === "hello") {
    const who = body.options.name || body.user.name;
    return res.json({
      type: "message",
      content: `Hello, **${who}**!`,
      components: [
        { label: "Wave back", style: "primary", customId: "wave" },
      ],
    });
  }
  if (body.type === "button" && body.customId === "wave") {
    const who = body.user.name;
    return res.json({ type: "update", content: `${who} waved` });
  }
  res.json({ type: "none" });
});

app.listen(3000);]==]

local PYTHON_STARTER = [==[# A Team Chat web bot (Python + Flask)
# pip install flask, then: TEAMCHAT_TOKEN=... python bot.py
import os
from flask import Flask, request, jsonify, abort

app = Flask(__name__)
TOKEN = os.environ["TEAMCHAT_TOKEN"]  # from the portal

HELLO = {
    "name": "hello",
    "description": "Say hello",
    "options": [
        {"name": "name", "type": "string", "required": False},
    ],
}
WAVE = {"label": "Wave back", "style": "primary", "customId": "wave"}

@app.post("/teamchat")
def teamchat():
    if request.headers.get("X-TeamChat-Token") != TOKEN:
        abort(401)
    body = request.get_json()
    if body["type"] == "ping":
        return jsonify(type="pong", name="Starter",
                       description="Says hello", commands=[HELLO])
    if body["type"] == "command" and body["command"] == "hello":
        who = body["options"].get("name") or body["user"]["name"]
        return jsonify(type="message",
                       content=f"Hello, **{who}**!",
                       components=[WAVE])
    if body["type"] == "button" and body["customId"] == "wave":
        who = body["user"]["name"]
        return jsonify(type="update", content=f"{who} waved")
    return jsonify(type="none")

app.run(port=3000)]==]

local REQUEST_EXAMPLE = [==[POST <your URL>
X-TeamChat-Token: <token>

{ "type": "command", "id": "8F1C…", "test": false,
  "bot": { "id": "…" },
  "user": { "id": 156, "name": "builderman" },
  "place": { "id": 1818 }, "conversation": "main",
  "command": "hello", "options": { "name": "Ana" },
  "args": ["Ana"] }

{ "type": "button", "customId": "wave",
  "message": { "id": "…", "content": "…" }, … }

{ "type": "ping" }
  -> answer { "type": "pong", "name", "commands": [ … ] }

{ "type": "followup", "id": "8F1C…" }
  (after a "deferred" answer, every 2 s)]==]

local ANSWER_EXAMPLE = [==[{ "type": "message", "content": "Hi **there**",
  "ephemeral": false,
  "embed": {
    "title": "Card", "description": "…", "color": "#5865F2",
    "fields": [ { "name": "A", "value": "1", "inline": true } ] },
  "components": [
    { "label": "Again", "style": "primary", "customId": "again" },
    { "label": "Docs", "style": "link", "url": "https://…" } ] }

{ "type": "update", … }   change the message the button is on
{ "type": "deferred" }    show "is thinking…", then answer followups
{ "type": "none" }        show nothing]==]

local STUDIO_EXAMPLE = [==[bot.commands.roll = {
	description = "Roll a die",
	options = {
		{ name = "sides", type = "integer", required = false },
	},
	run = function(ctx)
		local sides = ctx.options.sides or 6
		ctx.reply({
			content = "You rolled " .. math.random(sides),
			components = {
				{ label = "Roll again", customId = "again" },
			},
		})
	end,
}

function bot.onButton(ctx, customId)
	ctx.update("Rolled again: " .. math.random(6))
end]==]

local DeveloperDialog = {}

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function when(time: number?): string
	return if time and time > 0 then os.date("%d/%m %H:%M", time) else "-"
end

--!
-- kit: a ModalKit. params: { getThemeColors, openScript: (LuaSourceContainer) -> () }
-- Returns { open(), close(), isVisible(), recolor(), modal }
--!
function DeveloperDialog.create(kit, params)
	local modal = kit.createModal({ name = "DeveloperDialog", title = "Developer", iconKey = "command", zIndex = Z })
	local card = modal.card
	local z = modal.contentZIndex
	local keep = {}
	for _, child in ipairs(card:GetChildren()) do
		keep[child] = true -- the modal's own title, close button and layout
	end

	local section = "bots"
	local openBot: string? = nil -- a bot's page
	local page = "overview"
	local shownTokens: { [string]: boolean } = {}
	local consoles: { [string]: { any } } = {} -- each bot's test results, newest first
	local consoleInput: { [string]: string } = {}
	local running = false -- a test or check is on its way
	local newKind = "studio"
	local confirming: string? = nil
	local status = "" -- the last thing that happened ("Created Weather", an error…)

	local self = { modal = modal }
	local render: () -> ()

	local function setStatus(text: string)
		status = text
		confirming = nil
		render()
	end

	local function botById(id: string)
		for _, bot in ipairs(Bots.mine()) do
			if bot.id == id then
				return bot
			end
		end
		return nil
	end

	local function statusPill(parent: Instance, bot, order: number, colors)
		PanelKit.pill(
			parent,
			Language.t(if bot.disabled then "dev.disabled" elseif bot.online then "dev.online" else "dev.offline"),
			if bot.disabled then colors.danger elseif bot.online then colors.success else colors.timestamp,
			order,
			z
		)
	end

	---------------------------------------------------------------------------
	-- A bot's page
	---------------------------------------------------------------------------

	local function overviewPage(bot, colors, nextOrder: () -> number)
		-- Health
		local health = PanelKit.box(card, nextOrder(), z, colors)
		health.Name = "Health"
		local checked = bot.health and bot.health.time
		PanelKit.text(
			health,
			if checked
				then Language.t(if bot.health.ok then "dev.healthOk" else "dev.healthBad", {
					time = when(checked),
					ms = tostring(bot.health.ms or "-"),
					error = tostring(bot.health.error or ""),
				})
				else Language.t("dev.healthNever"),
			"body",
			1,
			z,
			colors
		)
		if bot.kind == "studio" then
			PanelKit.text(health, Language.t("dev.lastSeen", { time = when(bot.lastSeen) }), "muted", 2, z, colors)
		end
		PanelKit.button(
			health,
			Language.t(if running then "dev.checking" else "dev.check"),
			"secondary",
			3,
			z,
			colors,
			function()
				if running then
					return
				end
				running = true
				render()
				task.spawn(function()
					local result = Bots.checkHealth(bot.id)
					running = false
					setStatus(if result.ok
						then Language.t("dev.healthNow", { ms = tostring(result.ms or "-") })
						else Language.t("dev.healthFailed", {
							error = Language.tOr("dev.error." .. tostring(result.error), tostring(result.error)),
						}))
				end)
			end
		).Name =
			"Check"

		-- Commands
		PanelKit.text(card, Language.t("dev.commands", { count = #bot.commands }), "heading", nextOrder(), z, colors)
		local commandBox = PanelKit.box(card, nextOrder(), z, colors)
		commandBox.Name = "Commands"
		if #bot.commands == 0 then
			PanelKit.text(commandBox, Language.t("dev.noCommands"), "muted", 1, z, colors)
		end
		for index, command in ipairs(bot.commands) do
			local options = {}
			for _, option in ipairs(command.options) do
				table.insert(
					options,
					(if option.required then "<" else "[")
						.. option.name
						.. ": "
						.. option.type
						.. (if option.required then ">" else "]")
				)
			end
			PanelKit.text(
				commandBox,
				"<b>/"
					.. command.name
					.. "</b> "
					.. escape(table.concat(options, " "))
					.. (if command.description ~= "" then "\n" .. escape(command.description) else "")
					.. (if command.enabled then "" else "  \u{00B7}  " .. Language.t("dev.commandOff")),
				"body",
				index,
				z,
				colors
			)
		end

		-- Web bot: URL and token; Studio bot: its script
		if bot.kind == "web" then
			PanelKit.text(card, Language.t("dev.url"), "heading", nextOrder(), z, colors)
			local urlRow = PanelKit.row(card, nextOrder(), z)
			local url = PanelKit.input(urlRow, bot.url or "", "https://", 1, z, colors, { width = UDim.new(1, -70) })
			PanelKit.button(urlRow, Language.t("dev.save"), "secondary", 2, z, colors, function()
				setStatus(Language.t(if Bots.updateWeb(bot.id, { url = url.Text }) then "dev.saved" else "dev.badUrl"))
			end)
			PanelKit.text(card, Language.t("dev.token"), "heading", nextOrder(), z, colors)
			local tokenRow = PanelKit.row(card, nextOrder(), z)
			local token = Bots.tokenOf(bot.id) or ""
			PanelKit.input(
				tokenRow,
				if shownTokens[bot.id] then token else MASKED .. string.sub(token, -4),
				"",
				1,
				z,
				colors,
				{ width = UDim.new(1, -150), readOnly = true, mono = true }
			).Name =
				"Token"
			PanelKit.button(
				tokenRow,
				Language.t(if shownTokens[bot.id] then "dev.hide" else "dev.show"),
				"secondary",
				2,
				z,
				colors,
				function()
					shownTokens[bot.id] = not shownTokens[bot.id]
					render()
				end
			)
			PanelKit.button(tokenRow, Language.t("dev.newToken"), "secondary", 3, z, colors, function()
				Bots.regenerateToken(bot.id)
				shownTokens[bot.id] = true
				setStatus(Language.t("dev.tokenChanged"))
			end)
			PanelKit.text(card, Language.t("dev.tokenHint"), "muted", nextOrder(), z, colors)
		end

		local actions = PanelKit.row(card, nextOrder(), z)
		actions.Name = "Actions"
		if bot.kind == "web" then
			PanelKit.button(actions, Language.t("dev.sync"), "primary", 1, z, colors, function()
				setStatus(Language.t("dev.syncing"))
				task.spawn(function()
					local count, problem = Bots.syncWeb(bot.id)
					setStatus(
						if count
							then Language.t("dev.synced", { count = count })
							else Language.t("dev.syncFailed", { error = tostring(problem) })
					)
				end)
			end)
		else
			PanelKit.button(actions, Language.t("dev.openScript"), "primary", 1, z, colors, function()
				local module = Bots.scriptOf(bot.id)
				if module and params.openScript then
					params.openScript(module)
				end
			end)
			PanelKit.button(actions, Language.t("dev.reload"), "secondary", 2, z, colors, function()
				local names = Bots.reload()
				setStatus(Language.t("bot.reloaded", { names = table.concat(names, ", ") }))
			end)
		end
		PanelKit.button(
			actions,
			Language.t(if bot.disabled then "dev.turnOn" else "dev.turnOff"),
			"secondary",
			3,
			z,
			colors,
			function()
				Bots.setDisabled(bot.id, not bot.disabled)
				render()
			end
		)
		local deleteKey = "delete" .. bot.id
		PanelKit.button(
			actions,
			Language.t(if confirming == deleteKey then "dev.confirmDelete" else "dev.delete"),
			"danger",
			4,
			z,
			colors,
			function()
				if confirming ~= deleteKey then
					confirming = deleteKey
					render()
					return
				end
				Bots.remove(bot.id)
				openBot = nil
				setStatus(Language.t("bot.removed", { name = bot.name }))
			end
		).Name =
			"Delete"
	end

	-- One answer in the console: its text, card and buttons (they run too)
	local function consoleMessage(parent: Instance, message, order: number, colors, run: (input: any) -> ())
		local box = PanelKit.box(parent, order, z, colors)
		box.Name = "Answer"
		if message.update then
			PanelKit.text(box, Language.t("dev.updates"), "muted", 0, z, colors)
		end
		if message.ephemeral then
			PanelKit.text(box, Language.t("bot.onlyYou"), "muted", 0.5, z, colors)
		end
		if message.content and message.content ~= "" then
			PanelKit.text(box, Markdown.parse(message.content, colors, { textSize = 13 }).markup, "body", 1, z, colors).Name =
				"Content"
		end
		local embed = message.embed
		if type(embed) == "table" then
			local lines = {}
			if embed.title then
				table.insert(lines, "<b>" .. escape(tostring(embed.title)) .. "</b>")
			end
			if embed.description then
				table.insert(lines, escape(tostring(embed.description)))
			end
			for _, field in ipairs(if type(embed.fields) == "table" then embed.fields else {}) do
				table.insert(lines, "<b>" .. escape(tostring(field.name)) .. "</b>: " .. escape(tostring(field.value)))
			end
			PanelKit.text(box, table.concat(lines, "\n"), "body", 2, z, colors).Name = "Embed"
		end
		for rowIndex, buttons in ipairs(Bots.cleanComponents(message.components) or {}) do
			local row = PanelKit.row(box, 2 + rowIndex, z)
			row.Name = "Buttons"
			for index, button in ipairs(buttons) do
				PanelKit.button(
					row,
					tostring(button.label) .. (if button.url then " \u{2197}" else ""),
					if button.style == "danger"
						then "danger"
						elseif button.style == "primary" then "primary"
						else "secondary",
					index,
					z,
					colors,
					function()
						if button.url then
							Browser.open(button.url)
						elseif button.customId then
							run({ button = button.customId })
						end
					end
				).Name = "Button_"
					.. tostring(button.customId or index)
			end
		end
	end

	local function consolePage(bot, colors, nextOrder: () -> number)
		local results = consoles[bot.id] or {}
		consoles[bot.id] = results
		PanelKit.text(card, Language.t("dev.consoleHint"), "muted", nextOrder(), z, colors)
		local function run(input)
			if running then
				return
			end
			running = true
			render()
			task.spawn(function()
				local result = Bots.test(bot.id, input)
				running = false
				table.insert(results, 1, { input = input, result = result, time = os.time() })
				while #results > CONSOLE_KEEP do
					table.remove(results)
				end
				status = ""
				render()
			end)
		end
		self.runTest = run -- for tests
		local inputRow = PanelKit.row(card, nextOrder(), z)
		inputRow.Name = "ConsoleInput"
		local field = PanelKit.input(
			inputRow,
			consoleInput[bot.id] or "",
			"/command options",
			1,
			z,
			colors,
			{ width = UDim.new(1, -80), mono = true }
		)
		field.Name = "Command"
		field.FocusLost:Connect(function()
			consoleInput[bot.id] = field.Text
		end)
		PanelKit.button(
			inputRow,
			Language.t(if running then "dev.running" else "dev.run"),
			"primary",
			2,
			z,
			colors,
			function()
				consoleInput[bot.id] = field.Text
				local words = {}
				for word in string.gmatch(field.Text, "%S+") do
					table.insert(words, word)
				end
				local name = table.remove(words, 1)
				if not name then
					return
				end
				run({ command = (string.gsub(name, "^/", "")), args = words })
			end
		).Name =
			"Run"
		-- Quick picks: the bot's commands
		local picks = PanelKit.row(card, nextOrder(), z)
		picks.Name = "Picks"
		for index, command in ipairs(bot.commands) do
			PanelKit.button(picks, "/" .. command.name, "secondary", index, z, colors, function()
				consoleInput[bot.id] = "/" .. command.name .. " "
				render()
			end)
		end

		if #results == 0 then
			PanelKit.text(card, Language.t("dev.consoleEmpty"), "muted", nextOrder(), z, colors)
		end
		for _, entry in ipairs(results) do
			local input = entry.input
			local result = entry.result
			local heading = if input.button
				then Language.t("dev.clicked", { id = input.button })
				else "/" .. input.command .. " " .. table.concat(input.args or {}, " ")
			PanelKit.text(
				card,
				'<font transparency="0.4">'
					.. when(entry.time)
					.. "</font>  <b>"
					.. escape(heading)
					.. "</b>  "
					.. (
						if result.ok
							then Language.t("dev.testOk", { ms = result.ms })
							else Language.t("dev.testFailed", {
								error = escape(
									Language.tOr("dev.error." .. tostring(result.error), tostring(result.error))
								),
							})
					),
				"body",
				nextOrder(),
				z,
				colors
			).Name =
				"Result"
			if result.ok and #result.messages == 0 then
				PanelKit.text(card, Language.t("dev.noAnswerTest"), "muted", nextOrder(), z, colors)
			end
			for _, message in ipairs(result.messages) do
				consoleMessage(card, message, nextOrder(), colors, run)
			end
		end
	end

	local function logsPage(bot, colors, nextOrder: () -> number)
		local stats = Bots.statsOf(bot.id)
		local tiles = PanelKit.row(card, nextOrder(), z)
		tiles.Name = "Stats"
		PanelKit.tile(tiles, Language.t("dev.uses"), tostring(stats.total), 1, z, colors)
		PanelKit.tile(tiles, Language.t("dev.errors"), tostring(stats.errors), 2, z, colors)
		PanelKit.tile(
			tiles,
			Language.t("dev.averageMs"),
			if stats.averageMs then stats.averageMs .. " ms" else "-",
			3,
			z,
			colors
		)
		PanelKit.text(card, Language.t("dev.mostUsed"), "heading", nextOrder(), z, colors)
		if #stats.commands == 0 then
			PanelKit.text(card, Language.t("dev.notUsed"), "muted", nextOrder(), z, colors)
		else
			local items = {}
			for index, command in ipairs(stats.commands) do
				if index > 8 then
					break
				end
				table.insert(items, { label = escape(command.name), value = command.count })
			end
			PanelKit.bars(card, items, nextOrder(), z, colors).Name = "MostUsed"
		end

		local entries = Bots.logOf(bot.id)
		PanelKit.text(card, Language.t("dev.recent", { count = #entries }), "heading", nextOrder(), z, colors)
		local box = PanelKit.box(card, nextOrder(), z, colors)
		box.Name = "Log"
		if #entries == 0 then
			PanelKit.text(box, Language.t("dev.logEmpty"), "muted", 1, z, colors)
		end
		for index, entry in ipairs(entries) do
			local what = if entry.kind == "ping"
				then Language.t("dev.healthCheck")
				elseif entry.kind == "button" then Language.t("dev.clicked", { id = tostring(entry.name) })
				else "/" .. tostring(entry.name)
			PanelKit.text(
				box,
				'<font transparency="0.4">'
					.. when(entry.t)
					.. "</font>  <b>"
					.. escape(what)
					.. "</b>"
					.. (if entry.user then "  \u{00B7}  " .. escape(tostring(entry.user)) else "")
					.. (if entry.ms then "  \u{00B7}  " .. entry.ms .. " ms" else "")
					.. (if entry.test then "  \u{00B7}  " .. Language.t("dev.test") else "")
					.. (if entry.ok then "" else "\n\u{26A0} " .. escape(tostring(entry.error or "?"))),
				"body",
				index,
				z,
				colors
			).Name = if entry.ok
				then "Entry"
				else "Error"
		end
		PanelKit.button(card, Language.t("dev.clearLog"), "secondary", nextOrder(), z, colors, function()
			Bots.clearLog(bot.id)
			setStatus(Language.t("dev.logCleared"))
		end).Name =
			"ClearLog"
	end

	local function editPage(bot, colors, nextOrder: () -> number)
		PanelKit.text(card, Language.t("dev.editHint"), "muted", nextOrder(), z, colors)
		local form = PanelKit.box(card, nextOrder(), z, colors)
		form.Name = "EditForm"
		PanelKit.text(form, Language.t("dev.name"), "heading", 1, z, colors)
		local name = PanelKit.input(form, bot.name, bot.name, 2, z, colors)
		name.Name = "NameInput"
		PanelKit.text(form, Language.t("dev.description"), "heading", 3, z, colors)
		local description =
			PanelKit.input(form, bot.description, Language.t("dev.descriptionPlaceholder"), 4, z, colors)
		description.Name = "DescriptionInput"
		PanelKit.text(form, Language.t("dev.avatar"), "heading", 5, z, colors)
		local avatarRow = PanelKit.row(form, 6, z)
		PanelKit.avatar(avatarRow, nil, 30, 1, z, colors).Image = bot.avatar or ""
		local avatar = PanelKit.input(
			avatarRow,
			bot.avatar or "",
			"rbxassetid://… " .. Language.t("dev.orImageId"),
			2,
			z,
			colors,
			{ width = UDim.new(1, -40) }
		)
		avatar.Name = "AvatarInput"
		PanelKit.button(form, Language.t("dev.saveDetails"), "primary", 7, z, colors, function()
			local ok = Bots.editBot(bot.id, { name = name.Text, description = description.Text, avatar = avatar.Text })
			setStatus(Language.t(if ok then "dev.saved" else "dev.notYours"))
		end).Name =
			"SaveDetails"

		-- Commands: on or off, and their description
		PanelKit.text(card, Language.t("dev.commands", { count = #bot.commands }), "heading", nextOrder(), z, colors)
		local list = PanelKit.box(card, nextOrder(), z, colors)
		list.Name = "EditCommands"
		if #bot.commands == 0 then
			PanelKit.text(list, Language.t("dev.noCommands"), "muted", 1, z, colors)
			return
		end
		local enabled: { [string]: boolean } = {}
		local notes: { [string]: TextBox } = {}
		for index, command in ipairs(bot.commands) do
			enabled[command.name] = command.enabled
			local row = PanelKit.row(list, index, z)
			row.Name = "Command_" .. command.name
			local toggle: TextButton
			toggle = PanelKit.button(
				row,
				Language.t(if command.enabled then "dev.on" else "dev.off"),
				if command.enabled then "primary" else "secondary",
				1,
				z,
				colors,
				function()
					enabled[command.name] = not enabled[command.name]
					toggle.Text = Language.t(if enabled[command.name] then "dev.on" else "dev.off")
				end
			)
			toggle.Name = "Toggle"
			PanelKit.text(row, "<b>/" .. command.name .. "</b>", "body", 2, z, colors).Size = UDim2.fromOffset(110, 28)
			notes[command.name] = PanelKit.input(
				row,
				command.description,
				Language.t("dev.descriptionPlaceholder"),
				3,
				z,
				colors,
				{ width = UDim.new(1, -190) }
			)
		end
		PanelKit.button(card, Language.t("dev.saveCommands"), "primary", nextOrder(), z, colors, function()
			local off, texts = {}, {}
			for _, command in ipairs(bot.commands) do
				if not enabled[command.name] then
					table.insert(off, command.name)
				end
				texts[command.name] = notes[command.name].Text
			end
			local ok = Bots.editBot(bot.id, { disabledCommands = off, commandNotes = texts })
			setStatus(Language.t(if ok then "dev.saved" else "dev.notYours"))
		end).Name =
			"SaveCommands"
	end

	local function botPage(bot, colors, nextOrder: () -> number)
		PanelKit.button(card, Language.t("dev.back"), "secondary", nextOrder(), z, colors, function()
			openBot = nil
			render()
		end).Name =
			"Back"
		local header = PanelKit.row(card, nextOrder(), z)
		header.Name = "BotHeader"
		PanelKit.avatar(header, nil, 36, 1, z, colors).Image = bot.avatar or ""
		local title = PanelKit.text(header, "<b>" .. escape(bot.name) .. "</b>", "title", 2, z, colors)
		title.AutomaticSize = Enum.AutomaticSize.XY
		title.Size = UDim2.fromOffset(0, 0)
		PanelKit.pill(
			header,
			Language.t(if bot.kind == "web" then "dev.kindWeb" else "dev.kindStudio"),
			colors.sendButton,
			3,
			z
		)
		statusPill(header, bot, 4, colors)
		if bot.description ~= "" then
			PanelKit.text(card, escape(bot.description), "muted", nextOrder(), z, colors)
		end
		local tabs = {}
		for _, key in ipairs(PAGES) do
			table.insert(tabs, { key = key, label = Language.t("dev.page." .. key) })
		end
		PanelKit.tabs(card, tabs, page, nextOrder(), z, colors, function(key)
			page = key
			confirming = nil
			render()
		end).Name =
			"Pages"
		if page == "console" then
			consolePage(bot, colors, nextOrder)
		elseif page == "logs" then
			logsPage(bot, colors, nextOrder)
		elseif page == "edit" then
			editPage(bot, colors, nextOrder)
		else
			overviewPage(bot, colors, nextOrder)
		end
	end

	---------------------------------------------------------------------------
	-- Sections
	---------------------------------------------------------------------------

	local function botsSection(colors, nextOrder: () -> number)
		local mine = Bots.mine()
		PanelKit.text(card, Language.t("dev.intro"), "muted", nextOrder(), z, colors)
		PanelKit.text(card, Language.t("dev.yourBots"), "heading", nextOrder(), z, colors)
		if #mine == 0 then
			PanelKit.text(card, Language.t("dev.noBots"), "muted", nextOrder(), z, colors)
		end
		for _, bot in ipairs(mine) do
			local box = PanelKit.box(card, nextOrder(), z, colors)
			box.Name = "Bot_" .. bot.id
			local header = PanelKit.row(box, 1, z)
			PanelKit.avatar(header, nil, 28, 1, z, colors).Image = bot.avatar or ""
			local title = PanelKit.text(header, "<b>" .. escape(bot.name) .. "</b>", "title", 2, z, colors)
			title.AutomaticSize = Enum.AutomaticSize.XY
			title.Size = UDim2.fromOffset(0, 0)
			PanelKit.pill(
				header,
				Language.t(if bot.kind == "web" then "dev.kindWeb" else "dev.kindStudio"),
				colors.sendButton,
				3,
				z
			)
			statusPill(header, bot, 4, colors)
			local stats = Bots.statsOf(bot.id)
			PanelKit.text(
				box,
				Language.t("dev.summary", { commands = #bot.commands, uses = stats.total, errors = stats.errors }),
				"muted",
				2,
				z,
				colors
			)
			PanelKit.button(box, Language.t("dev.manage"), "primary", 3, z, colors, function()
				openBot = bot.id
				page = "overview"
				status = ""
				render()
			end).Name =
				"Manage"
		end
	end

	local function newSection(colors, nextOrder: () -> number)
		local form = PanelKit.box(card, nextOrder(), z, colors)
		form.Name = "NewBot"
		local kinds = PanelKit.row(form, 1, z)
		PanelKit.button(
			kinds,
			Language.t("dev.kindStudio"),
			if newKind == "studio" then "primary" else "secondary",
			1,
			z,
			colors,
			function()
				newKind = "studio"
				render()
			end
		).Name =
			"KindStudio"
		PanelKit.button(
			kinds,
			Language.t("dev.kindWeb"),
			if newKind == "web" then "primary" else "secondary",
			2,
			z,
			colors,
			function()
				newKind = "web"
				render()
			end
		).Name =
			"KindWeb"
		PanelKit.text(
			form,
			Language.t(if newKind == "web" then "dev.webHint" else "dev.studioHint"),
			"muted",
			2,
			z,
			colors
		)
		local name = PanelKit.input(form, "", Language.t("dev.namePlaceholder"), 3, z, colors)
		name.Name = "NameInput"
		local url: TextBox? = nil
		if newKind == "web" then
			url = PanelKit.input(form, "", "https://example.com/teamchat", 4, z, colors);
			(url :: TextBox).Name = "UrlInput"
		end
		PanelKit.button(form, Language.t("dev.create"), "primary", 5, z, colors, function()
			local botName = string.match(name.Text, "^%s*(.-)%s*$") or ""
			if not string.match(botName, "^[%w_]+$") then
				setStatus(Language.t("dev.badName"))
				return
			end
			if newKind == "web" then
				local id, problem = Bots.createWeb(botName, if url then url.Text else "")
				if id then
					section = "bots"
					openBot = id
					page = "overview"
					setStatus(Language.t("dev.createdWeb", { name = botName }))
				else
					setStatus(Language.t("dev." .. tostring(problem)))
				end
			else
				local module, problem = Bots.create(botName)
				if module and params.openScript then
					params.openScript(module)
				end
				if module then
					section = "bots"
				end
				setStatus(
					if module
						then Language.t("bot.created", { name = botName })
						else Language.t(
							if problem == "exists" then "bot.exists" else "bot.signedOut",
							{ name = botName }
						)
				)
			end
		end).Name =
			"CreateButton"
	end

	local function docsSection(colors, nextOrder: () -> number)
		PanelKit.text(card, Language.t("dev.docs.quickStart"), "heading", nextOrder(), z, colors)
		PanelKit.text(card, Language.t("dev.docs.studioSteps"), "body", nextOrder(), z, colors)
		PanelKit.codeBox(card, STUDIO_EXAMPLE, nextOrder(), z, colors).Name = "StudioExample"
		PanelKit.text(card, Language.t("dev.docs.webSteps"), "body", nextOrder(), z, colors)
		PanelKit.text(card, Language.t("dev.docs.requests"), "heading", nextOrder(), z, colors)
		PanelKit.codeBox(card, REQUEST_EXAMPLE, nextOrder(), z, colors).Name = "Requests"
		PanelKit.text(card, Language.t("dev.docs.answers"), "heading", nextOrder(), z, colors)
		PanelKit.codeBox(card, ANSWER_EXAMPLE, nextOrder(), z, colors).Name = "Answers"
		PanelKit.text(card, Language.t("dev.docs.starters"), "heading", nextOrder(), z, colors)
		PanelKit.text(card, Language.t("dev.docs.copyHint"), "muted", nextOrder(), z, colors)
		PanelKit.text(card, "<b>Node.js</b>", "body", nextOrder(), z, colors)
		PanelKit.codeBox(card, NODE_STARTER, nextOrder(), z, colors).Name = "NodeStarter"
		PanelKit.text(card, "<b>Python</b>", "body", nextOrder(), z, colors)
		PanelKit.codeBox(card, PYTHON_STARTER, nextOrder(), z, colors).Name = "PythonStarter"
		PanelKit.text(card, Language.t("dev.docs.security"), "muted", nextOrder(), z, colors)
		PanelKit.button(card, Language.t("dev.docs.full"), "secondary", nextOrder(), z, colors, function()
			if not Browser.open(DOCS_URL) then
				setStatus(Language.t("links.copied", { url = DOCS_URL }))
			end
		end).Name =
			"FullDocs"
	end

	render = function()
		local colors = params.getThemeColors()
		PanelKit.clear(card, keep)
		local order = 2
		local function nextOrder(): number
			order += 1
			return order
		end
		local tabs = {}
		for _, key in ipairs(SECTIONS) do
			table.insert(tabs, { key = key, label = Language.t("dev.section." .. key) })
		end
		PanelKit.tabs(card, tabs, section, nextOrder(), z, colors, function(key)
			section = key
			openBot = nil
			confirming = nil
			status = ""
			render()
		end)
		if status ~= "" then
			PanelKit.text(card, status, "body", nextOrder(), z, colors).Name = "Status"
		end
		if section == "new" then
			newSection(colors, nextOrder)
		elseif section == "docs" then
			docsSection(colors, nextOrder)
		else
			local bot = if openBot then botById(openBot) else nil
			if bot then
				botPage(bot, colors, nextOrder)
			else
				openBot = nil
				botsSection(colors, nextOrder)
			end
		end
	end

	function self.open(sectionKey: string?)
		status = ""
		confirming = nil
		if sectionKey and table.find(SECTIONS, sectionKey) then
			section = sectionKey
		end
		render()
		card.CanvasPosition = Vector2.zero
		modal.open()
	end
	function self.close()
		modal.close()
	end
	function self.isVisible(): boolean
		return modal.isVisible()
	end
	function self.recolor()
		if modal.isVisible() then
			render()
		end
	end
	-- Shows one of your bots' pages (tests use it too)
	function self.openBot(id: string, pageKey: string?)
		section = "bots"
		openBot = id
		page = pageKey or "overview"
		render()
	end
	return self
end

return DeveloperDialog
