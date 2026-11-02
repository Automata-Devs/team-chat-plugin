--!strict
--[[
	CommaAndCharacter
	Below Threshold (default 1e6): comma grouped.  At or above: suffix style.
	999999 -> "999,999",  1500000 -> "1M"
	Options: Threshold plus every Comma / Character option.
]]

local Utils = require(script.Parent.Parent.Utils)
local Types = require(script.Parent.Parent.Types)

local Comma = require(script.Parent.Comma)
local Character = require(script.Parent.Character)

local DEFAULT_THRESHOLD = 1e6

return function(value: number, options: Types.Options): string
	local valid, magnitude = Utils.Sanitize(value)
	if not valid then
		return options.Fallback or Utils.DEFAULT_FALLBACK
	end

	if magnitude < (options.Threshold or DEFAULT_THRESHOLD) then
		return Comma(value, options)
	end
	return Character(value, options)
end