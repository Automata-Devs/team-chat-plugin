--!strict
--[[
	Roman
	4 -> "IV", 1994 -> "MCMXCIV", 3999 -> "MMMCMXCIX"
	Valid range is 1-3999. Anything else returns Fallback (default "0").
]]

local Utils = require(script.Parent.Parent.Utils)
local Types = require(script.Parent.Parent.Types)

local NUMERALS = {
	{ 1000, "M" },
	{ 900, "CM" },
	{ 500, "D" },
	{ 400, "CD" },
	{ 100, "C" },
	{ 90, "XC" },
	{ 50, "L" },
	{ 40, "XL" },
	{ 10, "X" },
	{ 9, "IX" },
	{ 5, "V" },
	{ 4, "IV" },
	{ 1, "I" },
}

return function(value: number, options: Types.Options): string
	local valid, magnitude = Utils.Sanitize(value)
	if not valid then
		return options.Fallback or Utils.DEFAULT_FALLBACK
	end

	local remaining = math.floor(magnitude)
	if remaining < 1 or remaining > 3999 then
		return options.Fallback or Utils.DEFAULT_FALLBACK
	end

	local buffer: { string } = {}
	for _, pair in NUMERALS do
		local amount, numeral = pair[1] :: number, pair[2] :: string
		while remaining >= amount do
			table.insert(buffer, numeral)
			remaining -= amount
		end
	end

	return Utils.Wrap(table.concat(buffer), options)
end