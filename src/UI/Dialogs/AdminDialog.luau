--!strict
--[[
	AdminDialog

	The admin dashboard (Settings > Admin), for moderators and up: an
	overview of the chat, its settings (slowmode, whitelist mode), the
	members with their ranks and moderation actions, the moderation lists,
	the place's bots and chat backups. Everything here does what the
	moderation commands do (/mute, /ban, /setrank, …), with the same rank
	rules: you can only act on people ranked below you.
]]

local Players = game:GetService("Players")

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Bots = require(script.Parent.Parent.Parent.Services.Bots)
local ChatNetwork = require(script.Parent.Parent.Parent.Services.Chat)
local Conversations = require(script.Parent.Parent.Parent.Services.Chat.Conversations)
local VersionHistory = require(script.Parent.Parent.Parent.Services.Chat.VersionHistory)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local PanelKit = require(script.Parent.PanelKit)

local Z = 32
local SLOWMODE_PRESETS = { 0, 5, 10, 30, 60 }
local MAX_BACKUPS_SHOWN = 5

local AdminDialog = {}

local function rankName(rank: number): string
	return Language.tOr("rank." .. rank, AdminNetwork.getRankName(rank))
end

--!
-- kit: a ModalKit. params: { getThemeColors }
-- Returns { open(), close(), isVisible(), recolor(), modal }
--!
function AdminDialog.create(kit, params)
	local modal = kit.createModal({ name = "AdminDialog", title = "Admin", iconKey = "settings", zIndex = Z })
	local card = modal.card
	local z = modal.contentZIndex
	local keep = {}
	for _, child in ipairs(card:GetChildren()) do
		keep[child] = true
	end

	local status = ""
	local confirmRestore: string? = nil -- a backup id: click Restore again to confirm
	local self = { modal = modal }
	local render: () -> ()

	local function act(text: string)
		status = text
		render()
	end

	local function reason(): string
		return Language.t("admin.reason")
	end

	-- Everyone worth listing: here now, and anyone with a rank
	local function members(): { { userId: number, name: string, online: boolean, rank: number } }
		local byId = {}
		for _, player in ipairs(Players:GetPlayers()) do
			byId[player.UserId] = { userId = player.UserId, name = player.Name, online = true }
		end
		for _, ranked in ipairs(AdminNetwork.getRankedUsers()) do
			byId[ranked.userId] = byId[ranked.userId]
				or { userId = ranked.userId, name = AdminNetwork.getUsernameByUserId(ranked.userId), online = false }
		end
		local list = {}
		for userId, member in pairs(byId) do
			member.rank = AdminNetwork.getRank(userId)
			table.insert(list, member)
		end
		table.sort(list, function(a, b)
			if a.rank ~= b.rank then
				return a.rank > b.rank
			end
			return string.lower(a.name) < string.lower(b.name)
		end)
		return list
	end

	local function memberRow(parent: Instance, member, order: number, colors, myRank: number)
		local row = PanelKit.row(parent, order, z)
		row.Name = "Member_" .. member.userId
		PanelKit.avatar(row, member.userId, 26, 1, z, colors)
		local label = PanelKit.text(row, "<b>" .. member.name .. "</b>", "body", 2, z, colors)
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = UDim2.fromOffset(0, 0)
		PanelKit.pill(row, rankName(member.rank), if member.rank > 0 then colors.sendButton else colors.timestamp, 3, z)
		if member.online then
			PanelKit.pill(row, Language.t("sidebar.online"), colors.success, 4, z)
		end
		if AdminNetwork.isMuted(member.userId) then
			PanelKit.pill(row, Language.t("admin.muted"), colors.warning, 5, z)
		end
		-- Actions only on people ranked below you (not yourself)
		if member.userId == Identity.userId or member.rank >= myRank then
			return
		end
		local actions = PanelKit.row(parent, order + 0.5, z)
		actions.Name = "Actions_" .. member.userId
		local n = 0
		local function button(key: string, style: string, fn: () -> ())
			n += 1
			PanelKit.button(actions, Language.t(key), style, n, z, colors, fn).Name = key
		end
		if member.rank + 1 < myRank then
			button("admin.promote", "secondary", function()
				AdminNetwork.setRank(member.userId, member.rank + 1)
				act(Language.t("admin.rankSet", { user = member.name, rank = rankName(member.rank + 1) }))
			end)
		end
		if member.rank > 0 then
			button("admin.demote", "secondary", function()
				AdminNetwork.setRank(member.userId, member.rank - 1)
				act(Language.t("admin.rankSet", { user = member.name, rank = rankName(member.rank - 1) }))
			end)
		end
		button("admin.warn", "secondary", function()
			AdminNetwork.warn(member.userId, Identity.userId, reason(), Identity.username)
			act(Language.t("embed.mod.warn", { user = member.name }))
		end)
		if AdminNetwork.isMuted(member.userId) then
			button("admin.unmute", "secondary", function()
				AdminNetwork.unmute(member.userId)
				act(Language.t("embed.mod.unmute", { user = member.name }))
			end)
		else
			button("admin.mute", "secondary", function()
				AdminNetwork.mute(member.userId, member.name, reason())
				act(Language.t("embed.mod.mute", { user = member.name }))
			end)
		end
		button("admin.kick", "danger", function()
			AdminNetwork.kick(member.userId, member.name, reason())
			act(Language.t("embed.mod.kick", { user = member.name }))
		end)
		if myRank >= 2 then
			button("admin.ban", "danger", function()
				AdminNetwork.ban(member.userId, member.name, reason())
				act(Language.t("embed.mod.ban", { user = member.name }))
			end)
		end
	end

	-- One moderation list (banned, muted, …) with a remove button per person
	local function listBox(
		titleKey: string,
		entries: { table },
		removeKey: string,
		remove: (number) -> (),
		order: number,
		colors
	)
		PanelKit.text(card, Language.t(titleKey, { count = #entries }), "heading", order, z, colors)
		local box = PanelKit.box(card, order + 0.5, z, colors)
		box.Name = titleKey
		if #entries == 0 then
			PanelKit.text(box, Language.t("admin.nobody"), "muted", 1, z, colors)
			return
		end
		for index, entry in ipairs(entries) do
			local row = PanelKit.row(box, index, z)
			local label = PanelKit.text(
				row,
				"<b>"
					.. tostring(entry.username or entry.userId)
					.. "</b>"
					.. (if entry.reason then "  \u{00B7}  " .. tostring(entry.reason) else ""),
				"body",
				1,
				z,
				colors
			)
			label.Size = UDim2.new(1, -110, 0, 0)
			PanelKit.button(row, Language.t(removeKey), "secondary", 2, z, colors, function()
				remove(entry.userId)
				act(Language.t("admin.updated"))
			end)
		end
	end

	render = function()
		local colors = params.getThemeColors()
		PanelKit.clear(card, keep)
		local myRank = AdminNetwork.getMyRank()
		local order = 2
		local function nextOrder(): number
			order += 1
			return order
		end
		if myRank < 1 then
			PanelKit.text(card, Language.t("admin.noAccess"), "muted", nextOrder(), z, colors).Name = "NoAccess"
			return
		end
		if status ~= "" then
			PanelKit.text(card, status, "body", nextOrder(), z, colors).Name = "Status"
		end

		-- Overview
		PanelKit.text(card, Language.t("admin.overview"), "heading", nextOrder(), z, colors)
		local tiles = PanelKit.row(card, nextOrder(), z)
		tiles.Name = "Overview"
		local bots = Bots.list()
		local onlineBots = 0
		for _, bot in ipairs(bots) do
			onlineBots += if bot.online then 1 else 0
		end
		local dms = 0
		for _, entry in ipairs(Conversations.list()) do
			dms += if entry.kind == "dm" then 1 else 0
		end
		local slowmode = AdminNetwork.getSlowmode()
		local stats = {
			{ "admin.statOnline", #Players:GetPlayers() },
			{ "admin.statMessages", #ChatNetwork.getFolder():GetChildren() },
			{ "admin.statDms", dms },
			{ "admin.statBots", string.format("%d/%d", onlineBots, #bots) },
			{ "admin.statSlowmode", if slowmode > 0 then slowmode .. "s" else Language.t("option.off") },
			{ "admin.statRank", rankName(myRank) },
		}
		for index, stat in ipairs(stats) do
			PanelKit.tile(tiles, Language.t(stat[1]), tostring(stat[2]), index, z, colors).Name = stat[1]
		end

		-- Chat settings
		PanelKit.text(card, Language.t("admin.settings"), "heading", nextOrder(), z, colors)
		local settings = PanelKit.box(card, nextOrder(), z, colors)
		PanelKit.text(settings, Language.t("admin.slowmode"), "body", 1, z, colors)
		local presets = PanelKit.row(settings, 2, z)
		presets.Name = "Slowmode"
		for index, seconds in ipairs(SLOWMODE_PRESETS) do
			PanelKit.button(
				presets,
				if seconds == 0 then Language.t("option.off") else seconds .. "s",
				if slowmode == seconds then "primary" else "secondary",
				index,
				z,
				colors,
				function()
					AdminNetwork.setSlowmode(seconds)
					act(
						if seconds == 0
							then Language.t("reply.slowmode.off")
							else Language.t("reply.slowmode.set", { seconds = seconds })
					)
				end
			).Name = "Slowmode_"
				.. seconds
		end
		local whitelistOn = AdminNetwork.isWhitelistEnabled()
		PanelKit.text(settings, Language.t("admin.whitelistMode"), "body", 3, z, colors)
		local whitelistRow = PanelKit.row(settings, 4, z)
		PanelKit.button(
			whitelistRow,
			Language.t(if whitelistOn then "admin.whitelistOff" else "admin.whitelistOn"),
			if whitelistOn then "danger" else "secondary",
			1,
			z,
			colors,
			function()
				AdminNetwork.toggleWhitelist()
				act(Language.t(if whitelistOn then "reply.whitelist.off" else "reply.whitelist.on"))
			end
		).Name =
			"ToggleWhitelist"

		-- Members
		local people = members()
		PanelKit.text(card, Language.t("admin.members", { count = #people }), "heading", nextOrder(), z, colors)
		local memberBox = PanelKit.box(card, nextOrder(), z, colors)
		memberBox.Name = "Members"
		for index, member in ipairs(people) do
			memberRow(memberBox, member, index * 2, colors, myRank)
		end

		-- Moderation lists
		listBox("admin.banned", AdminNetwork.getBannedUsers(), "admin.unban", AdminNetwork.unban, nextOrder(), colors)
		listBox(
			"admin.mutedList",
			AdminNetwork.getMutedUsers(),
			"admin.unmute",
			AdminNetwork.unmute,
			nextOrder(),
			colors
		)
		listBox(
			"admin.blacklist",
			AdminNetwork.getBlacklistedUsers(),
			"admin.remove",
			AdminNetwork.unblacklist,
			nextOrder(),
			colors
		)
		listBox(
			"admin.whitelist",
			AdminNetwork.getWhitelistedUsers(),
			"admin.remove",
			AdminNetwork.unwhitelist,
			nextOrder(),
			colors
		)

		-- Bots
		PanelKit.text(card, Language.t("admin.bots", { count = #bots }), "heading", nextOrder(), z, colors)
		local botBox = PanelKit.box(card, nextOrder(), z, colors)
		botBox.Name = "Bots"
		if #bots == 0 then
			PanelKit.text(botBox, Language.t("bot.none"), "muted", 1, z, colors)
		end
		for index, bot in ipairs(bots) do
			local row = PanelKit.row(botBox, index, z)
			local label = PanelKit.text(row, "<b>" .. bot.name .. "</b>  \u{00B7}  " .. Language.t("bot.listEntry", {
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
						Bots.setDisabled(bot.id, not bot.disabled)
						act(Language.t("admin.updated"))
					end
				)
			end
		end

		-- Chat backups
		local backups = VersionHistory.list()
		PanelKit.text(card, Language.t("admin.backups", { count = #backups }), "heading", nextOrder(), z, colors)
		local backupBox = PanelKit.box(card, nextOrder(), z, colors)
		backupBox.Name = "Backups"
		PanelKit.button(backupBox, Language.t("admin.backupNow"), "primary", 0, z, colors, function()
			local version = VersionHistory.create(Language.t("admin.backupLabel"))
			act(if version then Language.t("embed.backup.title") else Language.t("reply.backup.notReady"))
		end).Name =
			"BackupNow"
		for index, version in ipairs(backups) do
			if index > MAX_BACKUPS_SHOWN then
				break
			end
			local row = PanelKit.row(backupBox, index, z)
			local label = PanelKit.text(
				row,
				os.date("%d/%m %H:%M", version.timestamp or os.time())
					.. (if version.label ~= "" then "  \u{00B7}  " .. version.label else "")
					.. "  \u{00B7}  "
					.. Language.t("embed.restore.value", {
						count = version.messageCount,
						author = version.author or Language.t("reply.unknownAuthor"),
					}),
				"body",
				1,
				z,
				colors
			)
			label.Size = UDim2.new(1, -110, 0, 0)
			if myRank >= 2 then
				local confirming = confirmRestore == version.id
				PanelKit.button(
					row,
					Language.t(if confirming then "admin.confirmRestore" else "admin.restore"),
					if confirming then "danger" else "secondary",
					2,
					z,
					colors,
					function()
						if not confirming then
							confirmRestore = version.id
							render()
							return
						end
						confirmRestore = nil
						VersionHistory.create("auto-before-restore")
						act(
							Language.t(
								if VersionHistory.restore(version.id)
									then "reply.restore.done"
									else "reply.restore.failed"
							)
						)
					end
				)
			end
		end
	end

	-- Moderation changes made elsewhere (commands, other admins) show here too
	Lifetime.add(AdminNetwork.onAdminEvent(function()
		if modal.isVisible() then
			task.defer(render)
		end
	end))

	function self.open()
		status = ""
		confirmRestore = nil
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
	return self
end

return AdminDialog
