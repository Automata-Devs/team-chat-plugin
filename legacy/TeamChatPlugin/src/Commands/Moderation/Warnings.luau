--!strict
-- Shows the warnings of a user

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "warnings",
	Aliases = {"warns"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "List the warnings of a user",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /warnings <username|userId>")
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. args[1])
			return
		end

		local warnings = AdminNetwork.getWarnings(userId)
		if #warnings == 0 then
			ctx.addSystemMessage(args[1] .. " has no warnings.")
			return
		end

		ctx.addSystemMessage(`Warnings for {args[1]} ({#warnings}):`)
		for i, w in warnings do
			ctx.addSystemMessage(`{i}. {w.reason} (by {w.moderatorName})`)
		end
	end,
}