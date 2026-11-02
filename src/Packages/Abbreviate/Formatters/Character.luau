--!strict
--[[
	Character
	1500 -> "1k", 1500000 -> "1M"
	Options: Decimals (default 0), TrimZeros (default true), Rounding (default "Floor"),
	         DecimalMark, Prefix, Postfix, Fallback, InfinityText
]]

local Utils = require(script.Parent.Parent.Utils)
local Suffixes = require(script.Parent.Parent.Suffixes)
local Types = require(script.Parent.Parent.Types)

return function(value: number, options: Types.Options): string
	local valid, magnitude, sign = Utils.Sanitize(value)
	if not valid then
		return options.Fallback or Utils.DEFAULT_FALLBACK
	end

	local infinity = options.InfinityText or Utils.DEFAULT_INFINITY
	if magnitude == math.huge then
		return Utils.Wrap(sign .. infinity, options)
	end

	local decimals = math.clamp(math.floor(options.Decimals or 0), 0, 10)
	local rounding = options.Rounding or "Floor"
	local trim = options.TrimZeros ~= false

	local scaled, tier = Utils.Scale(magnitude, decimals, Suffixes.MaxTier, rounding)
	if tier > Suffixes.MaxTier then
		return Utils.Wrap(sign .. infinity, options)
	end

	local text = Utils.Fixed(Utils.RoundTo(scaled, decimals, rounding), decimals)
	if trim then
		text = Utils.TrimZeros(text)
	end
	text = Utils.ApplyDecimalMark(text, options.DecimalMark)

	return Utils.Wrap(sign .. text .. Suffixes.Short[tier + 1], options)
end