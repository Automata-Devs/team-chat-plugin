--!strict
-- Sets the rank of a user

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "setrank",
	Aliases = { "rank" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 3,
	RankLock = false,
	Loopable = false,
	Tags = { "Roles" },
	Description = "Set the rank of a user",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
		{ name = "rank", description = "New rank number (0 or higher)" },
	},
	Function = function(speaker, args, ctx)
		if #args < 2 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/setrank <username|userId> <rank>" }))
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = args[1] }))
			return
		end

		local newRank = tonumber(args[2])
		if not newRank or newRank % 1 ~= 0 or newRank < 0 then
			ctx.addSystemMessage(Language.t("reply.setrank.number"))
			return
		end

		-- Can't touch equal/higher ranks, and can't grant a rank at or above your own
		if AdminNetwork.getRank(userId) >= speaker.rank then
			ctx.addSystemMessage(Language.t("reply.setrank.higher"))
			return
		end
		if newRank >= speaker.rank then
			ctx.addSystemMessage(Language.t("reply.setrank.tooHigh"))
			return
		end

		AdminNetwork.setRank(userId, newRank)
		ctx.addEmbed({
			title = Language.t("embed.mod.setrank", {
				user = args[1],
				rank = Language.tOr("rank." .. newRank, AdminNetwork.getRankName(newRank)),
			}),
			thumbnailUserId = userId,
		}, { public = true })
	end,
}
