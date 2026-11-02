--!strict
-- Lifts a user's ban from the experience

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "unban",
	Aliases = {},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Lift a user's ban from the chat",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /unban <username|userId>")
			return
		end

		local target = args[1]
		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. target)
			return
		end

		if not AdminNetwork.isBanned(userId) then
			ctx.addSystemMessage(target .. " is not banned.")
			return
		end

		AdminNetwork.unban(userId)
		ctx.addSystemMessage("Unbanned " .. target .. " (ID: " .. userId .. ")")
	end,
}