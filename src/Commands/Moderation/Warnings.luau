--!strict
-- Shows the warnings of a user

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "warnings",
	Aliases = { "warns" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "List the warnings of a user",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/warnings <username|userId>" }))
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = args[1] }))
			return
		end

		local warnings = AdminNetwork.getWarnings(userId)
		if #warnings == 0 then
			ctx.addSystemMessage(Language.t("reply.warnings.none", { user = args[1] }))
			return
		end

		local fields = {}
		for i, w in warnings do
			table.insert(fields, {
				name = Language.t("embed.warnings.item", { n = i, moderator = w.moderatorName }),
				value = w.reason,
			})
		end
		ctx.addEmbed({
			title = Language.t("embed.warnings.title", { user = args[1] }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(246, 183, 48),
			fields = fields,
			footer = Language.t("embed.warnings.total", { count = #warnings }),
		})
	end,
}
