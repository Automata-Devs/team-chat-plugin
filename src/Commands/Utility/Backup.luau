--!strict
-- Backup the chat history as a version snapshot

local VersionHistory = require(script.Parent.Parent.Parent.Services.Chat).VersionHistory
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "backup",
	Aliases = { "snapshot" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Save a version snapshot of the chat history",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "label", description = "Name for the backup", optional = true },
	},
	Function = function(_speaker, args, ctx)
		local label = #args > 0 and table.concat(args, " ") or nil
		local version = VersionHistory.create(label)
		if not version then
			ctx.addSystemMessage(Language.t("reply.backup.notReady"))
			return
		end
		local fields = {}
		if version.label ~= "" then
			table.insert(fields, { name = Language.t("embed.backup.label"), value = version.label, inline = true })
		end
		table.insert(
			fields,
			{ name = Language.t("embed.backup.messages"), value = tostring(version.messageCount), inline = true }
		)
		ctx.addEmbed({
			title = Language.t("embed.backup.title"),
			color = Color3.fromRGB(63, 191, 110),
			fields = fields,
			footer = Language.t("reply.backup.hint", { id = version.id }),
		})
	end,
}
