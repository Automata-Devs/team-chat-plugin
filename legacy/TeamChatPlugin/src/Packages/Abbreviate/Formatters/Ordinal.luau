--!strict
--[[
	Ordinal
	1 -> "1st", 2 -> "2nd", 3 -> "3rd", 11 -> "11th", 112 -> "112th", 1000 -> "1,000th"
	Options: Separator (set to "" to disable grouping)
]]

local Utils = require(script.Parent.Parent.Utils)
local Types = require(script.Parent.Parent.Types)

local function ordinalSuffix(n: number): string
	local lastTwo = n % 100
	if lastTwo >= 11 and lastTwo <= 13 then
		return "th"
	end

	local last = n % 10
	if last == 1 then
		return "st"
	elseif last == 2 then
		return "nd"
	elseif last == 3 then
		return "rd"
	end
	return "th"
end

return function(value: number, options: Types.Options): string
	local valid, magnitude, sign = Utils.Sanitize(value)
	if not valid then
		return options.Fallback or Utils.DEFAULT_FALLBACK
	end
	if magnitude == math.huge then
		return Utils.Wrap(sign .. (options.InfinityText or Utils.DEFAULT_INFINITY), options)
	end

	local whole = math.floor(magnitude)
	local integerText = string.format("%.0f", whole)
	local grouped = Utils.GroupDigits(integerText, options.Separator)

	return Utils.Wrap(sign .. grouped .. ordinalSuffix(whole), options)
end