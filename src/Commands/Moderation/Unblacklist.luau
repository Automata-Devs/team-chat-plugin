--!strict
-- Remove a user from the blacklist

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "unblacklist",
	Aliases = { "unbl" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Remove a user from the blacklist",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/unblacklist <username|userId>" }))
			return
		end

		local target = args[1]
		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = target }))
			return
		end

		if not AdminNetwork.isBlacklisted(userId) then
			ctx.addSystemMessage(Language.t("reply.unblacklist.not", { user = target }))
			return
		end

		AdminNetwork.unblacklist(userId)
		ctx.addEmbed({
			title = Language.t("embed.mod.unblacklist", { user = target }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(63, 191, 110),
		}, { public = true })
	end,
}
