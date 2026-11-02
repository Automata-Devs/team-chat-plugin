--!strict
-- Whitelist a user so only they can send messages when whitelist mode is on

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "whitelist",
	Aliases = { "wl" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Add a user to the whitelist so they can chat when whitelist mode is enabled",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/whitelist <username|userId>" }))
			return
		end

		local target = args[1]
		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = target }))
			return
		end

		if AdminNetwork.isWhitelisted(userId) then
			ctx.addSystemMessage(Language.t("reply.whitelist.already", { user = target }))
			return
		end

		AdminNetwork.whitelist(userId, target)
		ctx.addEmbed({
			title = Language.t("embed.mod.whitelist", { user = target }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(63, 191, 110),
		}, { public = true })
	end,
}
