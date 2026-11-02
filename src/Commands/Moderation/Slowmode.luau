--!strict
-- Limits how often users can send messages

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "slowmode",
	Aliases = { "slow" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Set the delay between messages (0 to disable)",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "seconds", description = "Seconds between messages (0-3600, 0 turns it off)" },
	},
	Function = function(_speaker, args, ctx)
		local seconds = tonumber(args[1])
		if not seconds or seconds < 0 or seconds > 3600 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/slowmode <seconds> (0-3600)" }))
			return
		end
		AdminNetwork.setSlowmode(seconds)
		ctx.addEmbed({
			title = if seconds == 0
				then Language.t("reply.slowmode.off")
				else Language.t("reply.slowmode.set", { seconds = seconds }),
		}, { public = true })
	end,
}
