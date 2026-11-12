--!strict
--[[
	Members

	The admin dashboard's Members section: everyone here, ranked or who
	wrote, with a search; and one person's details (rank, messages,
	warnings, mute) with every action on them, a reason and a mute length.
	You can only act on people ranked below you.
]]

local Players = game:GetService("Players")

local Identity = require(script.Parent.Parent.Parent.Parent.Core.Identity)
local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Shared)

local escape = Shared.escape
local when = Shared.when

local MUTE_LENGTHS = { { key = "m5", seconds = 300 }, { key = "h1", seconds = 3600 }, { key = "d1", seconds = 86400 } }

type Person = { name: string, count: number, last: number? }
type Summary = { users: { [number]: Person } }

local Members = {}

-- Everyone worth listing: here now, ranked, or who wrote in the chat
local function members(view: Shared.View, stats: Summary)
	local admin = view.services.admin
	local byId = {}
	for _, player in ipairs(Players:GetPlayers()) do
		byId[player.UserId] = { userId = player.UserId, name = player.Name, online = true }
	end
	for _, ranked in ipairs(admin.getRankedUsers()) do
		byId[ranked.userId] = byId[ranked.userId]
			or {
				userId = ranked.userId,
				name = if stats.users[ranked.userId]
					then stats.users[ranked.userId].name
					else view.nameOf(ranked.userId),
				online = false,
			}
	end
	for userId, person in pairs(stats.users) do
		byId[userId] = byId[userId] or { userId = userId, name = person.name, online = false }
	end
	local list = {}
	local query = string.lower(view.state.memberQuery)
	for userId, member in pairs(byId) do
		member.rank = admin.getRank(userId)
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

local function muteOf(view: Shared.View, userId: number)
	for _, entry in ipairs(view.services.admin.getMutedUsers()) do
		if entry.userId == userId then
			return entry
		end
	end
	return nil
end

-- One person: their details and every action on them
local function details(view: Shared.View, member, colors, nextOrder: () -> number, myRank: number)
	local card, z, state = view.card, view.z, view.state
	local admin = view.services.admin
	local act = view.act

	PanelKit.button(card, Language.t("admin.back"), "secondary", nextOrder(), z, colors, function()
		state.selected = nil
		view.render()
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
		view.rankName(member.rank),
		if member.rank > 0 then colors.sendButton else colors.timestamp,
		1,
		z
	)
	if member.online then
		PanelKit.pill(pills, Language.t("sidebar.online"), colors.success, 2, z)
	end
	local mute = muteOf(view, member.userId)
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
	if admin.isBanned(member.userId) then
		PanelKit.pill(pills, Language.t("admin.isBanned"), colors.danger, 4, z)
	end
	if admin.isBlacklisted(member.userId) then
		PanelKit.pill(pills, Language.t("admin.isBlacklisted"), colors.danger, 5, z)
	end
	if admin.isWhitelisted(member.userId) then
		PanelKit.pill(pills, Language.t("admin.isWhitelisted"), colors.success, 6, z)
	end
	local warnings = admin.getWarnings(member.userId)
	local facts = PanelKit.row(box, 3, z)
	PanelKit.tile(facts, Language.t("admin.statMessages"), tostring(member.messages), 1, z, colors)
	PanelKit.tile(facts, Language.t("admin.lastMessage"), when(member.last), 2, z, colors)
	PanelKit.tile(facts, Language.t("admin.warnings"), tostring(#warnings), 3, z, colors)

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
		view.showAudit(member.userId)
	end).Name =
		"ViewInLog"

	if member.userId == Identity.userId or member.rank >= myRank then
		PanelKit.text(box, Language.t("admin.cantAct"), "muted", 7, z, colors)
		return
	end

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
			admin.setRank(member.userId, member.rank + 1)
			act(Language.t("admin.rankSet", { user = member.name, rank = view.rankName(member.rank + 1) }))
		end)
	end
	if member.rank > 0 then
		button("admin.demote", "secondary", function()
			admin.setRank(member.userId, member.rank - 1)
			act(Language.t("admin.rankSet", { user = member.name, rank = view.rankName(member.rank - 1) }))
		end)
	end
	button("admin.warn", "secondary", function()
		admin.warn(member.userId, Identity.userId, reason(), Identity.username)
		act(Language.t("embed.mod.warn", { user = member.name }))
	end)
	if mute then
		button("admin.unmute", "secondary", function()
			admin.unmute(member.userId)
			act(Language.t("embed.mod.unmute", { user = member.name }))
		end)
	end
	button("admin.kick", "danger", function()
		admin.kick(member.userId, member.name, reason())
		act(Language.t("embed.mod.kick", { user = member.name }))
	end)
	if myRank >= 2 then
		if admin.isBanned(member.userId) then
			button("admin.unban", "secondary", function()
				admin.unban(member.userId)
				act(Language.t("embed.mod.unban", { user = member.name }))
			end)
		else
			button("admin.ban", "danger", function()
				admin.ban(member.userId, member.name, reason())
				act(Language.t("embed.mod.ban", { user = member.name }))
			end)
		end
		if admin.isBlacklisted(member.userId) then
			button("admin.unblacklist", "secondary", function()
				admin.unblacklist(member.userId)
				act(Language.t("embed.mod.unblacklist", { user = member.name }))
			end)
		else
			button("admin.blacklistUser", "danger", function()
				admin.blacklist(member.userId, member.name, reason())
				act(Language.t("embed.mod.blacklist", { user = member.name }))
			end)
		end
		button(
			if admin.isWhitelisted(member.userId) then "admin.unwhitelistUser" else "admin.whitelistUser",
			"secondary",
			function()
				if admin.isWhitelisted(member.userId) then
					admin.unwhitelist(member.userId)
					act(Language.t("embed.mod.unwhitelist", { user = member.name }))
				else
					admin.whitelist(member.userId, member.name)
					act(Language.t("embed.mod.whitelist", { user = member.name }))
				end
			end
		)
	end

	PanelKit.text(box, Language.t("admin.muteFor"), "body", 11, z, colors)
	local lengths = PanelKit.row(box, 12, z)
	lengths.Name = "MuteLengths"
	for index, length in ipairs(MUTE_LENGTHS) do
		PanelKit.button(lengths, Language.t("admin.duration." .. length.key), "secondary", index, z, colors, function()
			admin.mute(member.userId, member.name, reason(), os.time() + length.seconds)
			act(Language.t("embed.mod.mute", { user = member.name }))
		end).Name = "Mute_"
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
			admin.mute(member.userId, member.name, reason())
			act(Language.t("embed.mod.mute", { user = member.name }))
		end
	).Name =
		"Mute_permanent"

	-- Their messages in the team chat
	local purgeKey = "purgeUser" .. member.userId
	PanelKit.button(
		box,
		Language.t(
			if state.confirming == purgeKey then "admin.confirmPurgeUser" else "admin.purgeUser",
			{ count = member.messages }
		),
		"danger",
		13,
		z,
		colors,
		function()
			if view.confirm(purgeKey) then
				local removed = admin.purge(100000, member.userId)
				act(Language.t("admin.purged", { count = removed }))
			end
		end
	).Name =
		"PurgeUser"
