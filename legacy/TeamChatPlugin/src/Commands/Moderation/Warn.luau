--!strict
-- Warns a user and records it

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "warn",
	Aliases = {},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Warn a user",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>", "<reason>"},
	Function = function(speaker, args, ctx)
		if #args < 2 then
			ctx.addSystemMessage("Usage: /warn <username|userId> <reason>")
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. args[1])
			return
		end

		if AdminNetwork.getRank(userId) >= speaker.rank then
			ctx.addSystemMessage("You cannot warn someone of equal or higher rank.")
			return
		end

		local reason = table.concat(args, " ", 2)
		AdminNetwork.warn(userId, speaker.userId, reason)
		local count = #AdminNetwork.getWarnings(userId)
		ctx.addSystemMessage(`Warned {args[1]} ({count} total) - Reason: {reason}`)
	end,
}