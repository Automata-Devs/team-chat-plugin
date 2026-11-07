--!strict
--[[
	AdminDialog

	The admin dashboard (Settings > Admin), for moderators and up, in
	sections:
	  - Overview: the chat's numbers, messages per day and per hour, and the
	    most active people (7 or 30 days, Services/Chat/Stats).
	  - Members: everyone here, ranked or who wrote, with a search; a
	    person's details (rank, messages, warnings, mute timer) and every
	    action, with a reason and a mute length.
	  - Moderation: banned, muted, blacklisted and whitelisted people,
	    slowmode, whitelist mode and the place's bots.
	  - Audit log: every moderation action (Admin/AuditLog), searchable.
	  - Chat tools: blocked words, purging, exporting the chat, automatic
	    backups and backups.
	Everything follows the moderation commands' rank rules: you can only act
	on people ranked below you.
]]

local Players = game:GetService("Players")

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Bots = require(script.Parent.Parent.Parent.Services.Bots)
local ChatNetwork = require(script.Parent.Parent.Parent.Services.Chat)
local Stats = require(script.Parent.Parent.Parent.Services.Chat.Stats)
local VersionHistory = require(script.Parent.Parent.Parent.Services.Chat.VersionHistory)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local PanelKit = require(script.Parent.PanelKit)

local Z = 32
local SLOWMODE_PRESETS = { 0, 5, 10, 30, 60 }
local MUTE_LENGTHS = { { key = "m5", seconds = 300 }, { key = "h1", seconds = 3600 }, { key = "d1", seconds = 86400 } }
local AUTO_BACKUP_HOURS = { 0, 1, 6, 24 }
local PURGE_AMOUNTS = { 10, 25, 50 }
local MAX_BACKUPS_SHOWN = 8
local AUDIT_PAGE = 40

local SECTIONS = { "overview", "members", "moderation", "audit", "tools" }

local AdminDialog = {}

local function rankName(rank: number): string
	return Language.tOr("rank." .. rank, AdminNetwork.getRankName(rank))
end

local function when(time: number?): string
	return if time and time > 0 then os.date("%d/%m %H:%M", time) else "-"
end

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

