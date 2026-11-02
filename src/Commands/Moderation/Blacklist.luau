--!strict
-- Blacklists a user from the chat permanently

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "blacklist",
	Aliases = { "bl" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Blacklist a user from the chat permanently",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
		{ name = "reason", description = "Reason for blacklisting", optional = true },
	},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/blacklist <username|userId> [reason]" }))
			return
		end

		local target = args[1]
		local reason = #args > 1 and table.concat(args, " ", 2) or "No reason provided"

		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = target }))
			return
		end

		local targetRank = AdminNetwork.getRank(userId)
		if targetRank >= speaker.rank then
			ctx.addSystemMessage(Language.t("reply.blacklist.higher"))
			return
		end

		AdminNetwork.blacklist(userId, target, reason)
		ctx.addEmbed({
			title = Language.t("embed.mod.blacklist", { user = target }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(247, 75, 82),
			fields = { { name = Language.t("embed.mod.reason"), value = reason } },
		}, { public = true })
	end,
}
