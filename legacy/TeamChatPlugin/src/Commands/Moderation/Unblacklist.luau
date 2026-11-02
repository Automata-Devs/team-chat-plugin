--!strict
-- Remove a user from the blacklist

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "unblacklist",
	Aliases = {"unbl"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Remove a user from the blacklist",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /unblacklist <username|userId>")
			return
		end

		local target = args[1]
		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. target)
			return
		end

		if not AdminNetwork.isBlacklisted(userId) then
			ctx.addSystemMessage(target .. " is not blacklisted.")
			return
		end

		AdminNetwork.unblacklist(userId)
		ctx.addSystemMessage("Unblacklisted " .. target .. " (ID: " .. userId .. ")")
	end,
}