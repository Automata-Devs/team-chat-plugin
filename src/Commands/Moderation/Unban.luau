--!strict
-- Lifts a user's ban from the experience

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "unban",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Lift a user's ban from the chat",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/unban <username|userId>" }))
			return
		end

		local target = args[1]
		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = target }))
			return
		end

		if not AdminNetwork.isBanned(userId) then
			ctx.addSystemMessage(Language.t("reply.unban.not", { user = target }))
			return
		end

		AdminNetwork.unban(userId)
		ctx.addEmbed({
			title = Language.t("embed.mod.unban", { user = target }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(63, 191, 110),
		}, { public = true })
	end,
}
