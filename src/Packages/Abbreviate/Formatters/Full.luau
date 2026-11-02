--!strict
--[[
	Full
	1500000 -> "1.5 Million",  2000000000 -> "2 Billion"
	Options: Decimals (default 2), TrimZeros (default true), Rounding, Plural, ...
	Tiers beyond the long-name list fall back to the short suffix.
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

	local decimals = math.clamp(math.floor(options.Decimals or 2), 0, 10)
	local rounding = options.Rounding or "Floor"
	local trim = options.TrimZeros ~= false

	local scaled, tier = Utils.Scale(magnitude, decimals, Suffixes.MaxTier, rounding)
	if tier > Suffixes.MaxTier then
		return Utils.Wrap(sign .. infinity, options)
	end

	local rounded = Utils.RoundTo(scaled, decimals, rounding)
	local text = Utils.Fixed(rounded, decimals)
	if trim then
		text = Utils.TrimZeros(text)
	end
	text = Utils.ApplyDecimalMark(text, options.DecimalMark)

	if tier == 0 then
		return Utils.Wrap(sign .. text, options)
	end

	local name = Suffixes.Long[tier + 1] or Suffixes.Short[tier + 1]
	if options.Plural and rounded ~= 1 and Suffixes.Long[tier + 1] then
		name ..= "s"
	end

	return Utils.Wrap(`{sign}{text} {name}`, options)
end