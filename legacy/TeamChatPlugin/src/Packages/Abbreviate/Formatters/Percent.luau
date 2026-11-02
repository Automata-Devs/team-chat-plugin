--!strict
--[[
	Percent
	0.256 -> "25.6%"  (Ratio = true, default)
	25.6  -> "25.6%"  (Ratio = false)
	Options: Ratio, Decimals (default 1), TrimZeros (default true), Rounding, ...
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

	local decimals = math.clamp(math.floor(options.Decimals or 1), 0, 10)
	local rounding = options.Rounding or "Floor"
	local trim = options.TrimZeros ~= false

	local percent = if options.Ratio == false then magnitude else magnitude * 100

	local text = Utils.Fixed(Utils.RoundTo(percent, decimals, rounding), decimals)
	if trim then
		text = Utils.TrimZeros(text)
	end
	text = Utils.ApplyDecimalMark(text, options.DecimalMark)

	return Utils.Wrap(`{sign}{text}%`, options)
end