end

function Members.build(view: Shared.View, colors, nextOrder: () -> number, myRank: number)
	local card, z, state = view.card, view.z, view.state
	local stats = view.services.chat.Stats.collect(state.period)
	local people = members(view, stats)
	if state.selected then
		for _, member in ipairs(members(view, { users = stats.users })) do
			if member.userId == state.selected then
				details(view, member, colors, nextOrder, myRank)
				return
			end
		end
		-- Filtered out of the list: show them anyway
		local userId = state.selected :: number
		details(view, {
			userId = userId,
			name = if stats.users[userId] then stats.users[userId].name else "User " .. userId,
			online = Players:GetPlayerByUserId(userId) ~= nil,
			rank = view.services.admin.getRank(userId),
			messages = if stats.users[userId] then stats.users[userId].count else 0,
			last = if stats.users[userId] then stats.users[userId].last else nil,
		}, colors, nextOrder, myRank)
		return
	end
	local search = PanelKit.input(card, state.memberQuery, Language.t("admin.searchMembers"), nextOrder(), z, colors)
	search.Name = "MemberSearch"
	search.FocusLost:Connect(function()
		if search.Text ~= state.memberQuery then
			state.memberQuery = search.Text
			view.render()
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
			"<b>" .. escape(member.name) .. "</b>  " .. Language.t("admin.messageCount", { count = member.messages }),
			"body",
			2,
			z,
			colors
		)
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = UDim2.fromOffset(0, 0)
		PanelKit.pill(
			row,
			view.rankName(member.rank),
			if member.rank > 0 then colors.sendButton else colors.timestamp,
			3,
			z
		)
		if member.online then
			PanelKit.pill(row, Language.t("sidebar.online"), colors.success, 4, z)
		end
		if view.services.admin.isMuted(member.userId) then
			PanelKit.pill(row, Language.t("admin.muted"), colors.warning, 5, z)
		end
		PanelKit.button(row, Language.t("admin.details"), "secondary", 6, z, colors, function()
			state.selected = member.userId
			view.render()
		end).Name =
			"Details"
	end
end

return Members
