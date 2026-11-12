--[[
	Theme

	Centralized color palettes, fonts, and layout constants for the
	TeamChat plugin UI. Detects Studio's light/dark mode automatically.
]]

local Theme = {}

-- Color palettes for each Studio theme mode, from Roblox's Foundation design
-- tokens (the ones roblox.com and the Roblox app use).
Theme.PALETTES = {
	-- Roblox's Foundation dark theme: blue-tinted near-blacks (surface 0-300),
	-- #F7F7F8 / #D5D7DD / #BCBEC8 text, Roblox blue #335FFF. Its see-through
	-- overlays (a #D0D9FB tint at 4-16%) are baked onto the surface they sit on.
	Dark = {
		scrollBack = Color3.fromRGB(25, 26, 31), -- surface 100: the chat
		inputFrame = Color3.fromRGB(18, 18, 21), -- surface 0: header, sidebar and composer bar
		replyBarBack = Color3.fromRGB(32, 34, 39), -- surface 200
		inputBox = Color3.fromRGB(41, 42, 49), -- standard action: composer box, chips, icon buttons
		sendButton = Color3.fromRGB(51, 95, 255), -- emphasis: Roblox blue, primary actions and accents
		sendButtonInactive = Color3.fromRGB(31, 49, 115), -- soft emphasis
		timestamp = Color3.fromRGB(188, 190, 200), -- muted text
		messageText = Color3.fromRGB(247, 247, 248), -- emphasis text
		sendButtonText = Color3.fromRGB(247, 247, 248),
		divider = Color3.fromRGB(40, 41, 49), -- muted stroke
		scrollBar = Color3.fromRGB(98, 102, 119),
		textBoxText = Color3.fromRGB(247, 247, 248),
		placeholder = Color3.fromRGB(129, 131, 140),
		attachButton = Color3.fromRGB(41, 42, 49),
		attachIcon = Color3.fromRGB(213, 215, 221), -- default text
		imageBorder = Color3.fromRGB(47, 49, 57), -- default stroke
		previewBorder = Color3.fromRGB(47, 49, 57),
		loadingText = Color3.fromRGB(188, 190, 200),
		menuBack = Color3.fromRGB(32, 34, 39), -- surface 200: menus, popovers, tooltips
		menuBorder = Color3.fromRGB(53, 56, 64),
		menuItemHover = Color3.fromRGB(46, 49, 56), -- hover state on surface 200
		menuItemText = Color3.fromRGB(213, 215, 221),
		pollBar = Color3.fromRGB(47, 49, 57),
		pollBarVoted = Color3.fromRGB(51, 95, 255),
		pollBarText = Color3.fromRGB(247, 247, 248),
		emptyTitle = Color3.fromRGB(213, 215, 221),
		emptySubtitle = Color3.fromRGB(188, 190, 200),
		dialogBack = Color3.fromRGB(25, 26, 31), -- surface 100
		dialogBorder = Color3.fromRGB(47, 49, 57),
		dialogButton = Color3.fromRGB(51, 95, 255),
		dialogButtonText = Color3.fromRGB(247, 247, 248),
		dialogSecondary = Color3.fromRGB(39, 41, 48), -- surface 300: setting cards and secondary buttons
		navBack = Color3.fromRGB(18, 18, 21), -- the Settings window's tab column
		navSelected = Color3.fromRGB(41, 42, 49), -- its open tab
		dialogInput = Color3.fromRGB(18, 18, 21),
		dialogInputText = Color3.fromRGB(247, 247, 248),
		danger = Color3.fromRGB(240, 68, 51), -- alert actions (Delete)
		success = Color3.fromRGB(57, 197, 130), -- changelog "Added"
		warning = Color3.fromRGB(242, 186, 42), -- changelog "Fixed"
		-- @mentions: text under a see-through rounded tint (UI/Text/MentionPills), so
		-- the text is brighter than it ends up looking (Roblox's soft emphasis)
		mentionText = Color3.fromRGB(235, 241, 255),
		mentionBack = Color3.fromRGB(51, 95, 255),
		mentionRow = Color3.fromRGB(242, 186, 42), -- messages that mention you
		-- Code blocks and `inline code`: a box a shade off the chat, with a border
		codeBack = Color3.fromRGB(32, 34, 39),
		codeBorder = Color3.fromRGB(53, 56, 64),
		codeText = Color3.fromRGB(213, 215, 221),
		quoteBar = Color3.fromRGB(98, 102, 119), -- the bar left of a > quote
		tint = Color3.fromRGB(208, 217, 251), -- hover / press overlays (Theme.STATE)
	},
	-- Roblox's Foundation light theme: white and #F7F7F8 surfaces, #202227 /
	-- #494D5A / #6A6F81 text, a #1B254B tint for overlays and strokes.
	Light = {
		scrollBack = Color3.fromRGB(255, 255, 255), -- surface 0: the chat
		inputFrame = Color3.fromRGB(247, 247, 248), -- surface 100: header, sidebar and composer bar
		replyBarBack = Color3.fromRGB(237, 238, 241),
		inputBox = Color3.fromRGB(229, 230, 234), -- standard action: composer box, chips, icon buttons
		sendButton = Color3.fromRGB(51, 95, 255), -- emphasis: Roblox blue, primary actions and accents
		sendButtonInactive = Color3.fromRGB(188, 201, 250), -- soft emphasis
		timestamp = Color3.fromRGB(106, 111, 129), -- muted text
		messageText = Color3.fromRGB(32, 34, 39), -- emphasis text
		sendButtonText = Color3.fromRGB(247, 247, 248),
		divider = Color3.fromRGB(237, 238, 241), -- muted stroke
		scrollBar = Color3.fromRGB(141, 146, 165),
		textBoxText = Color3.fromRGB(32, 34, 39),
		placeholder = Color3.fromRGB(134, 138, 153),
		attachButton = Color3.fromRGB(229, 230, 234),
		attachIcon = Color3.fromRGB(73, 77, 90), -- default text
		imageBorder = Color3.fromRGB(228, 229, 233), -- default stroke
		previewBorder = Color3.fromRGB(228, 229, 233),
		loadingText = Color3.fromRGB(106, 111, 129),
		menuBack = Color3.fromRGB(255, 255, 255), -- menus, popovers, tooltips
		menuBorder = Color3.fromRGB(228, 229, 233),
		menuItemHover = Color3.fromRGB(237, 238, 241), -- hover state on white
		menuItemText = Color3.fromRGB(73, 77, 90),
		pollBar = Color3.fromRGB(228, 229, 233),
		pollBarVoted = Color3.fromRGB(51, 95, 255),
		pollBarText = Color3.fromRGB(32, 34, 39),
		emptyTitle = Color3.fromRGB(73, 77, 90),
		emptySubtitle = Color3.fromRGB(106, 111, 129),
		dialogBack = Color3.fromRGB(255, 255, 255),
		dialogBorder = Color3.fromRGB(228, 229, 233),
		dialogButton = Color3.fromRGB(51, 95, 255),
		dialogButtonText = Color3.fromRGB(247, 247, 248),
		dialogSecondary = Color3.fromRGB(238, 239, 241), -- setting cards and secondary buttons
		navBack = Color3.fromRGB(247, 247, 248), -- the Settings window's tab column
		navSelected = Color3.fromRGB(229, 230, 234), -- its open tab
		dialogInput = Color3.fromRGB(255, 255, 255),
		dialogInputText = Color3.fromRGB(32, 34, 39),
		danger = Color3.fromRGB(217, 28, 21), -- alert actions (Delete)
		success = Color3.fromRGB(2, 136, 73), -- changelog "Added" (darker than Roblox's, to read on white)
		warning = Color3.fromRGB(194, 121, 0), -- changelog "Fixed"
		mentionText = Color3.fromRGB(0, 20, 92), -- @mentions, under the tint (UI/Text/MentionPills)
		mentionBack = Color3.fromRGB(51, 95, 255),
		mentionRow = Color3.fromRGB(242, 186, 42), -- messages that mention you
		codeBack = Color3.fromRGB(247, 247, 248),
		codeBorder = Color3.fromRGB(228, 229, 233),
		codeText = Color3.fromRGB(32, 34, 39),
		quoteBar = Color3.fromRGB(164, 168, 183),
		tint = Color3.fromRGB(27, 37, 75), -- hover / press overlays (Theme.STATE)
	},
}

-- Shared font and layout constants.
Theme.FONT = Enum.Font.BuilderSans

-- Roblox's Builder type family: Sans for UI text, Extended for display
-- titles, Mono for numbers, times and commands.
Theme.FONT_FAMILIES = {
	sans = "rbxasset://fonts/families/BuilderSans.json",
	extended = "rbxasset://fonts/families/BuilderExtended.json",
	mono = "rbxasset://fonts/families/BuilderMono.json",
}

-- Font roles, applied with label.FontFace = Theme.FONTS.<role>.
-- Message lines stay on Theme.FONT: UI/Text/TextLayout measures them (links,
-- @mentions, markdown) in the label's own font.
Theme.FONTS = {
	body = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Regular),
	medium = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Medium),
	semibold = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.SemiBold),
	bold = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Bold),
	italic = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Regular, Enum.FontStyle.Italic),
	-- Roblox's product UI sets titles and headings in Builder Sans Bold too
	display = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Bold), -- dialog / empty-state titles
	heading = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Bold), -- poll questions, card labels
	mono = Font.new(Theme.FONT_FAMILIES.mono, Enum.FontWeight.Regular), -- times, counts, file types, /commands
}

