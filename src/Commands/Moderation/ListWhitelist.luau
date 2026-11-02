--!strict
-- List all whitelisted users

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "listwhitelist",
	Aliases = { "listwl", "wllist" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation", "Info" },
	Description = "List all whitelisted users",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		local enabled = AdminNetwork.isWhitelistEnabled()
		local list = AdminNetwork.getWhitelistedUsers()
		local fields = {}
		for _, data in ipairs(list) do
			table.insert(fields, { name = data.username, value = "ID " .. tostring(data.userId), inline = true })
		end
		ctx.addEmbed({
			title = Language.t("embed.whitelist.listTitle", { count = #list }),
			description = Language.t(
				"reply.whitelist.mode",
				{ state = Language.t(if enabled then "reply.enabled" else "reply.disabled") }
			),
			fields = fields,
			footer = if #list == 0 then Language.t("reply.whitelist.none") else nil,
		})
	end,
}
