--!strict
-- Bans a user from the chat

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "ban",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Ban a user from the chat",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
		{ name = "reason", description = "Reason for the ban", optional = true },
	},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/ban <username|userId> [reason]" }))
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
			ctx.addSystemMessage(Language.t("reply.ban.higher"))
			return
		end

		AdminNetwork.ban(userId, target, reason)
		ctx.addEmbed({
			title = Language.t("embed.mod.ban", { user = target }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(247, 75, 82),
			fields = { { name = Language.t("embed.mod.reason"), value = reason } },
		}, { public = true })
	end,
}
