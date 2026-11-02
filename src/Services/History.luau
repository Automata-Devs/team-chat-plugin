--!strict
--[[
	History

	Undo support (ChangeHistoryService). Use it for changes the plugin makes
	to the user's place content on their behalf, so each one is a single
	Ctrl+Z step. Chat data in ServerStorage.TeamChatData is shared plugin state
	and is deliberately not recorded (see docs/ARCHITECTURE.md, Undo policy).

	Usage:
		local ok, err = History.record("Rename parts", function()
			part.Name = "Door"
		end)
		History.waypoint("Before lighting pass")
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Logger = require(script.Parent.Parent.Core.Logger)

local log = Logger.scope("History")

local History = {}

--[=[
	Runs `change` inside an undo recording named `name`. If `change` errors,
	the recording is cancelled (its edits are reverted) and the error returned.
	Returns (true, nil) on success.
]=]
function History.record(name: string, change: () -> ()): (boolean, string?)
	local recording = ChangeHistoryService:TryBeginRecording(name, name)
	if not recording then
		-- Another recording is open (or Studio is in a state that forbids one):
		-- still make the change, but it won't be its own undo step.
		log.debug("Couldn't start recording %q; applying without a separate undo step", name)
	end

	local ok, err = pcall(change)

	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not ok then
		log.warn("%s failed: %s", name, tostring(err))
		return false, tostring(err)
	end
	return true, nil
end

--[=[
	Adds a named undo waypoint (what /waypoint does).
]=]
function History.waypoint(label: string)
	ChangeHistoryService:SetWaypoint(label)
end

return History
