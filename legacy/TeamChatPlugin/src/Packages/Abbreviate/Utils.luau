--!strict
--[[
	Utils
	Pure helper functions shared by every formatter.
	Nothing in here holds state.
]]

local Types = require(script.Parent.Types)

type Options = Types.Options

local Utils = {}

Utils.DEFAULT_FALLBACK = "0"
Utils.DEFAULT_INFINITY = "∞"

----------------------------------------------------------------------
-- Input handling
----------------------------------------------------------------------

--- Splits a value into (isValid, magnitude, sign).
--- Non-numbers and NaN are invalid.
function Utils.Sanitize(value: any): (boolean, number, string)
	if type(value) ~= "number" or value ~= value then
		return false, 0, ""
	end
	if value < 0 then
		return true, -value, "-"
	end
	return true, value, ""
end

--- Wraps the final string with Prefix / Postfix from the options.
function Utils.Wrap(text: string, options: Options): string
	return (options.Prefix or "") .. text .. (options.Postfix or "")
end

----------------------------------------------------------------------
-- Rounding
----------------------------------------------------------------------

--- Rounds `value` to `decimals` places using the named mode.
function Utils.RoundTo(value: number, decimals: number, mode: string?): number
	local factor = 10 ^ decimals
	local scaled = value * factor

	if mode == "Round" then
		return math.floor(scaled + 0.5) / factor
	elseif mode == "Ceil" then
		return math.ceil(scaled) / factor
	end

	-- Floor. A tiny epsilon prevents 0.29 * 100 = 28.999999 from flooring wrong.
	return math.floor(scaled + 1e-9) / factor
end

--- Formats with fixed decimals using %f (no scientific notation).
function Utils.Fixed(value: number, decimals: number): string
	return string.format("%." .. decimals .. "f", value)
end

--- Removes trailing zeros: "1.50" -> "1.5", "2.00" -> "2".
function Utils.TrimZeros(text: string): string
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

--- Swaps the decimal mark if the caller wants something other than ".".
function Utils.ApplyDecimalMark(text: string, mark: string?): string
	if mark and mark ~= "." then
		return (string.gsub(text, "%.", mark))
	end
	return text
end

----------------------------------------------------------------------
-- Tier detection
----------------------------------------------------------------------

--- Returns the base-1000 tier of a positive number (0 for < 1000).
--- Corrects floating point drift around exact powers of 1000.
function Utils.GetTier(value: number): number
	if value < 1000 then
		return 0
	end

	local tier = math.floor(math.log10(value) / 3)

	if value >= 10 ^ ((tier + 1) * 3) then
		tier += 1
	elseif value < 10 ^ (tier * 3) then
		tier -= 1
	end

	return math.max(tier, 0)
end

--- Scales a value into its tier and resolves rounding carry:
--- 999.999k at 2 decimals would round to 1000.00k, so it is promoted to 1.00M.
--- Returns (scaledValue, tier). Tier may exceed maxTier; callers handle that.
function Utils.Scale(value: number, decimals: number, maxTier: number, mode: string?): (number, number)
	local tier = Utils.GetTier(value)
	local scaled = value / 10 ^ (tier * 3)

	if tier <= maxTier and Utils.RoundTo(scaled, decimals, mode) >= 1000 then
		tier += 1
		scaled = value / 10 ^ (tier * 3)
	end

	return scaled, tier
end

----------------------------------------------------------------------
-- Comma grouping
----------------------------------------------------------------------

--- Inserts a separator every three digits of an integer string.
function Utils.GroupDigits(integerText: string, separator: string?): string
	local sep = separator or ","
	local sign = ""

	if string.sub(integerText, 1, 1) == "-" then
		sign = "-"
		integerText = string.sub(integerText, 2)
	end

	local length = #integerText
	if length <= 3 then
		return sign .. integerText
	end

	local parts = {}
	local first = length % 3
	if first > 0 then
		table.insert(parts, string.sub(integerText, 1, first))
	end
	for index = first + 1, length, 3 do
		table.insert(parts, string.sub(integerText, index, index + 2))
	end

	return sign .. table.concat(parts, sep)
end

----------------------------------------------------------------------
-- Parsing
----------------------------------------------------------------------

--- Parses "1.5M", "2,500", "3e6", "-4.2k" into a number.
--- Suffix matching is case sensitive first, then case insensitive.
function Utils.Parse(text: string, suffixes: { string }): number?
	if type(text) ~= "string" then
		return nil
	end

	local cleaned = string.gsub(text, "[%s,]", "")
	if cleaned == "" then
		return nil
	end

	-- Plain numbers and scientific notation are handled by tonumber directly.
	local direct = tonumber(cleaned)
	if direct then
		return direct
	end

	local numberPart, suffixPart = string.match(cleaned, "^(-?%d*%.?%d+)(%a+)$")
	if not numberPart or not suffixPart then
		return nil
	end

	local base = tonumber(numberPart)
	if not base then
		return nil
	end

	-- Exact match first
	for index, suffix in suffixes do
		if suffix ~= "" and suffix == suffixPart then
			return base * 10 ^ ((index - 1) * 3)
		end
	end

	-- Case-insensitive fallback ("K" -> "k")
	local lowered = string.lower(suffixPart)
	for index, suffix in suffixes do
		if suffix ~= "" and string.lower(suffix) == lowered then
			return base * 10 ^ ((index - 1) * 3)
		end
	end

	return nil
end

return Utils