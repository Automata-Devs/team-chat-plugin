--!strict
-- Unmutes a user so they can send messages

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "unmute",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Unmute a user so they can send messages",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/unmute <username|userId>" }))
			return
		end

		local target = args[1]
		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = target }))
			return
		end

		if not AdminNetwork.isMuted(userId) then
			ctx.addSystemMessage(Language.t("reply.unmute.not", { user = target }))
			return
		end

		AdminNetwork.unmute(userId)
		ctx.addEmbed({
			title = Language.t("embed.mod.unmute", { user = target }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(63, 191, 110),
		}, { public = true })
	end,
}
