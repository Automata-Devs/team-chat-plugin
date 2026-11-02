--[[
	GetNameColor
	ModuleScript (e.g. ReplicatedStorage.GetNameColor)

	Reproduces Roblox's chat name-color algorithm:
	  1. Turn the username into a number (GetNameValue).
	  2. value % 8 + 1 picks one of 8 palette colors.

	Based on the DevForum post "Your Name Color in Chat - History and How It Works"
	(GFink) and the web tools by RyloRiz / robloxnamecolor.com.

	Usage:
		local getNameColor = require(game.ReplicatedStorage.GetNameColor)
		part.Color = getNameColor("GFink")      -- latest palette (v3)
		part.Color = getNameColor("GFink", 1)   -- 2006 palette
		part.Color = getNameColor("GFink", 2)   -- 2015 palette

	Palette versions:
		1 = 2006 (darker red / blue / green)               -- see NOTE below
		2 = 2015 (brighter red / blue / green, Bright violet)
		3 = 2023 (same as 2, but Bright violet -> Alder; TextChatService)
]]

local PALETTE_VERSIONS = 3

-- Palettes are built lazily so the module can be required before BrickColor lookups are needed.
local function buildPalettes(): { [number]: { Color3 } }
	-- Colors 4-8 are shared by every version (except slot 4, Bright violet vs Alder).
	local orange = BrickColor.new("Bright orange").Color
	local yellow = BrickColor.new("Bright yellow").Color
	local reddishViolet = BrickColor.new("Light reddish violet").Color
	local brickYellow = BrickColor.new("Brick yellow").Color
	local brightViolet = BrickColor.new("Bright violet").Color
	local alder = BrickColor.new("Alder").Color

	return {
		-- v1 (2006). NOTE: these three are a best-effort reconstruction of the old
		-- darker red/blue/green (BrickColors "Bright red", "Bright blue", "Dark green").
		-- The DevForum post only shows them as an image; verify against the
		-- "Versioned-GetNameColor" module (library asset 15363536532) if you need exactness.
		[1] = {
			Color3.fromRGB(196, 40, 28), -- Bright red
			Color3.fromRGB(13, 105, 172), -- Bright blue
			Color3.fromRGB(40, 127, 71), -- Dark green
			brightViolet,
			orange,
			yellow,
			reddishViolet,
			brickYellow,
		},

		-- v2 (2015 - 2023)
		[2] = {
			Color3.fromRGB(253, 41, 67), -- Bright red
			Color3.fromRGB(1, 162, 255), -- Bright blue
			Color3.fromRGB(2, 184, 87), -- Earth green
			brightViolet,
			orange,
			yellow,
			reddishViolet,
			brickYellow,
		},

		-- v3 (2023 - now, TextChatService / ExperienceChat)
		[3] = {
			Color3.fromRGB(253, 41, 67), -- Bright red
			Color3.fromRGB(1, 162, 255), -- Bright blue
			Color3.fromRGB(2, 184, 87), -- Earth green
			alder, -- replaced Bright violet for better contrast
			orange,
			yellow,
			reddishViolet,
			brickYellow,
		},
	}
end

local palettes: { [number]: { Color3 } }? = nil

--- The "seed" number for a name. Exposed separately because it is the heart of the algorithm.
local function getNameValue(name: string): number
	local length = #name
	local value = 0

	for index = 1, length do
		local cValue = string.byte(name, index)

		local reverseIndex = length - index + 1
		if length % 2 == 1 then
			reverseIndex -= 1
		end

		if reverseIndex % 4 >= 2 then
			cValue = -cValue
		end

		value += cValue
	end

	return value
end

--- 1-based palette index (1..8) for a name.
local function getNameIndex(name: string): number
	-- Lua's % is a floored modulo, so negative sums still land in 0..7.
	return (getNameValue(name) % 8) + 1
end

local function getNameColor(name: string, version: number?): Color3
	local v = version or PALETTE_VERSIONS
	assert(v >= 1 and v <= PALETTE_VERSIONS and v % 1 == 0, "version must be 1, 2 or 3")

	if palettes == nil then
		palettes = buildPalettes()
	end

	return (palettes :: any)[v][getNameIndex(name)]
end

return setmetatable({
	getNameValue = getNameValue,
	getNameIndex = getNameIndex,
	getNameColor = getNameColor,
	LATEST_VERSION = PALETTE_VERSIONS,
}, {
	-- allow `require(module)("Name")` as well as `require(module).getNameColor("Name")`
	__call = function(_, name: string, version: number?)
		return getNameColor(name, version)
	end,
})