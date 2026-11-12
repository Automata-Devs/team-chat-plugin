--!strict
--[[
	BotList

	The developer portal's first section: your bots, each with its status,
	command count and use, and a Manage button that opens its page.
]]

local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Shared)

local escape = Shared.escape

local BotList = {}

function BotList.build(view: Shared.View, colors, nextOrder: () -> number)
	local card, z, state = view.card, view.z, view.state
	local bots = view.services.bots
	local mine = bots.mine()
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
		Shared.statusPill(header, bot, 4, colors, z)
		local stats = bots.statsOf(bot.id)
		PanelKit.text(
			box,
			Language.t("dev.summary", { commands = #bot.commands, uses = stats.total, errors = stats.errors }),
			"muted",
			2,
			z,
			colors
		)
		PanelKit.button(box, Language.t("dev.manage"), "primary", 3, z, colors, function()
			state.openBot = bot.id
			state.page = "overview"
			state.status = ""
			view.render()
		end).Name =
			"Manage"
	end
end

return BotList
