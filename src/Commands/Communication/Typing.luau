--!strict
-- Simulates a remote user typing (testing aid for the typing indicator)

local ChatNetwork = require(script.Parent.Parent.Parent.Services.Chat)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "typing",
	Aliases = { "simtyping" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Communication" },
	Description = "Simulate a user typing to test the typing indicator",
	Contributors = {},
	Args = {
		{ name = "name", description = "Name shown as typing" },
		{ name = "seconds", description = "How long, in seconds (default 5)", optional = true },
	},
	Function = function(_speaker, args, ctx)
		local name = args[1]
		if not name or name == "" then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/typing <name> [seconds]" }))
			return
		end

		local duration = tonumber(args[2]) or 5
		ChatNetwork.simulateTyping(name, duration)
		ctx.addSystemMessage(Language.t("reply.typing.simulating", { name = name, seconds = duration }))
	end,
}
