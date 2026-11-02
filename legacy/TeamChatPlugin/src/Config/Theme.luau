--!
-- Theme
-- Centralized color palettes, fonts, and layout constants for the
-- TeamChat plugin UI. Detects Studio's light/dark mode automatically.
--!

local Theme = {}

--!
-- Color palettes for each Studio theme mode.
--!
Theme.PALETTES = {
	Dark = {
		scrollBack    = Color3.fromRGB(25, 26, 31),
		inputFrame    = Color3.fromRGB(21, 21, 24),
		replyBarBack  = Color3.fromRGB(15, 15, 18),
		inputBox      = Color3.fromRGB(42, 42, 46),
		sendButton    = Color3.fromRGB(48, 88, 248),
		sendButtonInactive = Color3.fromRGB(51, 66, 125),
		timestamp     = Color3.fromRGB(150, 150, 150),
		messageText   = Color3.fromRGB(230, 230, 230),
		sendButtonText= Color3.fromRGB(255, 255, 255),
		divider       = Color3.fromRGB(50, 50, 52),
		scrollBar     = Color3.fromRGB(85, 85, 85),
		textBoxText   = Color3.fromRGB(225, 225, 225),
		placeholder   = Color3.fromRGB(125, 125, 125),
		attachButton  = Color3.fromRGB(42, 42, 46),
		attachIcon    = Color3.fromRGB(200, 200, 200),
		imageBorder   = Color3.fromRGB(60, 60, 65),
		previewBorder = Color3.fromRGB(60, 60, 65),
		loadingText   = Color3.fromRGB(180, 180, 180),
		menuBack      = Color3.fromRGB(42, 42, 46),
		menuBorder    = Color3.fromRGB(60, 60, 65),
		menuItemHover = Color3.fromRGB(55, 55, 60),
		menuItemText  = Color3.fromRGB(220, 220, 220),
		pollBar       = Color3.fromRGB(50, 50, 55),
		pollBarVoted  = Color3.fromRGB(48, 88, 248),
		pollBarText   = Color3.fromRGB(230, 230, 230),
		emptyTitle    = Color3.fromRGB(160, 160, 165),
		emptySubtitle = Color3.fromRGB(110, 110, 115),
		dialogBack    = Color3.fromRGB(35, 35, 38),
		dialogBorder  = Color3.fromRGB(60, 60, 65),
		dialogButton  = Color3.fromRGB(48, 88, 248),
		dialogButtonText = Color3.fromRGB(255, 255, 255),
		dialogSecondary = Color3.fromRGB(42, 42, 46),
		dialogInput   = Color3.fromRGB(42, 42, 46),
		dialogInputText = Color3.fromRGB(225, 225, 225),
		danger        = Color3.fromRGB(242, 87, 87), -- destructive actions (Delete)
		success       = Color3.fromRGB(67, 181, 129), -- changelog "Added"
		warning       = Color3.fromRGB(240, 168, 50), -- changelog "Fixed"
	},
	Light = {
		scrollBack    = Color3.fromRGB(250, 250, 250),
		inputFrame    = Color3.fromRGB(240, 240, 240),
		replyBarBack  = Color3.fromRGB(228, 228, 232),
		inputBox      = Color3.fromRGB(255, 255, 255),
		sendButton    = Color3.fromRGB(48, 88, 248),
		sendButtonInactive = Color3.fromRGB(51, 66, 125),
		timestamp     = Color3.fromRGB(120, 120, 120),
		messageText   = Color3.fromRGB(40, 40, 40),
		sendButtonText= Color3.fromRGB(255, 255, 255),
		divider       = Color3.fromRGB(215, 215, 215),
		scrollBar     = Color3.fromRGB(175, 175, 175),
		textBoxText   = Color3.fromRGB(40, 40, 40),
		placeholder   = Color3.fromRGB(160, 160, 160),
		attachButton  = Color3.fromRGB(255, 255, 255),
		attachIcon    = Color3.fromRGB(80, 80, 80),
		imageBorder   = Color3.fromRGB(200, 200, 200),
		previewBorder = Color3.fromRGB(200, 200, 200),
		loadingText   = Color3.fromRGB(100, 100, 100),
		menuBack      = Color3.fromRGB(255, 255, 255),
		menuBorder    = Color3.fromRGB(200, 200, 200),
		menuItemHover = Color3.fromRGB(240, 240, 240),
		menuItemText  = Color3.fromRGB(50, 50, 50),
		pollBar       = Color3.fromRGB(230, 230, 230),
		pollBarVoted  = Color3.fromRGB(48, 88, 248),
		pollBarText   = Color3.fromRGB(40, 40, 40),
		emptyTitle    = Color3.fromRGB(120, 120, 120),
		emptySubtitle = Color3.fromRGB(170, 170, 170),
		dialogBack    = Color3.fromRGB(250, 250, 250),
		dialogBorder  = Color3.fromRGB(200, 200, 200),
		dialogButton  = Color3.fromRGB(48, 88, 248),
		dialogButtonText = Color3.fromRGB(255, 255, 255),
		dialogSecondary = Color3.fromRGB(255, 255, 255),
		dialogInput   = Color3.fromRGB(255, 255, 255),
		dialogInputText = Color3.fromRGB(40, 40, 40),
		danger        = Color3.fromRGB(208, 45, 45), -- destructive actions (Delete)
		success       = Color3.fromRGB(36, 140, 90), -- changelog "Added"
		warning       = Color3.fromRGB(190, 115, 0), -- changelog "Fixed"
	},
}

