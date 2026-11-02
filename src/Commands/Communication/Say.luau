--!strict
-- Sends a message that shows as written by someone else (admins only)

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local ChatNetwork = require(script.Parent.Parent.Parent.Services.Chat)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "say",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Communication" },
	Description = "Make someone say something",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Who says it (username or user ID)" },
		{ name = "message", description = "What they say", optional = true },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/say <user> [message]" }))
			return
		end
		local message = if #args > 1 then table.concat(args, " ", 2) else "..."
		-- Real users get their avatar and badges; unknown names still work (initial avatar)
		local userId = AdminNetwork.resolveUserId(args[1]) or 0
		local name = if userId > 0 then (AdminNetwork.getUsernameByUserId(userId) or args[1]) else args[1]
		ChatNetwork.sendMessageAs(name, userId, message)
	end,
}
