--!strict
-- Kicks a user from the experience

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "kick",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Kick a user from the chat (temporary block)",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
		{ name = "reason", description = "Reason for the kick", optional = true },
	},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/kick <username|userId> [reason]" }))
			return
		end

		local target = args[1]
		local reason = #args > 1 and table.concat(args, " ", 2) or "No reason provided"

		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = target }))
			return
		end

		-- Cannot kick someone of equal or higher rank
		local targetRank = AdminNetwork.getRank(userId)
		if targetRank >= speaker.rank then
			ctx.addSystemMessage(Language.t("reply.kick.higher"))
			return
		end

		AdminNetwork.kick(userId, target, reason)
		ctx.addEmbed({
			title = Language.t("embed.mod.kick", { user = target }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(247, 75, 82),
			fields = { { name = Language.t("embed.mod.reason"), value = reason } },
		}, { public = true })
	end,
}
