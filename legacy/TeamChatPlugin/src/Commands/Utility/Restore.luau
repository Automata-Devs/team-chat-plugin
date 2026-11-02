--!strict
-- Restore the chat history from a saved version snapshot

local VersionHistory = require(script.Parent.Parent.Parent.Networking.Chat.VersionHistory)

local function resolveId(key: string): string?
	local versions = VersionHistory.list()
	local index = tonumber(key)
	if index then
		local version = versions[index]
		if version then
			return version.id
		end
		return nil
	end
	for _, version in ipairs(versions) do
		if version.id == key then
			return version.id
		end
	end
	return nil
end

return {
	Name = "restore",
	Aliases = {"revert"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Utility"},
	Description = "Restore chat history from a saved version (no argument lists versions)",
	Contributors = {"D3veloperHac"},
	Args = {"[id]"},
	Function = function(speaker, args, ctx)
		local versions = VersionHistory.list()

		if #args == 0 then
			if #versions == 0 then
				ctx.addSystemMessage("No saved versions yet. Use /backup [label] to create one.")
				return
			end
			ctx.addSystemMessage("Saved versions (newest first):")
			for i, version in ipairs(versions) do
				local label = version.label ~= "" and (" - " .. version.label) or ""
				local when = os.date("%m/%d %H:%M", version.timestamp or os.time())
				ctx.addSystemMessage("  " .. i .. ". " .. when .. label .. " - " .. version.messageCount .. " messages by " .. (version.author or "Unknown"))
			end
			ctx.addSystemMessage("Use /restore <number or id> to restore a version.")
			return
		end

		local id = resolveId(args[1])
		if not id then
			ctx.addSystemMessage("No version found matching '" .. args[1] .. "'. Use /restore to list versions.")
			return
		end

		-- Snapshot the current history first so the restore itself can be reverted
		VersionHistory.create("auto-before-restore")

		if VersionHistory.restore(id) then
			ctx.addSystemMessage("Chat history restored. Toggle the chat widget to reload the view.")
		else
			ctx.addSystemMessage("Failed to restore version - snapshot data could not be loaded.")
		end
	end,
}