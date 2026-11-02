--!strict
--[[
	Engineering
	Like scientific, but the exponent is always a multiple of 3.
	1234567 -> "1.23e6",  12345 -> "12.3e3",  123456789 -> "123e6"
	Options: Decimals (significant decimals, default 2), TrimZeros, Rounding, ...
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
	exponent -= exponent % 3 -- snap down to a multiple of 3 (works for negatives too)

	local mantissa = magnitude / 10 ^ exponent
	if mantissa >= 1000 then
		mantissa /= 1000
		exponent += 3
	elseif mantissa < 1 then
		mantissa *= 1000
		exponent -= 3
	end

	-- Rounding carry: 999.999 -> 1000.00 becomes 1.00e(n+3)
	mantissa = Utils.RoundTo(mantissa, decimals, rounding)
	if mantissa >= 1000 then
		mantissa /= 1000
		exponent += 3
	end

	local text = Utils.Fixed(mantissa, decimals)
	if trim then
		text = Utils.TrimZeros(text)
	end
	text = Utils.ApplyDecimalMark(text, options.DecimalMark)

	return Utils.Wrap(`{sign}{text}e{exponent}`, options)
end