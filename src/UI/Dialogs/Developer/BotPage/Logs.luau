--!strict
--[[
	Logs

	A bot's Logs page: how often it's used, errors and response times, its
	most used commands and its recent interactions.
]]

local Language = require(script.Parent.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Parent.Shared)

local escape = Shared.escape
local when = Shared.when

local Logs = {}

function Logs.build(view: Shared.View, bot, colors, nextOrder: () -> number)
	local card, z = view.card, view.z
	local bots = view.services.bots

	local stats = bots.statsOf(bot.id)
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

	local entries = bots.logOf(bot.id)
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
		bots.clearLog(bot.id)
		view.setStatus(Language.t("dev.logCleared"))
	end).Name =
		"ClearLog"
end

return Logs
