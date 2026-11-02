--!strict
-- Remove a user from the whitelist

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "unwhitelist",
	Aliases = {"unwl"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Remove a user from the whitelist",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /unwhitelist <username|userId>")
			return
		end

		local target = args[1]
		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. target)
			return
		end

		if not AdminNetwork.isWhitelisted(userId) then
			ctx.addSystemMessage(target .. " is not whitelisted.")
			return
		end

		AdminNetwork.unwhitelist(userId)
		ctx.addSystemMessage("Unwhitelisted " .. target .. " (ID: " .. userId .. ")")
	end,
}