--!
-- Theme
-- Centralized color palettes, fonts, and layout constants for the
-- TeamChat plugin UI. Detects Studio's light/dark mode automatically.
--!

local Theme = {}

--!
-- Color palettes for each Studio theme mode, modeled on Roblox's own dark
-- and light themes: near-black / white surfaces, soft grays and Roblox blue.
--!
Theme.PALETTES = {
	Dark = {
		scrollBack = Color3.fromRGB(25, 27, 30), -- chat background
		inputFrame = Color3.fromRGB(18, 19, 22), -- header, sidebar and composer bar
		replyBarBack = Color3.fromRGB(32, 34, 38),
		inputBox = Color3.fromRGB(37, 39, 43),
		sendButton = Color3.fromRGB(51, 95, 255), -- Roblox blue: primary actions and accents
		sendButtonInactive = Color3.fromRGB(38, 52, 110),
		timestamp = Color3.fromRGB(166, 168, 173), -- muted text
		messageText = Color3.fromRGB(247, 247, 248),
		sendButtonText = Color3.fromRGB(255, 255, 255),
		divider = Color3.fromRGB(47, 49, 54),
		scrollBar = Color3.fromRGB(80, 82, 88),
		textBoxText = Color3.fromRGB(247, 247, 248),
		placeholder = Color3.fromRGB(120, 123, 130),
		attachButton = Color3.fromRGB(37, 39, 43),
		attachIcon = Color3.fromRGB(200, 202, 207),
		imageBorder = Color3.fromRGB(47, 49, 54),
		previewBorder = Color3.fromRGB(47, 49, 54),
		loadingText = Color3.fromRGB(166, 168, 173),
		menuBack = Color3.fromRGB(32, 34, 38),
		menuBorder = Color3.fromRGB(52, 54, 59),
		menuItemHover = Color3.fromRGB(45, 47, 52),
		menuItemText = Color3.fromRGB(222, 223, 226),
		pollBar = Color3.fromRGB(45, 47, 52),
		pollBarVoted = Color3.fromRGB(51, 95, 255),
		pollBarText = Color3.fromRGB(247, 247, 248),
		emptyTitle = Color3.fromRGB(189, 190, 194),
		emptySubtitle = Color3.fromRGB(120, 123, 130),
		dialogBack = Color3.fromRGB(25, 27, 30),
		dialogBorder = Color3.fromRGB(47, 49, 54),
		dialogButton = Color3.fromRGB(51, 95, 255),
		dialogButtonText = Color3.fromRGB(255, 255, 255),
		dialogSecondary = Color3.fromRGB(37, 39, 43), -- setting cards and secondary buttons
		dialogInput = Color3.fromRGB(18, 19, 22),
		dialogInputText = Color3.fromRGB(247, 247, 248),
		danger = Color3.fromRGB(247, 75, 82), -- destructive actions (Delete)
		success = Color3.fromRGB(63, 191, 110), -- changelog "Added"
		warning = Color3.fromRGB(246, 183, 48), -- changelog "Fixed"
		-- @mentions: text under a see-through rounded tint (UI/MentionPills), so
		-- the text is brighter than it ends up looking
		mentionText = Color3.fromRGB(249, 250, 255),
		mentionBack = Color3.fromRGB(88, 101, 242),
		mentionRow = Color3.fromRGB(240, 178, 50), -- messages that mention you
	},
	Light = {
		scrollBack = Color3.fromRGB(255, 255, 255), -- chat background
		inputFrame = Color3.fromRGB(242, 244, 245), -- header, sidebar and composer bar
		replyBarBack = Color3.fromRGB(232, 234, 236),
		inputBox = Color3.fromRGB(234, 236, 238),
		sendButton = Color3.fromRGB(51, 95, 255), -- Roblox blue: primary actions and accents
		sendButtonInactive = Color3.fromRGB(165, 180, 240),
		timestamp = Color3.fromRGB(96, 97, 98), -- muted text
		messageText = Color3.fromRGB(25, 27, 30),
		sendButtonText = Color3.fromRGB(255, 255, 255),
		divider = Color3.fromRGB(222, 225, 227),
		scrollBar = Color3.fromRGB(189, 190, 190),
		textBoxText = Color3.fromRGB(25, 27, 30),
		placeholder = Color3.fromRGB(145, 147, 150),
		attachButton = Color3.fromRGB(234, 236, 238),
		attachIcon = Color3.fromRGB(57, 59, 61),
		imageBorder = Color3.fromRGB(222, 225, 227),
		previewBorder = Color3.fromRGB(222, 225, 227),
		loadingText = Color3.fromRGB(96, 97, 98),
		menuBack = Color3.fromRGB(255, 255, 255),
		menuBorder = Color3.fromRGB(222, 225, 227),
		menuItemHover = Color3.fromRGB(242, 244, 245),
		menuItemText = Color3.fromRGB(57, 59, 61),
		pollBar = Color3.fromRGB(234, 236, 238),
		pollBarVoted = Color3.fromRGB(51, 95, 255),
		pollBarText = Color3.fromRGB(25, 27, 30),
		emptyTitle = Color3.fromRGB(96, 97, 98),
		emptySubtitle = Color3.fromRGB(145, 147, 150),
		dialogBack = Color3.fromRGB(255, 255, 255),
		dialogBorder = Color3.fromRGB(222, 225, 227),
		dialogButton = Color3.fromRGB(51, 95, 255),
		dialogButtonText = Color3.fromRGB(255, 255, 255),
		dialogSecondary = Color3.fromRGB(242, 244, 245), -- setting cards and secondary buttons
		dialogInput = Color3.fromRGB(255, 255, 255),
		dialogInputText = Color3.fromRGB(25, 27, 30),
		danger = Color3.fromRGB(214, 44, 44), -- destructive actions (Delete)
		success = Color3.fromRGB(2, 136, 73), -- changelog "Added"
		warning = Color3.fromRGB(194, 121, 0), -- changelog "Fixed"
		mentionText = Color3.fromRGB(54, 68, 235), -- @mentions, under the tint (UI/MentionPills)
		mentionBack = Color3.fromRGB(88, 101, 242),
		mentionRow = Color3.fromRGB(240, 178, 50), -- messages that mention you
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
	body = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Regular),
	medium = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Medium),
	semibold = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.SemiBold),
	bold = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Bold),
	italic = Font.new(Theme.FONT_FAMILIES.sans, Enum.FontWeight.Regular, Enum.FontStyle.Italic),
	display = Font.new(Theme.FONT_FAMILIES.extended, Enum.FontWeight.Bold), -- dialog / empty-state titles
	heading = Font.new(Theme.FONT_FAMILIES.extended, Enum.FontWeight.SemiBold), -- poll questions, card labels
	mono = Font.new(Theme.FONT_FAMILIES.mono, Enum.FontWeight.Regular), -- times, counts, file types, /commands
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
Theme.LINK_COLOR = Color3.fromRGB(0, 88, 204) -- underlined links in messages and link previews
Theme.MENTION_TRANSPARENCY = 0.7 -- the rounded tint over an @mention
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
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	)
end

return Theme
