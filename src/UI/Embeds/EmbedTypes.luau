--!nonstrict
--[[
	EmbedTypes

	Shared type definitions for the embed system. Contains no runtime logic.

	A provider is a ModuleScript placed in UI/Embeds/Providers that returns a
	table with this shape. EmbedManager discovers providers automatically.
]]

export type ThemeColors = { [string]: any }

export type EmbedContext = {
	plugin: Plugin?,
}

export type EmbedProvider = {
	-- Unique name, stored on the embed so it can be recolored later
	Name: string,
	-- Higher priority providers are tried first (default 0). The generic
	-- link provider uses 0 and matches everything, so specific providers
	-- should use a value above 0.
	Priority: number?,
	-- Return true if this provider can render the URL
	matches: (url: string) -> boolean,
	-- Return the root GuiObject of the embed (use CardFrame.create)
	build: (url: string, theme: ThemeColors, ctx: EmbedContext) -> GuiObject,
	-- Re-apply theme colors to an existing embed built by this provider
	recolor: (embed: GuiObject, theme: ThemeColors) -> (),
}

return {}
