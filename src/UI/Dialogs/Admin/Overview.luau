--!strict
--[[
	Overview

	The admin dashboard's first section: the chat's numbers, messages per
	day and per hour, and the most active people over 7 or 30 days.
]]

local Players = game:GetService("Players")

local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Shared)

local escape = Shared.escape
local when = Shared.when

local Overview = {}

function Overview.build(view: Shared.View, colors, nextOrder: () -> number)
	local card, z, state = view.card, view.z, view.state
	local admin = view.services.admin
	local stats = view.services.chat.Stats.collect(state.period)
	local bots = view.services.bots.list()
	local onlineBots = 0
	for _, bot in ipairs(bots) do
		onlineBots += if bot.online then 1 else 0
	end
	local slowmode = admin.getSlowmode()
	local tiles = PanelKit.row(card, nextOrder(), z)
	tiles.Name = "Overview"
	local values = {
		{ "admin.statOnline", #Players:GetPlayers() },
		{ "admin.statMessages", stats.total },
		{ "admin.statRecent", stats.recent },
		{ "admin.statDms", stats.dmConversations },
		{ "admin.statBots", string.format("%d/%d", onlineBots, #bots) },
		{ "admin.statSlowmode", if slowmode > 0 then slowmode .. "s" else Language.t("option.off") },
		{ "admin.statRank", view.rankName(admin.getMyRank()) },
	}
	for index, stat in ipairs(values) do
		PanelKit.tile(tiles, Language.t(stat[1], { days = state.period }), tostring(stat[2]), index, z, colors).Name =
			stat[1]
	end

	local periods = PanelKit.row(card, nextOrder(), z)
	for index, days in ipairs({ 7, 30 }) do
		PanelKit.button(
			periods,
			Language.t("admin.lastDays", { days = days }),
			if state.period == days then "selected" else "choice",
			index,
			z,
			colors,
			function()
				state.period = days
				view.render()
			end
		).Name = "Period_"
			.. days
	end

	PanelKit.text(card, Language.t("admin.perDay"), "heading", nextOrder(), z, colors)
	local dayValues, dayLabels = {}, {}
	for index, day in ipairs(stats.perDay) do
		table.insert(dayValues, day.count)
		local every = if state.period > 10 then 5 else 1
		table.insert(dayLabels, if (#stats.perDay - index) % every == 0 then day.label else "")
	end
	PanelKit.barChart(card, dayValues, dayLabels, nextOrder(), z, colors).Name = "PerDay"

	PanelKit.text(card, Language.t("admin.byHour"), "heading", nextOrder(), z, colors)
	local hourLabels = {}
	for hour = 0, 23 do
		table.insert(hourLabels, if hour % 3 == 0 then string.format("%02d", hour) else "")
	end
	PanelKit.barChart(card, stats.byHour, hourLabels, nextOrder(), z, colors, { height = 70 }).Name = "ByHour"

	PanelKit.text(card, Language.t("admin.mostActive"), "heading", nextOrder(), z, colors)
	if #stats.top == 0 then
		PanelKit.text(card, Language.t("admin.noMessages"), "muted", nextOrder(), z, colors)
	else
		local items = {}
		for _, person in ipairs(stats.top) do
			table.insert(items, { label = escape(person.name), value = person.count, detail = when(person.last) })
		end
		PanelKit.bars(card, items, nextOrder(), z, colors).Name = "MostActive"
	end

	local more = PanelKit.row(card, nextOrder(), z)
	more.Name = "Counts"
	for index, stat in ipairs({
		{ "admin.statDmMessages", stats.dmMessages },
		{ "admin.statBotMessages", stats.botMessages },
		{ "admin.statFiles", stats.files },
		{ "admin.statPolls", stats.polls },
	}) do
		PanelKit.tile(more, Language.t(stat[1]), tostring(stat[2]), index, z, colors)
	end
end

return Overview
