--!strict
--[[
	Suffixes
	Short suffixes and long names, indexed by tier.
	Tier 0 = 10^0, tier 1 = 10^3 (k), tier 2 = 10^6 (M), ...

	Short list is 1-indexed: Short[tier + 1].
]]

local SHORT: { string } = {
	"",     -- 10^0
	"k",    -- 10^3
	"M",    -- 10^6
	"B",    -- 10^9
	"T",    -- 10^12
	"Qa",   -- 10^15
	"Qn",   -- 10^18
	"Sx",   -- 10^21
	"Sp",   -- 10^24
	"Oc",   -- 10^27
	"N",    -- 10^30
	"Dc",   -- 10^33
	"Ud",   -- 10^36
	"DD",   -- 10^39
	"Td",   -- 10^42
	"Qua",  -- 10^45
	"Qui",  -- 10^48
	"Sxd",  -- 10^51
	"Spd",  -- 10^54
	"Ocd",  -- 10^57
	"Nod",  -- 10^60
	"Vgn",  -- 10^63
	"UVg",  -- 10^66
	"DVg",  -- 10^69
	"TVg",  -- 10^72
	"QuVg", -- 10^75
	"QiVg", -- 10^78
	"SxVg", -- 10^81
	"SpVg", -- 10^84
	"OcVg", -- 10^87
	"NoVg", -- 10^90
	"TGN",  -- 10^93
	"UTg",  -- 10^96
	"DTg",  -- 10^99
	"TTg",  -- 10^102
	"QuTg", -- 10^105
	"QiTg", -- 10^108
	"SxTg", -- 10^111
	"SpTg", -- 10^114
	"OcTg", -- 10^117
	"NoAG", -- 10^120
	"UnAG", -- 10^123
	"DuAG", -- 10^126
	"TeAG", -- 10^129
	"QdAG", -- 10^132
	"QnAG", -- 10^135
	"SxAG", -- 10^138
	"SpAG", -- 10^141
	"OcAG", -- 10^144
	"NvAG", -- 10^147
	"CT",   -- 10^150
	"TaCG", -- 10^153
	"AnTG", -- 10^156
	"YX",   -- 10^159
	"YaZQ", -- 10^162
	"YXZ",  -- 10^165
	"NoEV", -- 10^168
	"KoTG", -- 10^171
	"TrAG", -- 10^174
}

-- Generated tail: e177, e180, ... e198
do
	local exponent = #SHORT * 3
	while exponent <= 198 do
		table.insert(SHORT, "e" .. tostring(exponent))
		exponent += 3
	end
end

-- Long names used by the "Full" formatter. Tiers beyond this list fall back
-- to the short suffix.
local LONG: { string } = {
	"",
	"Thousand",
	"Million",
	"Billion",
	"Trillion",
	"Quadrillion",
	"Quintillion",
	"Sextillion",
	"Septillion",
	"Octillion",
	"Nonillion",
	"Decillion",
	"Undecillion",
	"Duodecillion",
	"Tredecillion",
	"Quattuordecillion",
	"Quindecillion",
	"Sexdecillion",
	"Septendecillion",
	"Octodecillion",
	"Novemdecillion",
	"Vigintillion",
}

return table.freeze({
	Short = table.freeze(SHORT),
	Long = table.freeze(LONG),
	MaxTier = #SHORT - 1,
})