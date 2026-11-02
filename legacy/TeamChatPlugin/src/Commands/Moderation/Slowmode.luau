--!strict
-- Limits how often users can send messages

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "slowmode",
	Aliases = {"slow"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Set the delay between messages (0 to disable)",
	Contributors = {"D3veloperHac"},
	Args = {"<seconds>"},
	Function = function(speaker, args, ctx)
		local seconds = tonumber(args[1])
		if not seconds or seconds < 0 or seconds > 3600 then
			ctx.addSystemMessage("Usage: /slowmode <seconds>  (0-3600, 0 disables)")
			return
		end

		AdminNetwork.setSlowmode(seconds)
		if seconds == 0 then
			ctx.addSystemMessage("Slowmode disabled.")
		else
			ctx.addSystemMessage(`Slowmode set to {seconds}s.`)
		end
	end,
}