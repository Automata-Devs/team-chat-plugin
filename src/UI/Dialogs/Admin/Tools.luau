--!strict
--[[
	Tools

	The admin dashboard's Chat tools section: blocked words, purging the
	newest messages, exporting the chat, automatic backups and backups.
	Destructive actions ask for a second click.
]]

local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Shared)

local escape = Shared.escape
local when = Shared.when

local AUTO_BACKUP_HOURS = { 0, 1, 6, 24 }
local PURGE_AMOUNTS = { 10, 25, 50 }
local MAX_BACKUPS_SHOWN = 8

local Tools = {}

function Tools.build(view: Shared.View, colors, nextOrder: () -> number, myRank: number)
	local card, z, state = view.card, view.z, view.state
	local admin = view.services.admin
	local chat = view.services.chat
	local rules = admin.ChatRules
	local act = view.act

	local words = rules.getBlockedWords()
	PanelKit.text(card, Language.t("admin.blockedWords", { count = #words }), "heading", nextOrder(), z, colors)
	local wordBox = PanelKit.box(card, nextOrder(), z, colors)
	wordBox.Name = "BlockedWords"
	PanelKit.text(wordBox, Language.t("admin.blockedHint"), "muted", 1, z, colors)
	local addRow = PanelKit.row(wordBox, 2, z)
	local wordInput =
		PanelKit.input(addRow, "", Language.t("admin.blockedPlaceholder"), 1, z, colors, { width = UDim.new(1, -80) })
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
			Language.t(if state.confirming == key then "admin.confirmPurge" else "admin.purgeLast", { count = amount }),
			if state.confirming == key then "danger" else "secondary",
			index,
			z,
			colors,
			function()
				if view.confirm(key) then
					act(Language.t("admin.purged", { count = admin.purge(amount) }))
				end
			end
		).Name = "Purge_"
			.. amount
	end

	PanelKit.text(card, Language.t("admin.exportTitle"), "heading", nextOrder(), z, colors)
	local exportRow = PanelKit.row(card, nextOrder(), z)
	PanelKit.button(exportRow, Language.t("admin.export"), "primary", 1, z, colors, function()
		local module = chat.Stats.saveScript(chat.Stats.transcript())
		admin.AuditLog.record("export", { detail = module.Name })
		if view.openScript then
			view.openScript(module)
		end
		act(Language.t("admin.exported", { path = module:GetFullName() }))
	end).Name =
		"Export"

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

	local history = chat.VersionHistory
	local backups = history.list()
	PanelKit.text(card, Language.t("admin.backups", { count = #backups }), "heading", nextOrder(), z, colors)
	local backupBox = PanelKit.box(card, nextOrder(), z, colors)
	backupBox.Name = "Backups"
	PanelKit.button(backupBox, Language.t("admin.backupNow"), "primary", 0, z, colors, function()
		local version = history.create(Language.t("admin.backupLabel"))
		if version then
			admin.AuditLog.record("backup", { detail = version.label })
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
				Language.t(if state.confirming == restoreKey then "admin.confirmRestore" else "admin.restore"),
				if state.confirming == restoreKey then "danger" else "secondary",
				2,
				z,
				colors,
				function()
					if view.confirm(restoreKey) then
						history.create("auto-before-restore")
						local ok = history.restore(version.id)
						admin.AuditLog.record("restore", { detail = version.label })
						act(Language.t(if ok then "reply.restore.done" else "reply.restore.failed"))
					end
				end
			).Name =
				"Restore"
			local deleteKey = "delete" .. version.id
			PanelKit.button(
				row,
				Language.t(if state.confirming == deleteKey then "admin.confirmDelete" else "admin.delete"),
				"danger",
				3,
				z,
				colors,
				function()
					if view.confirm(deleteKey) then
						history.delete(version.id)
						act(Language.t("admin.updated"))
					end
				end
			).Name =
				"DeleteBackup"
		end
	end
end

return Tools
