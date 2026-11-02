--!strict
-- Toggle the blacklist on/off

-- Note: Blacklist is always active when users are blacklisted.
-- This command toggles whether the blacklist filter is enforced.

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "toggleblacklist",
	Aliases = { "tbl" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Toggle the blacklist filter on/off",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		local list = AdminNetwork.getBlacklistedUsers()
		if #list == 0 then
			ctx.addSystemMessage(Language.t("reply.blacklist.empty"))
			return
		end

		ctx.addSystemMessage(Language.t("reply.blacklist.always"))
		ctx.addSystemMessage(Language.t("reply.blacklist.count", { count = #list }))
		for _, data in ipairs(list) do
			ctx.addSystemMessage(
				"  "
					.. data.username
					.. " (ID: "
					.. data.userId
					.. ") - "
					.. (data.reason or Language.t("reply.noReason"))
			)
		end
	end,
}
