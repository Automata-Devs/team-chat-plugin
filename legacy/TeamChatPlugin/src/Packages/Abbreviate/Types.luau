--!strict
--[[
	Types
	Shared type definitions. Contains no runtime logic.
]]

export type Options = {
	-- Number of decimal places (Character, CharacterDecimals, Scientific, ...)
	Decimals: number?,
	-- Trim trailing zeros ("1.50" -> "1.5"). Default depends on the formatter.
	TrimZeros: boolean?,
	-- "Floor" | "Round" | "Ceil". Default "Floor" for suffix styles.
	Rounding: string?,
	-- Separator used by Comma styles. Default ","
	Separator: string?,
	-- Decimal mark. Default "."
	DecimalMark: string?,
	-- Value at which CommaAndCharacter switches to suffixes. Default 1e6
	Threshold: number?,
	-- Prefix / suffix wrapped around the final string (e.g. "$", " coins")
	Prefix: string?,
	Postfix: string?,
	-- Text returned for NaN / non-number input. Default "0"
	Fallback: string?,
	-- Text used for values beyond the suffix table. Default "∞"
	InfinityText: string?,
	-- Time formatter: maximum number of units shown. Default 3
	MaxUnits: number?,
	-- Time formatter: "Short" ("1h 2m") | "Clock" ("01:02:05") | "Long" ("1 hour 2 minutes")
	TimeStyle: string?,
	-- Bytes formatter: "Binary" (1024) | "Decimal" (1000). Default "Binary"
	ByteBase: string?,
	-- Percent formatter: treat the input as a 0-1 ratio. Default true
	Ratio: boolean?,
	-- Full formatter: use "and" style spacing. Default false
	Plural: boolean?,
}

export type Formatter = (value: number, options: Options) -> string

return {}