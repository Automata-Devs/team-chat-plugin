--!strict
-- Sends an action message, e.g. /me waves -> *D3veloperHac waves*

local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "me",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Communication" },
	Description = "Describe what you're doing",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "action", description = "What you're doing, e.g. waves" },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/me <action>" }))
			return
		end
		ctx.sendMessage("*" .. ctx.getUsername() .. " " .. table.concat(args, " ") .. "*")
	end,
}
