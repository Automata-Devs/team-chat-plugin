--!strict
-- Starts a timer that notifies you when it ends

local Abbreviate = require(script.Parent.Parent.Parent.Packages.Abbreviate)

-- Parses compound duration strings like "30s", "10m", "1h30m", "1w", "1mo", "1y".
-- (The Abbreviate module handles formatting; duration parsing stays local.)
local DURATION_UNITS: {[string]: number} = {s = 1, m = 60, h = 3600, d = 86400, w = 604800, mo = 2592000, y = 31536000}

local function parseDuration(text: string): number?
	local total, matched = 0, 0
	for amount, unit in text:lower():gmatch("(%d+)(%a+)") do
		local multiplier = DURATION_UNITS[unit]
		if not multiplier then
			return nil
		end
		total += tonumber(amount) :: number * multiplier
		matched += 1
	end
	if matched == 0 then
		return tonumber(text)
	end
	return total
end

return {
	Name = "timer",
	Aliases = {"remind"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Utility"},
	Description = "Start a timer with an optional label",
	Contributors = {"D3veloperHac"},
	Args = {"<duration>", "[label]"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /timer <duration> [label]  (e.g. 10m, 1h30m)")
			return
		end

		local seconds = parseDuration(args[1])
		if not seconds or seconds <= 0 then
			ctx.addSystemMessage("Invalid duration: " .. args[1])
			return
		end

		local label = #args > 1 and table.concat(args, " ", 2) or "Timer"
		ctx.addSystemMessage(`Timer "{label}" set for {Abbreviate.Format(seconds, "Time")}.`)

		task.delay(seconds, function()
			ctx.addSystemMessage(`Timer finished: {label}`)
		end)
	end,
}