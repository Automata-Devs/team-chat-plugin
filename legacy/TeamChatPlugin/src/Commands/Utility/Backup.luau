--!strict
-- Backup the chat history as a version snapshot

local VersionHistory = require(script.Parent.Parent.Parent.Networking.Chat.VersionHistory)

return {
	Name = "backup",
	Aliases = {"snapshot"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Utility"},
	Description = "Save a version snapshot of the chat history",
	Contributors = {"D3veloperHac"},
	Args = {"[label]"},
	Function = function(speaker, args, ctx)
		local label = #args > 0 and table.concat(args, " ") or nil
		local version = VersionHistory.create(label)
		if not version then
			ctx.addSystemMessage("Failed to create backup - plugin is not fully initialized yet.")
			return
		end
		local labelText = version.label ~= "" and (" '" .. version.label .. "'") or ""
		ctx.addSystemMessage("Backup created" .. labelText .. " - " .. version.messageCount .. " messages saved.")
		ctx.addSystemMessage("Restore later with /restore " .. version.id)
	end,
}