--!strict
-- Whitelist a user so only they can send messages when whitelist mode is on

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "whitelist",
	Aliases = {"wl"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Add a user to the whitelist so they can chat when whitelist mode is enabled",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /whitelist <username|userId>")
			return
		end

		local target = args[1]
		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. target)
			return
		end

		if AdminNetwork.isWhitelisted(userId) then
			ctx.addSystemMessage(target .. " is already whitelisted.")
			return
		end

		AdminNetwork.whitelist(userId, target)
		ctx.addSystemMessage("Whitelisted " .. target .. " (ID: " .. userId .. ")")
	end,
}