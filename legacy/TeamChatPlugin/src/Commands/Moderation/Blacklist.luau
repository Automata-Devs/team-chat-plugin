--!strict
-- Blacklists a user from the chat permanently

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "blacklist",
	Aliases = {"bl"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Blacklist a user from the chat permanently",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>", "[reason]"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /blacklist <username|userId> [reason]")
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
			ctx.addSystemMessage("You cannot blacklist someone of equal or higher rank.")
			return
		end

		AdminNetwork.blacklist(userId, target, reason)
		ctx.addSystemMessage("Blacklisted " .. target .. " (ID: " .. userId .. ") - Reason: " .. reason)
	end,
}