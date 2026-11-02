--!strict
-- Warns a user and records it

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "warn",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Warn a user",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
		{ name = "reason", description = "Reason for the warning" },
	},
	Function = function(speaker, args, ctx)
		if #args < 2 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/warn <username|userId> <reason>" }))
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = args[1] }))
			return
		end

		if AdminNetwork.getRank(userId) >= speaker.rank then
			ctx.addSystemMessage(Language.t("reply.warn.higher"))
			return
		end

		local reason = table.concat(args, " ", 2)
		AdminNetwork.warn(userId, speaker.userId, reason)
		local count = #AdminNetwork.getWarnings(userId)
		ctx.addEmbed({
			title = Language.t("embed.mod.warn", { user = args[1] }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(246, 183, 48),
			fields = {
				{ name = Language.t("embed.mod.reason"), value = reason },
				{ name = Language.t("embed.mod.warnings"), value = tostring(count), inline = true },
			},
		}, { public = true })
	end,
}
