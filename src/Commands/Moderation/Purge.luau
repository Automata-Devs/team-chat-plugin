--!strict
-- Deletes recent messages, optionally only from one user

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "purge",
	Aliases = { "delmsgs" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Delete the last N messages, optionally from one user",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "amount", description = "How many messages to delete (1-200)" },
		{ name = "user", description = "Only delete this user's messages", optional = true },
	},
	Function = function(_speaker, args, ctx)
		local amount = tonumber(args[1])
		if not amount or amount < 1 or amount > 200 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/purge <amount> [username|userId] (1-200)" }))
			return
		end

		local userId: number? = nil
		if args[2] then
			userId = AdminNetwork.resolveUserId(args[2])
			if not userId then
				ctx.addSystemMessage(Language.t("reply.unresolved", { user = args[2] }))
				return
			end
		end

		local removed = AdminNetwork.purge(math.floor(amount), userId)
		ctx.addEmbed(
			{ title = Language.t("reply.purge.done", { count = removed }), color = Color3.fromRGB(247, 75, 82) },
			{ public = true }
		)
	end,
}
