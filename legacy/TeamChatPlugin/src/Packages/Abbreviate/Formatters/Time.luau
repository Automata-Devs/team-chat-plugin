--!strict
--[[
	Time
	Input is in SECONDS.
	3725 -> "1h 2m 5s" (Short) | "01:02:05" (Clock) | "1 hour 2 minutes 5 seconds" (Long)
	Options: TimeStyle ("Short" | "Clock" | "Long"), MaxUnits (default 3, Short/Long only)
]]

local Utils = require(script.Parent.Parent.Utils)
local Types = require(script.Parent.Parent.Types)

local UNITS = {
	{ Seconds = 31536000, Short = "y", Singular = "year", Plural = "years" },
	{ Seconds = 86400, Short = "d", Singular = "day", Plural = "days" },
	{ Seconds = 3600, Short = "h", Singular = "hour", Plural = "hours" },
	{ Seconds = 60, Short = "m", Singular = "minute", Plural = "minutes" },
	{ Seconds = 1, Short = "s", Singular = "second", Plural = "seconds" },
}

local function clock(total: number): string
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local seconds = total % 60

	if hours > 0 then
		return string.format("%02d:%02d:%02d", hours, minutes, seconds)
	end
	return string.format("%02d:%02d", minutes, seconds)
end

return function(value: number, options: Types.Options): string
	local valid, magnitude, sign = Utils.Sanitize(value)
	if not valid then
		return options.Fallback or Utils.DEFAULT_FALLBACK
	end
	if magnitude == math.huge then
		return Utils.Wrap(sign .. (options.InfinityText or Utils.DEFAULT_INFINITY), options)
	end

	local total = math.floor(magnitude)
	local style = options.TimeStyle or "Short"

	if style == "Clock" then
		return Utils.Wrap(sign .. clock(total), options)
	end

	if total == 0 then
		return Utils.Wrap(style == "Long" and "0 seconds" or "0s", options)
	end

	local maxUnits = math.max(1, math.floor(options.MaxUnits or 3))
	local parts: { string } = {}
	local remaining = total

	for _, unit in UNITS do
		if #parts >= maxUnits then
			break
		end
		if remaining >= unit.Seconds then
			local amount = remaining // unit.Seconds
			remaining -= amount * unit.Seconds

			if style == "Long" then
				table.insert(parts, `{amount} {amount == 1 and unit.Singular or unit.Plural}`)
			else
				table.insert(parts, `{amount}{unit.Short}`)
			end
		end
	end

	return Utils.Wrap(sign .. table.concat(parts, " "), options)
end