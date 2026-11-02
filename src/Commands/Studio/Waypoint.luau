--!strict
-- Creates an undo waypoint with a label

local History = require(script.Parent.Parent.Parent.Services.History)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "waypoint",
	Aliases = { "wp" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Studio" },
	Description = "Create an undo waypoint with a label",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "label", description = "Name for the waypoint", optional = true },
	},
	Function = function(_speaker, args, ctx)
		local label = #args > 0 and table.concat(args, " ") or "Waypoint"
		History.waypoint(label)
		ctx.addSystemMessage(Language.t("reply.waypoint.set", { label = label }))
	end,
}
