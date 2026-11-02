--!strict
-- Kicks a user from the experience

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "kick",
	Aliases = {},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Kick a user from the chat (temporary block)",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>", "[reason]"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /kick <username|userId> [reason]")
			return
		end

		local target = args[1]
		local reason = #args > 1 and table.concat(args, " ", 2) or "No reason provided"

		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. target)
			return
		end

		-- Cannot kick someone of equal or higher rank
		local targetRank = AdminNetwork.getRank(userId)
		if targetRank >= speaker.rank then
			ctx.addSystemMessage("You cannot kick someone of equal or higher rank.")
			return
		end

		AdminNetwork.kick(userId, target, reason)
		ctx.addSystemMessage("Kicked " .. target .. " (ID: " .. userId .. ") - Reason: " .. reason)
	end,
}