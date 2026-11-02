--!strict
--[[
	Scientific
	1234567 -> "1.23e6",  0.00042 -> "4.2e-4"
	Options: Decimals (default 2), TrimZeros (default true), Rounding, ...
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
	if magnitude == 0 then
		return Utils.Wrap("0", options)
	end

	local decimals = math.clamp(math.floor(options.Decimals or 2), 0, 10)
	local rounding = options.Rounding or "Floor"
	local trim = options.TrimZeros ~= false

	local exponent = math.floor(math.log10(magnitude))
	local mantissa = magnitude / 10 ^ exponent

	-- Fix drift at exact powers of ten
	if mantissa >= 10 then
		mantissa /= 10
		exponent += 1
	elseif mantissa < 1 then
		mantissa *= 10
		exponent -= 1
	end

	-- Rounding carry: 9.999 -> 10.00 becomes 1.00e(n+1)
	mantissa = Utils.RoundTo(mantissa, decimals, rounding)
	if mantissa >= 10 then
		mantissa /= 10
		exponent += 1
	end

	local text = Utils.Fixed(mantissa, decimals)
	if trim then
		text = Utils.TrimZeros(text)
	end
	text = Utils.ApplyDecimalMark(text, options.DecimalMark)

	return Utils.Wrap(`{sign}{text}e{exponent}`, options)
end