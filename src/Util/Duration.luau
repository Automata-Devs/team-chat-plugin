--!strict
--[[
	Duration

	Parses durations typed in commands: "30s", "10m", "1h30m", "2d", "1w",
	"1mo", "1y", or a plain number of seconds.

	Usage:
		Duration.parse("1h30m")   -- 5400
		Duration.parse("abc")     -- nil
]]

local UNIT_SECONDS: { [string]: number } = {
	s = 1,
	m = 60,
	h = 3600,
	d = 86400,
	w = 604800,
	mo = 2592000,
	y = 31536000,
}

local Duration = {}

--[=[
	Seconds for a duration string, or nil when it isn't one.
]=]
function Duration.parse(text: string): number?
	local total, matched = 0, 0
	for amount, unit in string.gmatch(string.lower(text), "(%d+)(%a+)") do
		local multiplier = UNIT_SECONDS[unit]
		if not multiplier then
			return nil
		end
		total += (tonumber(amount) :: number) * multiplier
		matched += 1
	end
	if matched == 0 then
		return tonumber(text)
	end
	return total
end

return Duration
