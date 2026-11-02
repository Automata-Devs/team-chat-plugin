--!strict
-- Delete a saved version snapshot

local VersionHistory = require(script.Parent.Parent.Parent.Networking.Chat.VersionHistory)

return {
	Name = "delversion",
	Aliases = {"deleteversion"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Utility"},
	Description = "Delete a saved version snapshot",
	Contributors = {"D3veloperHac"},
	Args = {"<id or number>"},
	Function = function(speaker, args, ctx)
		if #args == 0 then
			ctx.addSystemMessage("Usage: /delversion <id or number> - use /restore to list versions.")
			return
		end

		local id = args[1]
		local index = tonumber(id)
		if index then
			local version = VersionHistory.list()[index]
			if not version then
				ctx.addSystemMessage("No version at position " .. id .. ".")
				return
				end
			id = version.id
		end

		if VersionHistory.delete(id) then
			ctx.addSystemMessage("Version " .. id .. " deleted.")
		else
			ctx.addSystemMessage("No version found matching '" .. args[1] .. "'.")
		end
	end,
}