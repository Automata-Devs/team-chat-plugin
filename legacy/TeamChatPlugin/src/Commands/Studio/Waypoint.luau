--!strict
-- Creates an undo waypoint with a label

local ChangeHistoryService = game:GetService("ChangeHistoryService")

return {
	Name = "waypoint",
	Aliases = {"wp"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Studio"},
	Description = "Create an undo waypoint with a label",
	Contributors = {"D3veloperHac"},
	Args = {"[label]"},
	Function = function(speaker, args, ctx)
		local label = #args > 0 and table.concat(args, " ") or "Waypoint"
		ChangeHistoryService:SetWaypoint(label)
		ctx.addSystemMessage(`Waypoint set: {label}`)
	end,
}