--!strict
--[[
	Overview

	A bot's Overview page: status and a health check, its commands, the URL
	and token (web bots) or the script (Studio bots), turn off and delete.
]]

local Language = require(script.Parent.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Parent.Shared)

local escape = Shared.escape
local when = Shared.when

local MASKED = string.rep("\u{2022}", 12)

local Overview = {}

function Overview.build(view: Shared.View, bot, colors, nextOrder: () -> number)
	local card, z, state = view.card, view.z, view.state
	local bots = view.services.bots

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
		Language.t(if state.running then "dev.checking" else "dev.check"),
		"secondary",
		3,
		z,
		colors,
		function()
			if state.running then
				return
			end
			state.running = true
			view.render()
			task.spawn(function()
				local result = bots.checkHealth(bot.id)
				state.running = false
				view.setStatus(if result.ok
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
			view.setStatus(Language.t(if bots.updateWeb(bot.id, { url = url.Text }) then "dev.saved" else "dev.badUrl"))
		end)
		PanelKit.text(card, Language.t("dev.token"), "heading", nextOrder(), z, colors)
		local tokenRow = PanelKit.row(card, nextOrder(), z)
		local token = bots.tokenOf(bot.id) or ""
		PanelKit.input(
			tokenRow,
			if state.shownTokens[bot.id] then token else MASKED .. string.sub(token, -4),
			"",
			1,
			z,
			colors,
			{ width = UDim.new(1, -150), readOnly = true, mono = true }
		).Name =
			"Token"
		PanelKit.button(
			tokenRow,
			Language.t(if state.shownTokens[bot.id] then "dev.hide" else "dev.show"),
			"secondary",
			2,
			z,
			colors,
			function()
				state.shownTokens[bot.id] = not state.shownTokens[bot.id]
				view.render()
			end
		)
		PanelKit.button(tokenRow, Language.t("dev.newToken"), "secondary", 3, z, colors, function()
			bots.regenerateToken(bot.id)
			state.shownTokens[bot.id] = true
			view.setStatus(Language.t("dev.tokenChanged"))
		end)
		PanelKit.text(card, Language.t("dev.tokenHint"), "muted", nextOrder(), z, colors)
	end

	local actions = PanelKit.row(card, nextOrder(), z)
	actions.Name = "Actions"
	if bot.kind == "web" then
		PanelKit.button(actions, Language.t("dev.sync"), "primary", 1, z, colors, function()
			view.setStatus(Language.t("dev.syncing"))
			task.spawn(function()
				local count, problem = bots.syncWeb(bot.id)
				view.setStatus(
					if count
						then Language.t("dev.synced", { count = count })
						else Language.t("dev.syncFailed", { error = tostring(problem) })
				)
			end)
		end)
	else
		PanelKit.button(actions, Language.t("dev.openScript"), "primary", 1, z, colors, function()
			local module = bots.scriptOf(bot.id)
			if module and view.openScript then
				view.openScript(module)
			end
		end)
		PanelKit.button(actions, Language.t("dev.reload"), "secondary", 2, z, colors, function()
			local names = bots.reload()
			view.setStatus(Language.t("bot.reloaded", { names = table.concat(names, ", ") }))
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
			bots.setDisabled(bot.id, not bot.disabled)
			view.render()
		end
	)
	local deleteKey = "delete" .. bot.id
	PanelKit.button(
		actions,
		Language.t(if state.confirming == deleteKey then "dev.confirmDelete" else "dev.delete"),
		"danger",
		4,
		z,
		colors,
		function()
			if state.confirming ~= deleteKey then
				state.confirming = deleteKey
				view.render()
				return
			end
			bots.remove(bot.id)
			state.openBot = nil
			view.setStatus(Language.t("bot.removed", { name = bot.name }))
		end
	).Name =
		"Delete"
end

return Overview
