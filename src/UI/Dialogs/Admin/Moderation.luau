--!strict
--[[
	Moderation

	The admin dashboard's Moderation section: slowmode and whitelist mode,
	the banned, muted, blacklisted and whitelisted people, and the place's
	bots (admins can turn them off).
]]

local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Shared)

local escape = Shared.escape
local when = Shared.when

local SLOWMODE_PRESETS = { 0, 5, 10, 30, 60 }

local Moderation = {}

-- One list (banned, muted, ...) with a remove button per person
local function listBox(
	view: Shared.View,
	titleKey: string,
	entries: { any },
	removeKey: string,
	remove: (number) -> (),
	colors,
	nextOrder: () -> number
)
	local card, z = view.card, view.z
	PanelKit.text(card, Language.t(titleKey, { count = #entries }), "heading", nextOrder(), z, colors)
	local box = PanelKit.box(card, nextOrder(), z, colors)
	box.Name = titleKey
	if #entries == 0 then
		PanelKit.text(box, Language.t("admin.nobody"), "muted", 1, z, colors)
		return
	end
	for index, entry in ipairs(entries) do
		local row = PanelKit.row(box, index, z)
		local detail = if entry.expiry
			then "  \u{00B7}  " .. Language.t("admin.until", { time = when(entry.expiry) })
			else ""
		local label = PanelKit.text(
			row,
			"<b>"
				.. escape(tostring(entry.username or entry.userId))
				.. "</b>"
				.. (if entry.reason then "  \u{00B7}  " .. escape(tostring(entry.reason)) else "")
				.. detail,
			"body",
			1,
			z,
			colors
		)
		label.Size = UDim2.new(1, -110, 0, 0)
		PanelKit.button(row, Language.t(removeKey), "secondary", 2, z, colors, function()
			remove(entry.userId)
			view.act(Language.t("admin.updated"))
		end)
	end
end

function Moderation.build(view: Shared.View, colors, nextOrder: () -> number, myRank: number)
	local card, z = view.card, view.z
	local admin = view.services.admin
	local act = view.act

	PanelKit.text(card, Language.t("admin.settings"), "heading", nextOrder(), z, colors)
	local settings = PanelKit.box(card, nextOrder(), z, colors)
	local slowmode = admin.getSlowmode()
	PanelKit.text(settings, Language.t("admin.slowmode"), "body", 1, z, colors)
	local presets = PanelKit.row(settings, 2, z)
	presets.Name = "Slowmode"
	for index, seconds in ipairs(SLOWMODE_PRESETS) do
		PanelKit.button(
			presets,
			if seconds == 0 then Language.t("option.off") else seconds .. "s",
			if slowmode == seconds then "selected" else "choice",
			index,
			z,
			colors,
			function()
				admin.setSlowmode(seconds)
				act(
					if seconds == 0
						then Language.t("reply.slowmode.off")
						else Language.t("reply.slowmode.set", { seconds = seconds })
				)
			end
		).Name = "Slowmode_"
			.. seconds
	end
	local whitelistOn = admin.isWhitelistEnabled()
	PanelKit.text(settings, Language.t("admin.whitelistMode"), "body", 3, z, colors)
	PanelKit.button(
		settings,
		Language.t(if whitelistOn then "admin.whitelistOff" else "admin.whitelistOn"),
		if whitelistOn then "danger" else "secondary",
		4,
		z,
		colors,
		function()
			admin.toggleWhitelist()
			act(Language.t(if whitelistOn then "reply.whitelist.off" else "reply.whitelist.on"))
		end
	).Name =
		"ToggleWhitelist"

	listBox(view, "admin.banned", admin.getBannedUsers(), "admin.unban", admin.unban, colors, nextOrder)
	listBox(view, "admin.mutedList", admin.getMutedUsers(), "admin.unmute", admin.unmute, colors, nextOrder)
	listBox(view, "admin.blacklist", admin.getBlacklistedUsers(), "admin.remove", admin.unblacklist, colors, nextOrder)
	listBox(view, "admin.whitelist", admin.getWhitelistedUsers(), "admin.remove", admin.unwhitelist, colors, nextOrder)

	local bots = view.services.bots.list()
	PanelKit.text(card, Language.t("admin.bots", { count = #bots }), "heading", nextOrder(), z, colors)
	local botBox = PanelKit.box(card, nextOrder(), z, colors)
	botBox.Name = "Bots"
	if #bots == 0 then
		PanelKit.text(botBox, Language.t("bot.none"), "muted", 1, z, colors)
	end
	for index, bot in ipairs(bots) do
		local row = PanelKit.row(botBox, index, z)
		local label =
			PanelKit.text(row, "<b>" .. escape(bot.name) .. "</b>  \u{00B7}  " .. Language.t("bot.listEntry", {
				owner = bot.ownerName,
				commands = tostring(#bot.commands),
			}), "body", 1, z, colors)
		label.Size = UDim2.new(1, -190, 0, 0)
		PanelKit.pill(
			row,
			Language.t(if bot.disabled then "dev.disabled" elseif bot.online then "dev.online" else "dev.offline"),
			if bot.disabled then colors.danger elseif bot.online then colors.success else colors.timestamp,
			2,
			z
		)
		if myRank >= 2 then
			PanelKit.button(
				row,
				Language.t(if bot.disabled then "dev.turnOn" else "dev.turnOff"),
				"secondary",
				3,
				z,
				colors,
				function()
					view.services.bots.setDisabled(bot.id, not bot.disabled)
					act(Language.t("admin.updated"))
				end
			)
		end
	end
end

return Moderation
