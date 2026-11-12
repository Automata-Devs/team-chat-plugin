--!strict
--[[
	BotPage

	One of your bots in the developer portal: its header (avatar, name, kind,
	status) and its pages: Overview, Console, Logs and Edit.
]]

local Console = require(script.Console)
local Edit = require(script.Edit)
local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local Logs = require(script.Logs)
local Overview = require(script.Overview)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Shared)

local PAGES = { "overview", "console", "logs", "edit" }

local BotPage = {}

function BotPage.build(view: Shared.View, bot, colors, nextOrder: () -> number)
	local card, z, state = view.card, view.z, view.state
	PanelKit.button(card, Language.t("dev.back"), "secondary", nextOrder(), z, colors, function()
		state.openBot = nil
		view.render()
	end).Name =
		"Back"
	local header = PanelKit.row(card, nextOrder(), z)
	header.Name = "BotHeader"
	PanelKit.avatar(header, nil, 36, 1, z, colors).Image = bot.avatar or ""
	local title = PanelKit.text(header, "<b>" .. Shared.escape(bot.name) .. "</b>", "title", 2, z, colors)
	title.AutomaticSize = Enum.AutomaticSize.XY
	title.Size = UDim2.fromOffset(0, 0)
	PanelKit.pill(
		header,
		Language.t(if bot.kind == "web" then "dev.kindWeb" else "dev.kindStudio"),
		colors.sendButton,
		3,
		z
	)
	Shared.statusPill(header, bot, 4, colors, z)
	if bot.description ~= "" then
		PanelKit.text(card, Shared.escape(bot.description), "muted", nextOrder(), z, colors)
	end
	local tabs = {}
	for _, key in ipairs(PAGES) do
		table.insert(tabs, { key = key, label = Language.t("dev.page." .. key) })
	end
	PanelKit.tabs(card, tabs, state.page, nextOrder(), z, colors, function(key)
		state.page = key
		state.confirming = nil
		view.render()
	end).Name =
		"Pages"
	if state.page == "console" then
		Console.build(view, bot, colors, nextOrder)
	elseif state.page == "logs" then
		Logs.build(view, bot, colors, nextOrder)
	elseif state.page == "edit" then
		Edit.build(view, bot, colors, nextOrder)
	else
		Overview.build(view, bot, colors, nextOrder)
	end
end

return BotPage
