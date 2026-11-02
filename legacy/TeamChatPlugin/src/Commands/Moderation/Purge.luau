--!strict
-- Deletes recent messages, optionally only from one user

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "purge",
	Aliases = {"delmsgs"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Delete the last N messages, optionally from one user",
	Contributors = {"D3veloperHac"},
	Args = {"<amount>", "[username|userId]"},
	Function = function(speaker, args, ctx)
		local amount = tonumber(args[1])
		if not amount or amount < 1 or amount > 200 then
			ctx.addSystemMessage("Usage: /purge <amount> [username|userId]  (1-200)")
			return
		end

		local userId: number? = nil
		if args[2] then
			userId = AdminNetwork.resolveUserId(args[2])
			if not userId then
				ctx.addSystemMessage("Could not resolve user: " .. args[2])
				return
			end
		end

		local removed = AdminNetwork.purge(math.floor(amount), userId)
		ctx.addSystemMessage(`Deleted {removed} message(s).`)
	end,
}