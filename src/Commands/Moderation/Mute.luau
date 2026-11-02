--!strict
-- Mutes a user so they cannot send messages

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "mute",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Mute a user so they cannot send messages",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
		{ name = "reason", description = "Reason for the mute", optional = true },
	},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/mute <username|userId> [reason]" }))
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
			ctx.addSystemMessage(Language.t("reply.mute.higher"))
			return
		end

		if AdminNetwork.isMuted(userId) then
			ctx.addSystemMessage(Language.t("reply.mute.already", { user = target }))
			return
		end

		AdminNetwork.mute(userId, target, reason)
		ctx.addEmbed({
			title = Language.t("embed.mod.mute", { user = target }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(255, 140, 50),
			fields = { { name = Language.t("embed.mod.reason"), value = reason } },
		}, { public = true })
	end,
}