--!
-- kit: a ModalKit. params: { getThemeColors, openScript: ((LuaSourceContainer) -> ())? }
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

	-- What the dashboard shows (kept while it's open)
	local section = "overview"
	local period = 7
	local memberQuery = ""
	local selected: number? = nil -- a member's details
	local auditQuery = ""
	local auditAction: string? = nil
	local auditTarget: number? = nil
	local auditLimit = AUDIT_PAGE
	local confirming: string? = nil -- an action waiting for a second click
	local status = ""

	local self = { modal = modal }
	local render: () -> ()

	local function act(text: string)
		status = text
		confirming = nil
		render()
	end

	-- A second click confirms: returns true when this is it
	local function confirm(key: string): boolean
		if confirming == key then
			confirming = nil
			return true
		end
		confirming = key
		render()
		return false
	end

	-- Names of ranked people who aren't here and never wrote (looked up once,
	-- in the background: drawing never waits on the web)
	local names: { [number]: string | false } = {}
	local refresh: () -> ()
	local function nameOf(userId: number): string
		local known = names[userId]
		if known then
			return known
		end
		if known == nil then
			names[userId] = false
			task.spawn(function()
				local name = Identity.nameOf(userId)
				if name then
					names[userId] = name
					refresh()
				end
			end)
		end
		return "User " .. userId
	end

	-- Everyone worth listing: here now, ranked, or who wrote in the chat
	local function members(stats: Stats.Summary)
		local byId = {}
		for _, player in ipairs(Players:GetPlayers()) do
			byId[player.UserId] = { userId = player.UserId, name = player.Name, online = true }
		end
		for _, ranked in ipairs(AdminNetwork.getRankedUsers()) do
			byId[ranked.userId] = byId[ranked.userId]
				or {
					userId = ranked.userId,
					name = if stats.users[ranked.userId]
						then stats.users[ranked.userId].name
						else nameOf(ranked.userId),
					online = false,
				}
		end
		for userId, person in pairs(stats.users) do
			byId[userId] = byId[userId] or { userId = userId, name = person.name, online = false }
		end
		local list = {}
		local query = string.lower(memberQuery)
		for userId, member in pairs(byId) do
			member.rank = AdminNetwork.getRank(userId)
			member.messages = if stats.users[userId] then stats.users[userId].count else 0
			member.last = if stats.users[userId] then stats.users[userId].last else nil
			if query == "" or string.find(string.lower(member.name), query, 1, true) or tostring(userId) == query then
				table.insert(list, member)
			end
		end
		table.sort(list, function(a, b)
			if a.online ~= b.online then
				return a.online
			end
			if a.rank ~= b.rank then
				return a.rank > b.rank
			end
			return string.lower(a.name) < string.lower(b.name)
		end)
		return list
	end

	local function muteOf(userId: number)
		for _, entry in ipairs(AdminNetwork.getMutedUsers()) do
			if entry.userId == userId then
				return entry
			end
		end
		return nil
	end

	---------------------------------------------------------------------------
	-- Sections
	---------------------------------------------------------------------------

	local function overview(colors, nextOrder: () -> number)
		local stats = Stats.collect(period)
		local bots = Bots.list()
		local onlineBots = 0
		for _, bot in ipairs(bots) do
			onlineBots += if bot.online then 1 else 0
		end
		local slowmode = AdminNetwork.getSlowmode()
		local tiles = PanelKit.row(card, nextOrder(), z)
		tiles.Name = "Overview"
		local values = {
			{ "admin.statOnline", #Players:GetPlayers() },
			{ "admin.statMessages", stats.total },
			{ "admin.statRecent", stats.recent },
			{ "admin.statDms", stats.dmConversations },
			{ "admin.statBots", string.format("%d/%d", onlineBots, #bots) },
			{ "admin.statSlowmode", if slowmode > 0 then slowmode .. "s" else Language.t("option.off") },
			{ "admin.statRank", rankName(AdminNetwork.getMyRank()) },
		}
		for index, stat in ipairs(values) do
			PanelKit.tile(tiles, Language.t(stat[1], { days = period }), tostring(stat[2]), index, z, colors).Name =
				stat[1]
		end

		-- The period
		local periods = PanelKit.row(card, nextOrder(), z)
		for index, days in ipairs({ 7, 30 }) do
			PanelKit.button(
				periods,
				Language.t("admin.lastDays", { days = days }),
				if period == days then "selected" else "choice",
				index,
				z,
				colors,
				function()
					period = days
					render()
				end
			).Name = "Period_"
				.. days
		end

		PanelKit.text(card, Language.t("admin.perDay"), "heading", nextOrder(), z, colors)
		local dayValues, dayLabels = {}, {}
		for index, day in ipairs(stats.perDay) do
			table.insert(dayValues, day.count)
			local every = if period > 10 then 5 else 1
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

	-- One person: their details and every action on them
	local function memberDetails(member, colors, nextOrder: () -> number, myRank: number)
		PanelKit.button(card, Language.t("admin.back"), "secondary", nextOrder(), z, colors, function()
			selected = nil
			render()
		end).Name =
			"Back"
		local box = PanelKit.box(card, nextOrder(), z, colors)
		box.Name = "MemberDetails"
		local head = PanelKit.row(box, 1, z)
		PanelKit.avatar(head, member.userId, 48, 1, z, colors)
		local title = PanelKit.text(
			head,
			string.format(
				'<b>%s</b>\n<font size="13" color="#%s">%s</font>',
				escape(member.name),
				colors.timestamp:ToHex(),
				Language.t("admin.userId", { id = member.userId })
			),
			"title",
			2,
			z,
			colors
		)
		title.AutomaticSize = Enum.AutomaticSize.XY
		title.Size = UDim2.fromOffset(0, 0)
		local pills = PanelKit.row(box, 2, z)
		PanelKit.pill(
			pills,
			rankName(member.rank),
			if member.rank > 0 then colors.sendButton else colors.timestamp,
			1,
			z
		)
		if member.online then
			PanelKit.pill(pills, Language.t("sidebar.online"), colors.success, 2, z)
		end
		local mute = muteOf(member.userId)
		if mute then
			PanelKit.pill(
				pills,
				if mute.expiry
					then Language.t("admin.mutedUntil", { time = when(mute.expiry) })
					else Language.t("admin.muted"),
				colors.warning,
				3,
				z
			)
		end
		if AdminNetwork.isBanned(member.userId) then
			PanelKit.pill(pills, Language.t("admin.isBanned"), colors.danger, 4, z)
		end
		if AdminNetwork.isBlacklisted(member.userId) then
			PanelKit.pill(pills, Language.t("admin.isBlacklisted"), colors.danger, 5, z)
		end
		if AdminNetwork.isWhitelisted(member.userId) then
			PanelKit.pill(pills, Language.t("admin.isWhitelisted"), colors.success, 6, z)
		end
		local warnings = AdminNetwork.getWarnings(member.userId)
		local facts = PanelKit.row(box, 3, z)
		PanelKit.tile(facts, Language.t("admin.statMessages"), tostring(member.messages), 1, z, colors)
		PanelKit.tile(facts, Language.t("admin.lastMessage"), when(member.last), 2, z, colors)
		PanelKit.tile(facts, Language.t("admin.warnings"), tostring(#warnings), 3, z, colors)

		-- Warnings
		if #warnings > 0 then
			PanelKit.text(box, Language.t("admin.warnings"), "heading", 4, z, colors)
			for index, warning in ipairs(warnings) do
				PanelKit.text(
					box,
					string.format(
						"%s  \u{00B7}  <b>%s</b>: %s",
						when(warning.timestamp),
						escape(tostring(warning.moderatorName or "?")),
						escape(tostring(warning.reason or ""))
					),
					"body",
					4 + index / 100,
					z,
					colors
				)
			end
		end

		PanelKit.button(box, Language.t("admin.viewInLog"), "secondary", 6, z, colors, function()
			section = "audit"
			auditTarget = member.userId
			auditLimit = AUDIT_PAGE
			render()
		end).Name =
			"ViewInLog"

		if member.userId == Identity.userId or member.rank >= myRank then
			PanelKit.text(box, Language.t("admin.cantAct"), "muted", 7, z, colors)
			return
		end

		-- Actions, with a reason
		PanelKit.text(box, Language.t("admin.actions"), "heading", 8, z, colors)
		local reasonBox = PanelKit.input(box, "", Language.t("admin.reasonPlaceholder"), 9, z, colors)
		reasonBox.Name = "Reason"
		local function reason(): string
			local text = string.match(reasonBox.Text, "^%s*(.-)%s*$") or ""
			return if text ~= "" then text else Language.t("admin.reason")
		end
		local actions = PanelKit.row(box, 10, z)
		actions.Name = "Actions"
		local n = 0
		local function button(key: string, style: string, fn: () -> (), label: string?)
			n += 1
			PanelKit.button(actions, label or Language.t(key), style, n, z, colors, fn).Name = key
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
		if mute then
			button("admin.unmute", "secondary", function()
				AdminNetwork.unmute(member.userId)
				act(Language.t("embed.mod.unmute", { user = member.name }))
			end)
		end
		button("admin.kick", "danger", function()
			AdminNetwork.kick(member.userId, member.name, reason())
			act(Language.t("embed.mod.kick", { user = member.name }))
		end)
		if myRank >= 2 then
			if AdminNetwork.isBanned(member.userId) then
				button("admin.unban", "secondary", function()
					AdminNetwork.unban(member.userId)
					act(Language.t("embed.mod.unban", { user = member.name }))
				end)
			else
				button("admin.ban", "danger", function()
					AdminNetwork.ban(member.userId, member.name, reason())
					act(Language.t("embed.mod.ban", { user = member.name }))
				end)
			end
			if AdminNetwork.isBlacklisted(member.userId) then
				button("admin.unblacklist", "secondary", function()
					AdminNetwork.unblacklist(member.userId)
					act(Language.t("embed.mod.unblacklist", { user = member.name }))
				end)
			else
				button("admin.blacklistUser", "danger", function()
					AdminNetwork.blacklist(member.userId, member.name, reason())
					act(Language.t("embed.mod.blacklist", { user = member.name }))
				end)
			end
			button(
				if AdminNetwork.isWhitelisted(member.userId) then "admin.unwhitelistUser" else "admin.whitelistUser",
				"secondary",
				function()
					if AdminNetwork.isWhitelisted(member.userId) then
						AdminNetwork.unwhitelist(member.userId)
						act(Language.t("embed.mod.unwhitelist", { user = member.name }))
					else
						AdminNetwork.whitelist(member.userId, member.name)
						act(Language.t("embed.mod.whitelist", { user = member.name }))
					end
				end
			)
		end

		-- Mute for a while
		PanelKit.text(box, Language.t("admin.muteFor"), "body", 11, z, colors)
		local lengths = PanelKit.row(box, 12, z)
		lengths.Name = "MuteLengths"
		for index, length in ipairs(MUTE_LENGTHS) do
			PanelKit.button(
				lengths,
				Language.t("admin.duration." .. length.key),
				"secondary",
				index,
				z,
				colors,
				function()
					AdminNetwork.mute(member.userId, member.name, reason(), os.time() + length.seconds)
					act(Language.t("embed.mod.mute", { user = member.name }))
				end
			).Name = "Mute_"
				.. length.key
		end
		PanelKit.button(
			lengths,
			Language.t("admin.duration.permanent"),
			"secondary",
			#MUTE_LENGTHS + 1,
			z,
			colors,
			function()
				AdminNetwork.mute(member.userId, member.name, reason())
				act(Language.t("embed.mod.mute", { user = member.name }))
			end
		).Name =
			"Mute_permanent"

		-- Their messages in the team chat
		local purgeKey = "purgeUser" .. member.userId
		PanelKit.button(
			box,
			Language.t(
				if confirming == purgeKey then "admin.confirmPurgeUser" else "admin.purgeUser",
				{ count = member.messages }
			),
			"danger",
			13,
			z,
			colors,
			function()
				if confirm(purgeKey) then
					local removed = AdminNetwork.purge(100000, member.userId)
					act(Language.t("admin.purged", { count = removed }))
				end
			end
		).Name =
			"PurgeUser"
	end

	local function membersSection(colors, nextOrder: () -> number, myRank: number)
		local stats = Stats.collect(period)
		local people = members(stats)
		if selected then
			for _, member in ipairs(members({ users = stats.users } :: any)) do
				if member.userId == selected then
					memberDetails(member, colors, nextOrder, myRank)
					return
				end
			end
			-- Not in the list (filtered out): show them anyway
			local userId = selected :: number
			memberDetails({
				userId = userId,
				name = if stats.users[userId] then stats.users[userId].name else "User " .. userId,
				online = Players:GetPlayerByUserId(userId) ~= nil,
				rank = AdminNetwork.getRank(userId),
				messages = if stats.users[userId] then stats.users[userId].count else 0,
				last = if stats.users[userId] then stats.users[userId].last else nil,
			}, colors, nextOrder, myRank)
			return
		end
		local search = PanelKit.input(card, memberQuery, Language.t("admin.searchMembers"), nextOrder(), z, colors)
		search.Name = "MemberSearch"
		search.FocusLost:Connect(function()
			if search.Text ~= memberQuery then
				memberQuery = search.Text
				render()
			end
		end)
		PanelKit.text(card, Language.t("admin.members", { count = #people }), "heading", nextOrder(), z, colors)
		local box = PanelKit.box(card, nextOrder(), z, colors)
		box.Name = "Members"
		if #people == 0 then
			PanelKit.text(box, Language.t("admin.nobody"), "muted", 1, z, colors)
		end
		for index, member in ipairs(people) do
			local row = PanelKit.row(box, index, z)
			row.Name = "Member_" .. member.userId
			PanelKit.avatar(row, member.userId, 26, 1, z, colors)
			local label = PanelKit.text(
				row,
				"<b>"
					.. escape(member.name)
					.. "</b>  "
					.. Language.t("admin.messageCount", { count = member.messages }),
				"body",
				2,
				z,
				colors
			)
			label.AutomaticSize = Enum.AutomaticSize.XY
			label.Size = UDim2.fromOffset(0, 0)
			PanelKit.pill(
				row,
				rankName(member.rank),
				if member.rank > 0 then colors.sendButton else colors.timestamp,
				3,
				z
			)
			if member.online then
				PanelKit.pill(row, Language.t("sidebar.online"), colors.success, 4, z)
			end
			if AdminNetwork.isMuted(member.userId) then
				PanelKit.pill(row, Language.t("admin.muted"), colors.warning, 5, z)
			end
			PanelKit.button(row, Language.t("admin.details"), "secondary", 6, z, colors, function()
				selected = member.userId
				render()
			end).Name =
				"Details"
		end
	end

	-- One moderation list (banned, muted, …) with a remove button per person
	local function listBox(
		titleKey: string,
		entries: { any },
		removeKey: string,
		remove: (number) -> (),
		colors,
		nextOrder: () -> number
	)
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
				act(Language.t("admin.updated"))
			end)
		end
	end

	local function moderation(colors, nextOrder: () -> number, myRank: number)
		-- Chat settings
		PanelKit.text(card, Language.t("admin.settings"), "heading", nextOrder(), z, colors)
		local settings = PanelKit.box(card, nextOrder(), z, colors)
		local slowmode = AdminNetwork.getSlowmode()
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
		PanelKit.button(
			settings,
			Language.t(if whitelistOn then "admin.whitelistOff" else "admin.whitelistOn"),
			if whitelistOn then "danger" else "secondary",
			4,
			z,
			colors,
			function()
				AdminNetwork.toggleWhitelist()
				act(Language.t(if whitelistOn then "reply.whitelist.off" else "reply.whitelist.on"))
			end
		).Name =
			"ToggleWhitelist"

		listBox("admin.banned", AdminNetwork.getBannedUsers(), "admin.unban", AdminNetwork.unban, colors, nextOrder)
		listBox("admin.mutedList", AdminNetwork.getMutedUsers(), "admin.unmute", AdminNetwork.unmute, colors, nextOrder)
		listBox(
			"admin.blacklist",
			AdminNetwork.getBlacklistedUsers(),
			"admin.remove",
			AdminNetwork.unblacklist,
			colors,
			nextOrder
		)
		listBox(
			"admin.whitelist",
			AdminNetwork.getWhitelistedUsers(),
			"admin.remove",
			AdminNetwork.unwhitelist,
			colors,
			nextOrder
		)

		-- Bots
		local bots = Bots.list()
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
						Bots.setDisabled(bot.id, not bot.disabled)
						act(Language.t("admin.updated"))
					end
				)
			end
		end
	end

	local function audit(colors, nextOrder: () -> number)
		local log = AdminNetwork.AuditLog
		local search = PanelKit.input(card, auditQuery, Language.t("admin.searchLog"), nextOrder(), z, colors)
		search.Name = "LogSearch"
		search.FocusLost:Connect(function()
			if search.Text ~= auditQuery then
				auditQuery = search.Text
				auditLimit = AUDIT_PAGE
				render()
			end
		end)
		local filters = PanelKit.row(card, nextOrder(), z)
		filters.Name = "LogFilters"
		PanelKit.button(
			filters,
			Language.t("admin.allActions"),
			if auditAction == nil then "selected" else "choice",
			0,
			z,
			colors,
			function()
				auditAction = nil
				render()
			end
		)
		for index, action in ipairs(log.actions()) do
			PanelKit.button(
				filters,
				Language.tOr("admin.action." .. action, action),
				if auditAction == action then "selected" else "choice",
				index,
				z,
				colors,
				function()
					auditAction = action
					auditLimit = AUDIT_PAGE
					render()
				end
			).Name = "Filter_"
				.. action
		end
		if auditTarget then
			PanelKit.button(card, Language.t("admin.clearPerson"), "secondary", nextOrder(), z, colors, function()
				auditTarget = nil
				render()
			end).Name =
				"ClearPerson"
		end
		local all = log.list({ query = auditQuery, action = auditAction, targetId = auditTarget })
		PanelKit.text(card, Language.t("admin.logCount", { count = #all }), "heading", nextOrder(), z, colors)
		local box = PanelKit.box(card, nextOrder(), z, colors)
		box.Name = "AuditLog"
		if #all == 0 then
			PanelKit.text(box, Language.t("admin.logEmpty"), "muted", 1, z, colors)
		end
		for index, entry in ipairs(all) do
			if index > auditLimit then
				break
			end
			local line = Language.t("admin.logLine", {
				actor = "<b>" .. escape(entry.actorName) .. "</b>",
				action = Language.tOr("admin.action." .. entry.action, entry.action),
				target = if entry.targetName or entry.targetId
					then "<b>" .. escape(tostring(entry.targetName or entry.targetId)) .. "</b>"
					else "",
			})
			local extra = {}
			if entry.detail then
				table.insert(extra, escape(entry.detail))
			end
			if entry.reason then
				table.insert(extra, "\u{201C}" .. escape(entry.reason) .. "\u{201D}")
			end
			PanelKit.text(
				box,
				'<font transparency="0.4">'
					.. when(entry.time)
					.. "</font>  "
					.. line
					.. (if #extra > 0 then "  \u{00B7}  " .. table.concat(extra, "  \u{00B7}  ") else ""),
				"body",
				index,
				z,
				colors
			).Name = "Entry_"
				.. index
		end
		if #all > auditLimit then
			PanelKit.button(card, Language.t("admin.showMore"), "secondary", nextOrder(), z, colors, function()
				auditLimit += AUDIT_PAGE
				render()
			end).Name =
				"ShowMore"
		end
	end

	local function tools(colors, nextOrder: () -> number, myRank: number)
		local rules = AdminNetwork.ChatRules

		-- Blocked words
		local words = rules.getBlockedWords()
		PanelKit.text(card, Language.t("admin.blockedWords", { count = #words }), "heading", nextOrder(), z, colors)
		local wordBox = PanelKit.box(card, nextOrder(), z, colors)
		wordBox.Name = "BlockedWords"
		PanelKit.text(wordBox, Language.t("admin.blockedHint"), "muted", 1, z, colors)
		local addRow = PanelKit.row(wordBox, 2, z)
		local wordInput = PanelKit.input(
			addRow,
			"",
			Language.t("admin.blockedPlaceholder"),
			1,
			z,
			colors,
			{ width = UDim.new(1, -80) }
		)
		wordInput.Name = "WordInput"
		PanelKit.button(addRow, Language.t("admin.add"), "primary", 2, z, colors, function()
			act(Language.t(if rules.addBlockedWord(wordInput.Text) then "admin.wordAdded" else "admin.wordNotAdded"))
		end).Name =
			"AddWord"
		local chips = PanelKit.row(wordBox, 3, z)
		chips.Name = "Words"
		for index, word in ipairs(words) do
			PanelKit.button(chips, escape(word) .. "  \u{00D7}", "secondary", index, z, colors, function()
				rules.removeBlockedWord(word)
				act(Language.t("admin.wordRemoved", { word = word }))
			end).Name = "Word_"
				.. word
		end

		-- Purge the team chat's newest messages
		PanelKit.text(card, Language.t("admin.purgeTitle"), "heading", nextOrder(), z, colors)
		local purgeRow = PanelKit.row(card, nextOrder(), z)
		purgeRow.Name = "Purge"
		for index, amount in ipairs(PURGE_AMOUNTS) do
			local key = "purge" .. amount
			PanelKit.button(
				purgeRow,
				Language.t(if confirming == key then "admin.confirmPurge" else "admin.purgeLast", { count = amount }),
				if confirming == key then "danger" else "secondary",
				index,
				z,
				colors,
				function()
					if confirm(key) then
						act(Language.t("admin.purged", { count = AdminNetwork.purge(amount) }))
					end
				end
			).Name = "Purge_"
				.. amount
		end

		-- Export
		PanelKit.text(card, Language.t("admin.exportTitle"), "heading", nextOrder(), z, colors)
		local exportRow = PanelKit.row(card, nextOrder(), z)
		PanelKit.button(exportRow, Language.t("admin.export"), "primary", 1, z, colors, function()
			local module = Stats.saveScript(Stats.transcript())
			AdminNetwork.AuditLog.record("export", { detail = module.Name })
			if params.openScript then
				params.openScript(module)
			end
			act(Language.t("admin.exported", { path = module:GetFullName() }))
		end).Name =
			"Export"

		-- Automatic backups
		local hours = rules.getAutoBackupHours()
		PanelKit.text(card, Language.t("admin.autoBackups"), "heading", nextOrder(), z, colors)
		local autoRow = PanelKit.row(card, nextOrder(), z)
		autoRow.Name = "AutoBackups"
		for index, option in ipairs(AUTO_BACKUP_HOURS) do
			PanelKit.button(
				autoRow,
				if option == 0 then Language.t("option.off") else Language.t("admin.everyHours", { hours = option }),
				if hours == option then "selected" else "choice",
				index,
				z,
				colors,
				function()
					rules.setAutoBackupHours(option)
					act(Language.t("admin.updated"))
				end
			).Name = "Auto_"
				.. option
		end
		PanelKit.text(
			card,
			Language.t("admin.lastAutoBackup", { time = when(rules.lastAutoBackup()) }),
			"muted",
			nextOrder(),
			z,
			colors
		)

		-- Backups
		local backups = VersionHistory.list()
		PanelKit.text(card, Language.t("admin.backups", { count = #backups }), "heading", nextOrder(), z, colors)
		local backupBox = PanelKit.box(card, nextOrder(), z, colors)
		backupBox.Name = "Backups"
		PanelKit.button(backupBox, Language.t("admin.backupNow"), "primary", 0, z, colors, function()
			local version = VersionHistory.create(Language.t("admin.backupLabel"))
			if version then
				AdminNetwork.AuditLog.record("backup", { detail = version.label })
			end
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
				when(version.timestamp)
					.. (if version.label ~= "" then "  \u{00B7}  " .. escape(version.label) else "")
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
			label.Size = UDim2.new(1, -200, 0, 0)
			if myRank >= 2 then
				local restoreKey = "restore" .. version.id
				PanelKit.button(
					row,
					Language.t(if confirming == restoreKey then "admin.confirmRestore" else "admin.restore"),
					if confirming == restoreKey then "danger" else "secondary",
					2,
					z,
					colors,
					function()
						if confirm(restoreKey) then
							VersionHistory.create("auto-before-restore")
							local ok = VersionHistory.restore(version.id)
							AdminNetwork.AuditLog.record("restore", { detail = version.label })
							act(Language.t(if ok then "reply.restore.done" else "reply.restore.failed"))
						end
					end
				).Name =
					"Restore"
				local deleteKey = "delete" .. version.id
				PanelKit.button(
					row,
					Language.t(if confirming == deleteKey then "admin.confirmDelete" else "admin.delete"),
					"danger",
					3,
					z,
					colors,
					function()
						if confirm(deleteKey) then
							VersionHistory.delete(version.id)
							act(Language.t("admin.updated"))
						end
					end
				).Name =
					"DeleteBackup"
			end
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
		local tabs = {}
		for _, key in ipairs(SECTIONS) do
			table.insert(tabs, { key = key, label = Language.t("admin.section." .. key) })
		end
		PanelKit.tabs(card, tabs, section, nextOrder(), z, colors, function(key)
			section = key
			selected = nil
			confirming = nil
			status = ""
			render()
		end)
		if status ~= "" then
			PanelKit.text(card, status, "body", nextOrder(), z, colors).Name = "Status"
		end
		if section == "members" then
			membersSection(colors, nextOrder, myRank)
		elseif section == "moderation" then
			moderation(colors, nextOrder, myRank)
		elseif section == "audit" then
			audit(colors, nextOrder)
		elseif section == "tools" then
			tools(colors, nextOrder, myRank)
		else
			overview(colors, nextOrder)
		end
	end

	-- Changes made elsewhere (commands, other moderators) show here too
	local queued = false
	refresh = function()
		if queued then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			if modal.isVisible() then
				render()
			end
		end)
	end
	Lifetime.add(AdminNetwork.onAdminEvent(refresh))
	Lifetime.add(AdminNetwork.AuditLog.onChanged(function()
		if section == "audit" then
			refresh()
		end
	end))
	Lifetime.connect(ChatNetwork.getFolder().ChildAdded, function()
		if section == "overview" then
			refresh()
		end
	end)

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
	return self
end

return AdminDialog
