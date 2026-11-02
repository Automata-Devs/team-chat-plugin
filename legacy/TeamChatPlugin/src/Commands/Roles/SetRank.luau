--!strict
-- Sets the rank of a user

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "setrank",
	Aliases = {"rank"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 3,
	RankLock = false,
	Loopable = false,
	Tags = {"Roles"},
	Description = "Set the rank of a user",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>", "<rank>"},
	Function = function(speaker, args, ctx)
		if #args < 2 then
			ctx.addSystemMessage("Usage: /setrank <username|userId> <rank>")
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. args[1])
			return
		end

		local newRank = tonumber(args[2])
		if not newRank or newRank % 1 ~= 0 or newRank < 0 then
			ctx.addSystemMessage("Rank must be a whole number, 0 or higher.")
			return
		end

		-- Can't touch equal/higher ranks, and can't grant a rank at or above your own
		if AdminNetwork.getRank(userId) >= speaker.rank then
			ctx.addSystemMessage("You cannot change the rank of someone of equal or higher rank.")
			return
		end
		if newRank >= speaker.rank then
			ctx.addSystemMessage("You cannot grant a rank equal to or higher than your own.")
			return
		end

		AdminNetwork.setRank(userId, newRank)
		ctx.addSystemMessage(`Set {args[1]}'s rank to {newRank}.`)
	end,
}