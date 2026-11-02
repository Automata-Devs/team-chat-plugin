--!strict
--[[
	Bytes
	1536 -> "1.5 KB",  5242880 -> "5 MB"
	Options: ByteBase ("Binary" = 1024 default | "Decimal" = 1000), Decimals (default 2),
	         TrimZeros (default true), Rounding
]]

local Utils = require(script.Parent.Parent.Utils)
local Types = require(script.Parent.Parent.Types)

local UNITS = { "B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB" }

return function(value: number, options: Types.Options): string
	local valid, magnitude, sign = Utils.Sanitize(value)
	if not valid then
		return options.Fallback or Utils.DEFAULT_FALLBACK
	end
	if magnitude == math.huge then
		return Utils.Wrap(sign .. (options.InfinityText or Utils.DEFAULT_INFINITY), options)
	end

	local base = if options.ByteBase == "Decimal" then 1000 else 1024
	local decimals = math.clamp(math.floor(options.Decimals or 2), 0, 10)
	local rounding = options.Rounding or "Floor"
	local trim = options.TrimZeros ~= false

	local index = 1
	local scaled = magnitude
	while scaled >= base and index < #UNITS do
		scaled /= base
		index += 1
	end

	-- Rounding carry: 1023.999 KB -> 1024.00 KB should become 1.00 MB
	if Utils.RoundTo(scaled, decimals, rounding) >= base and index < #UNITS then
		scaled /= base
		index += 1
	end

	local text = Utils.Fixed(Utils.RoundTo(scaled, decimals, rounding), decimals)
	if trim then
		text = Utils.TrimZeros(text)
	end
	text = Utils.ApplyDecimalMark(text, options.DecimalMark)

	return Utils.Wrap(`{sign}{text} {UNITS[index]}`, options)
end