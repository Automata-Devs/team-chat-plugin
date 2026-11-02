--!strict
-- Starts a timer that notifies you when it ends

local Abbreviate = require(script.Parent.Parent.Parent.Packages.Abbreviate)
local Duration = require(script.Parent.Parent.Parent.Util.Duration)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "timer",
	Aliases = { "remind" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Start a timer with an optional label",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "duration", description = "How long, e.g. 10m or 1h30m" },
		{ name = "label", description = "What the reminder says", optional = true },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/timer <duration> [label] (10m, 1h30m)" }))
			return
		end

		local seconds = Duration.parse(args[1])
		if not seconds or seconds <= 0 then
			ctx.addSystemMessage(Language.t("reply.invalidDuration", { value = args[1] }))
			return
		end

		local label = #args > 1 and table.concat(args, " ", 2) or Language.t("reply.timer.default")
		ctx.addSystemMessage(
			Language.t("reply.timer.set", { label = label, duration = Abbreviate.Format(seconds, "Time") })
		)

		Lifetime.delay(seconds, function() -- cancelled if the plugin unloads
			ctx.addSystemMessage(Language.t("reply.timer.done", { label = label }))
		end)
	end,
}
