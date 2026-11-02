--!strict
-- Restore the chat history from a saved version snapshot

local VersionHistory = require(script.Parent.Parent.Parent.Services.Chat.VersionHistory)
local Language = require(script.Parent.Parent.Parent.Core.Language)

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
	Aliases = { "revert" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Restore chat history from a saved version (no argument lists versions)",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "version", description = "Version ID or number (leave out to list them)", optional = true },
	},
	Function = function(_speaker, args, ctx)
		local versions = VersionHistory.list()

		if #args == 0 then
			if #versions == 0 then
				ctx.addSystemMessage(Language.t("reply.restore.none"))
				return
			end
			local fields = {}
			for i, version in ipairs(versions) do
				local summary = Language.t("embed.restore.value", {
					count = version.messageCount,
					author = version.author or Language.t("reply.unknownAuthor"),
				})
				table.insert(fields, {
					name = Language.t("embed.restore.item", {
						n = i,
						when = os.date("%d/%m %H:%M", version.timestamp or os.time()),
					}),
					value = if version.label ~= "" then version.label .. "\n" .. summary else summary,
				})
			end
			ctx.addEmbed({
				title = Language.t("embed.restore.title"),
				fields = fields,
				footer = Language.t("reply.restore.hint"),
			})
			return
		end

		local id = resolveId(args[1])
		if not id then
			ctx.addSystemMessage(Language.t("reply.restore.notFound", { query = args[1] }))
			return
		end

		-- Snapshot the current history first so the restore itself can be reverted
		VersionHistory.create("auto-before-restore")

		if VersionHistory.restore(id) then
			ctx.addSystemMessage(Language.t("reply.restore.done"))
		else
			ctx.addSystemMessage(Language.t("reply.restore.failed"))
		end
	end,
}
