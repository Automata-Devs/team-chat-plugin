--!strict
--[[
	Console

	A bot's Console page: run its commands and click its buttons without
	posting in the chat (Services/Bots.test), and see exactly what it answers.
]]

local Browser = require(script.Parent.Parent.Parent.Parent.Parent.Core.Browser)
local Language = require(script.Parent.Parent.Parent.Parent.Parent.Core.Language)
local Markdown = require(script.Parent.Parent.Parent.Parent.Parent.Util.Markdown)
local PanelKit = require(script.Parent.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Parent.Shared)

local escape = Shared.escape
local when = Shared.when

local KEEP = 10 -- results kept per bot

local Console = {}

-- One answer: its text, card and buttons (the buttons run too)
local function consoleMessage(
	view: Shared.View,
	parent: Instance,
	message,
	order: number,
	colors,
	run: (input: any) -> ()
)
	local z = view.z
	local bots = view.services.bots
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
	for rowIndex, buttons in ipairs(bots.cleanComponents(message.components) or {}) do
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

function Console.build(view: Shared.View, bot, colors, nextOrder: () -> number)
	local card, z, state = view.card, view.z, view.state
	local bots = view.services.bots

	local results = state.consoles[bot.id] or {}
	state.consoles[bot.id] = results
	PanelKit.text(card, Language.t("dev.consoleHint"), "muted", nextOrder(), z, colors)
	local function run(input)
		if state.running then
			return
		end
		state.running = true
		view.render()
		task.spawn(function()
			local result = bots.test(bot.id, input)
			state.running = false
			table.insert(results, 1, { input = input, result = result, time = os.time() })
			while #results > KEEP do
				table.remove(results)
			end
			state.status = ""
			view.render()
		end)
	end
	view.dialog.runTest = run -- for tests
	local inputRow = PanelKit.row(card, nextOrder(), z)
	inputRow.Name = "ConsoleInput"
	local field = PanelKit.input(
		inputRow,
		state.consoleInput[bot.id] or "",
		"/command options",
		1,
		z,
		colors,
		{ width = UDim.new(1, -80), mono = true }
	)
	field.Name = "Command"
	field.FocusLost:Connect(function()
		state.consoleInput[bot.id] = field.Text
	end)
	PanelKit.button(
		inputRow,
		Language.t(if state.running then "dev.running" else "dev.run"),
		"primary",
		2,
		z,
		colors,
		function()
			state.consoleInput[bot.id] = field.Text
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
			state.consoleInput[bot.id] = "/" .. command.name .. " "
			view.render()
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
			consoleMessage(view, card, message, nextOrder(), colors, run)
		end
	end
end

return Console