--[=[
	Opening RichText tag for a font family, e.g. Theme.richFont("mono") .. text .. "</font>".
	Optional weight is a RichText weight name ("medium", "semibold", "bold").
]=]
function Theme.richFont(family: string, weight: string?): string
	local weightAttr = weight and string.format(' weight="%s"', weight) or ""
	return string.format('<font family="%s"%s>', Theme.FONT_FAMILIES[family], weightAttr)
end
Theme.MAX_IMAGE_HEIGHT = 160
-- Underlined links in messages and link previews: one blue that reads on both
-- themes, between Roblox's dark (#528BFF) and light (#1446FF) link colours
Theme.LINK_COLOR = Color3.fromRGB(64, 120, 255)
Theme.MENTION_TRANSPARENCY = 0.65 -- the rounded tint over an @mention (Roblox's soft emphasis)
Theme.MENTION_ROW_TRANSPARENCY = 0.9 -- the tint on a message that mentions you (its left bar is solid)
Theme.IMAGE_FILTER = { "png", "jpg", "jpeg", "bmp" }
Theme.FILE_EXTENSIONS = {
	mp3 = "Audio",
	wav = "Audio",
	ogg = "Audio",
	mp4 = "Video",
	webm = "Video",
	gif = "Decal",
	obj = "Mesh",
	fbx = "Mesh",
	rbxm = "Model",
	rbxmx = "Model",
	lua = "Script",
	luau = "Script",
	txt = "Text",
	json = "Text",
	xml = "Text",
	csv = "Text",
}

-- Roblox Foundation's corner radii (on a 4px grid): xsmall for hairline
-- marks, small for tags and badges, medium for buttons, inputs, cards and
-- menus, large for dialogs and panels, circle for avatars, chips and icon
-- buttons.
Theme.RADIUS = {
	xsmall = UDim.new(0, 2),
	small = UDim.new(0, 4),
	medium = UDim.new(0, 8),
	large = UDim.new(0, 16),
	circle = UDim.new(1, 0),
}

-- See-through overlays of the palette's `tint`, as BackgroundTransparency:
-- STATE for hover and press layers, STROKE for borders and dividers.
Theme.STATE = { hover = 0.92, press = 0.88 }
Theme.STROKE = { muted = 0.92, default = 0.88, emphasis = 0.84 }

-- Layout constants
Theme.INPUT_HEIGHT = 49
Theme.PREVIEW_HEIGHT = 36
Theme.MENU_WIDTH = 160
Theme.MENU_ITEM_HEIGHT = 34
Theme.MAX_POLL_OPTIONS = 10

--[=[
	Detects the current Roblox Studio theme.
	Returns string "Dark" or "Light"
]=]
function Theme.detect(): string
	local ok, theme = pcall(function()
		return settings().Studio.Theme
	end)

	if ok and theme then
		local themeStr = tostring(theme)
		if string.find(string.lower(themeStr), "light") then
			return "Light"
		end
	end
	return "Dark"
end

--[=[
	Returns the color palette for the current Studio theme.
	Returns table
]=]
function Theme.getColors()
	return Theme.PALETTES[Theme.detect()]
end

--[=[
	Converts a Color3 to a hex string for use in RichText <font color> tags.
]=]
function Theme.toHex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	)
end

return Theme
