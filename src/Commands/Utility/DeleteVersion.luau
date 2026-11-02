--!strict
-- Delete a saved version snapshot

local VersionHistory = require(script.Parent.Parent.Parent.Services.Chat.VersionHistory)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "delversion",
	Aliases = { "deleteversion" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Delete a saved version snapshot",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "version", description = "Version ID or its number in /restore" },
	},
	Function = function(_speaker, args, ctx)
		if #args == 0 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/delversion <id|number>" }))
			return
		end

		local id = args[1]
		local index = tonumber(id)
		if index then
			local version = VersionHistory.list()[index]
			if not version then
				ctx.addSystemMessage(Language.t("reply.version.noPosition", { n = id }))
				return
			end
			id = version.id
		end

		if VersionHistory.delete(id) then
			ctx.addSystemMessage(Language.t("reply.version.deleted", { id = id }))
		else
			ctx.addSystemMessage(Language.t("reply.version.notFound", { query = args[1] }))
		end
	end,
}
