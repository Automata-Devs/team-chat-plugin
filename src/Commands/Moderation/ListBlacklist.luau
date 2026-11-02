--!strict
-- List all blacklisted users

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "listblacklist",
	Aliases = { "listbl", "bllist" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation", "Info" },
	Description = "List all blacklisted users",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		local list = AdminNetwork.getBlacklistedUsers()
		if #list == 0 then
			ctx.addSystemMessage(Language.t("reply.blacklist.none"))
			return
		end
		local fields = {}
		for _, data in ipairs(list) do
			table.insert(fields, { name = data.username, value = data.reason or Language.t("reply.noReason") })
		end
		ctx.addEmbed({
			title = Language.t("embed.blacklist.title", { count = #list }),
			color = Color3.fromRGB(247, 75, 82),
			fields = fields,
		})
	end,
}
