--!strict
--[[
	Comma
	1234567 -> "1,234,567"
	Options: Separator, Prefix, Postfix, Fallback
]]

local Utils = require(script.Parent.Parent.Utils)
local Types = require(script.Parent.Parent.Types)

return function(value: number, options: Types.Options): string
	local valid, magnitude, sign = Utils.Sanitize(value)
	if not valid then
		return options.Fallback or Utils.DEFAULT_FALLBACK
	end
	if magnitude == math.huge then
		return Utils.Wrap(sign .. (options.InfinityText or Utils.DEFAULT_INFINITY), options)
	end

	local integerText = string.format("%.0f", math.floor(magnitude))
	local grouped = Utils.GroupDigits(integerText, options.Separator)

	return Utils.Wrap(sign .. grouped, options)
end