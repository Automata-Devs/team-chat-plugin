--!strict
--[[
	Abbreviate
	A modular number formatting library.

	Structure (children of this module):
		Types       - exported type definitions
		Suffixes    - suffix tables (short and long names)
		Utils       - shared math and string helpers
		Formatters  - Folder; each child ModuleScript is one format style

	Usage:
		local Abbreviate = require(path.to.Abbreviate)

		Abbreviate.Format(1234567, "Character")                       --> "1M"
		Abbreviate.Format(1234567, "CharacterDecimals", { Decimals = 1 }) --> "1.2M"
		Abbreviate.Format(1234567, "Comma")                           --> "1,234,567"
		Abbreviate.Format(1234567, "Scientific")                      --> "1.23e6"
		Abbreviate.Format(3725, "Time")                               --> "1h 2m 5s"

		-- Shorthand: every formatter is also callable as a method
		Abbreviate.Character(1500)      --> "1k"
		Abbreviate.Comma(1500)          --> "1,500"

		-- Reverse
		Abbreviate.Parse("1.5M")        --> 1500000

		-- Custom formatters
		Abbreviate.Register("Shout", function(n, options)
			return tostring(n) .. "!!!"
		end)
]]

local Types = require(script.Types)
local Utils = require(script.Utils)
local Suffixes = require(script.Suffixes)

export type Options = Types.Options
export type Formatter = Types.Formatter

local DEFAULT_MODE = "Character"

----------------------------------------------------------------------
-- Formatter registry
----------------------------------------------------------------------

local formatters: { [string]: Formatter } = {}

local function register(name: string, formatter: Formatter)
	assert(type(name) == "string" and #name > 0, "[Abbreviate] Formatter name must be a non-empty string")
	assert(type(formatter) == "function", "[Abbreviate] Formatter must be a function")
	formatters[name] = formatter
end

-- Auto-load every ModuleScript inside the Formatters folder.
do
	local folder = script:FindFirstChild("Formatters")
	assert(folder, "[Abbreviate] Missing 'Formatters' folder under the main module")

	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if ok and type(result) == "function" then
				register(child.Name, result :: Formatter)
			else
				warn(`[Abbreviate] Failed to load formatter "{child.Name}": {tostring(result)}`)
			end
		end
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

local Abbreviate = {}

Abbreviate.Suffixes = Suffixes.Short
Abbreviate.LongNames = Suffixes.Long

--- Formats a number using the named style.
function Abbreviate.Format(value: number, mode: string?, options: Options?): string
	local name = mode or DEFAULT_MODE
	local formatter = formatters[name]

	if not formatter then
		warn(`[Abbreviate] Unknown mode "{name}", falling back to "{DEFAULT_MODE}"`)
		formatter = formatters[DEFAULT_MODE]
	end

	return formatter(value, options or {})
end

--- Registers (or overrides) a formatter.
function Abbreviate.Register(name: string, formatter: Formatter)
	register(name, formatter)
end

--- Returns a sorted list of every available mode name.
function Abbreviate.GetModes(): { string }
	local modes = {}
	for name in formatters do
		table.insert(modes, name)
	end
	table.sort(modes)
	return modes
end

--- Returns true if a mode exists.
function Abbreviate.HasMode(name: string): boolean
	return formatters[name] ~= nil
end

--- Converts a short-suffix string ("1.5M", "2,500", "3e6") back to a number.
function Abbreviate.Parse(text: string): number?
	return Utils.Parse(text, Suffixes.Short)
end

--- Formats many values at once with the same settings.
function Abbreviate.FormatMany(values: { number }, mode: string?, options: Options?): { string }
	local out = table.create(#values)
	for index, value in values do
		out[index] = Abbreviate.Format(value, mode, options)
	end
	return out
end

-- Dynamic shorthand: Abbreviate.Comma(n, options), Abbreviate.Time(n), ...
setmetatable(Abbreviate, {
	__index = function(_, key)
		local formatter = formatters[key]
		if formatter then
			return function(value: number, options: Options?): string
				return formatter(value, options or {})
			end
		end
		return nil
	end,
})

return Abbreviate