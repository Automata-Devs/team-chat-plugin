--!strict
-- Unmutes a user so they can send messages

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "unmute",
	Aliases = {},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Unmute a user so they can send messages",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /unmute <username|userId>")
			return
		end

		local target = args[1]
		local userId = AdminNetwork.resolveUserId(target)
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. target)
			return
		end

		if not AdminNetwork.isMuted(userId) then
			ctx.addSystemMessage(target .. " is not muted.")
			return
		end

		AdminNetwork.unmute(userId)
		ctx.addSystemMessage("Unmuted " .. target .. " (ID: " .. userId .. ")")
	end,
}