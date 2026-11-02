--!strict
-- Simulates a remote user typing (testing aid for the typing indicator)

local ChatNetwork = require(script.Parent.Parent.Parent.Networking.ChatNetwork)

return {
	Name = "typing",
	Aliases = {"simtyping"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Communication"},
	Description = "Simulate a user typing to test the typing indicator",
	Contributors = {},
	Args = {"<name>", "[seconds]"},
	Function = function(speaker, args, ctx)
		local name = args[1]
		if not name or name == "" then
			ctx.addSystemMessage("Usage: /typing <name> [seconds] - simulates that user typing")
			return
		end

		local duration = tonumber(args[2]) or 5
		ChatNetwork.simulateTyping(name, duration)
		ctx.addSystemMessage(`Simulating '{name}' typing for {duration} seconds...`)
	end,
}