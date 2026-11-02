--!strict
-- Bans a user from the chat

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "ban",
	Aliases = {},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Ban a user from the chat",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>", "[reason]"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /ban <username|userId> [reason]")
			return
		end

		local target = args[1]
		local reason = #args > 1 and table.concat(args, " ", 2) or "No reason provided"

		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. target)
			return
		end

		local targetRank = AdminNetwork.getRank(userId)
		if targetRank >= speaker.rank then
			ctx.addSystemMessage("You cannot ban someone of equal or higher rank.")
			return
		end

		AdminNetwork.ban(userId, target, reason)
		ctx.addSystemMessage("Banned " .. target .. " (ID: " .. userId .. ") - Reason: " .. reason)
	end,
}