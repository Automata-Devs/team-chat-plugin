--!strict
-- Mutes a user so they cannot send messages

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "mute",
	Aliases = {},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Mute a user so they cannot send messages",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>", "[reason]"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /mute <username|userId> [reason]")
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
			ctx.addSystemMessage("You cannot mute someone of equal or higher rank.")
			return
		end

		if AdminNetwork.isMuted(userId) then
			ctx.addSystemMessage(target .. " is already muted.")
			return
		end

		AdminNetwork.mute(userId, target, reason)
		ctx.addSystemMessage("Muted " .. target .. " (ID: " .. userId .. ") - Reason: " .. reason)
	end,
}