--!
-- Shared font and layout constants.
--!
Theme.FONT = Enum.Font.BuilderSans

-- Roblox's Builder type family: Sans for UI text, Extended for display
-- titles, Mono for numbers, times and commands.
Theme.FONT_FAMILIES = {
	sans = "rbxasset://fonts/families/BuilderSans.json",
	extended = "rbxasset://fonts/families/BuilderExtended.json",
	mono = "rbxasset://fonts/families/BuilderMono.json",
}

--!
-- Font roles, applied with label.FontFace = Theme.FONTS.<role>.
-- Message lines stay on Theme.FONT: LinkHelper hit-tests links by
-- measuring them in a single font.
--!
Theme.FONTS = {
	body     = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Regular),
	medium   = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Medium),
	semibold = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.SemiBold),
	bold     = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Bold),
	italic   = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Regular, Enum.FontStyle.Italic),
	display  = Font.new(Theme.FONT_FAMILIES.extended, Enum.FontWeight.Bold),     -- dialog / empty-state titles
	heading  = Font.new(Theme.FONT_FAMILIES.extended, Enum.FontWeight.SemiBold), -- poll questions, card labels
	mono     = Font.new(Theme.FONT_FAMILIES.mono, Enum.FontWeight.Regular),      -- times, counts, file types, /commands
}

--!
-- Opening RichText tag for a font family, e.g. Theme.richFont("mono") .. text .. "</font>".
-- Optional weight is a RichText weight name ("medium", "semibold", "bold").
--!
function Theme.richFont(family: string, weight: string?): string
	local weightAttr = weight and string.format(' weight="%s"', weight) or ""
	return string.format('<font family="%s"%s>', Theme.FONT_FAMILIES[family], weightAttr)
end
Theme.MAX_IMAGE_HEIGHT = 160
Theme.IMAGE_FILTER = {"png", "jpg", "jpeg", "bmp"}
Theme.FILE_EXTENSIONS = {
	mp3 = "Audio", wav = "Audio", ogg = "Audio",
	mp4 = "Video", webm = "Video",
	gif = "Decal",
	obj = "Mesh", fbx = "Mesh",
	rbxm = "Model", rbxmx = "Model",
	lua = "Script", luau = "Script",
	txt = "Text", json = "Text", xml = "Text", csv = "Text",
}

-- Layout constants
Theme.INPUT_HEIGHT = 49
Theme.PREVIEW_HEIGHT = 36
Theme.MENU_WIDTH = 160
Theme.MENU_ITEM_HEIGHT = 34
Theme.MAX_POLL_OPTIONS = 10

--!
-- Detects the current Roblox Studio theme.
-- @return string "Dark" or "Light"
--!
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

--!
-- Returns the color palette for the current Studio theme.
-- @return table
--!
function Theme.getColors()
	return Theme.PALETTES[Theme.detect()]
end

--!
-- Converts a Color3 to a hex string for use in RichText <font color> tags.
--!
function Theme.toHex(color: Color3): string
	return string.format("#%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255))
end

return Theme