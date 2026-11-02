--!
-- Icons
-- Central registry for every icon in the plugin, using Roblox's official
-- Builder Icons font (the same icon set Studio and the Roblox client use).
--
-- Usage:
--   Icons.apply(button, "send")                  -- make a TextButton/TextLabel show an icon
--   Icons.apply(button, "send", true)            -- same, but the filled variant
--   label.RichText = true
--   label.Text = Icons.inline("attachFile") .. " " .. Icons.escape(fileName)
--   Icons.forFileType("Audio")                   -- icon key for a file type
--
-- To change an icon, edit its name in Icons.NAMES below; nothing else needs
-- to change. Icons are drawn as text, so their color is the label's TextColor3.
--!

local Icons = {}

-- Font family Roblox itself uses for Builder Icons.
-- Regular weight = outline icons, Bold weight = filled icons.
Icons.FONT_FAMILY = "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json"

-- Semantic key -> Builder Icons name (names are ligatures in the font).
-- Names must match the font exactly; browse them at
-- https://voxlenox.github.io/RobloxBuilderIconList/ (an unknown name renders as a box).
Icons.NAMES = {
	-- Chat
	emptyChat = "two-speech-bubbles",
	send = "paper-airplane",
	scrollDown = "arrow-large-down",
	announcement = "megaphone",
	reply = "arrow-curl-to-left",
	copy = "two-stacked-squares",
	delete = "trash-can",
	settings = "gear",
	command = "code",
	whatsNew = "book-open",

	-- Composer, menus and dialogs
	add = "plus-large",
	createPoll = "chart-three-horizontal-bars",
	attachFile = "page",
	dropFile = "arrow-down-to-line",
	close = "x",

	-- Media playback
	play = "play-large",
	pause = "pause-large",
	download = "arrow-down-to-line",

	-- Links and embeds
	website = "compass",
	link = "chain-link",

	-- Conversations sidebar
	sidebar = "sidebar",
	pinned = "pin",
	gameFallback = "cube",
	directMessages = "two-people",
	newMessage = "person-plus",
	openExternal = "arrow-up-right-from-square",

	-- File types (see Icons.forFileType)
	fileDefault = "page",
	fileImage = "image",
	fileAudio = "music-note",
	fileVideo = "video-camera",
	fileMesh = "cube-vertexes",
	fileModel = "cube",
	fileScript = "code",
	fileText = "pencil",
}

-- Plugin file type (see Theme.FILE_EXTENSIONS) -> icon key
Icons.FILE_TYPE_KEYS = {
	Image = "fileImage",
	Audio = "fileAudio",
	Video = "fileVideo",
	Mesh = "fileMesh",
	Model = "fileModel",
	Script = "fileScript",
	Text = "fileText",
}

local regularFont = Font.new(Icons.FONT_FAMILY, Enum.FontWeight.Regular)
local filledFont = Font.new(Icons.FONT_FAMILY, Enum.FontWeight.Bold)

local warnedKeys = {}

--!
-- Returns the Builder Icons name for a key ("" and a one-time warning if unknown).
--!
function Icons.name(key: string): string
	local name = Icons.NAMES[key]
	if not name then
		if not warnedKeys[key] then
			warnedKeys[key] = true
			warn("[TeamChat] Unknown icon key: " .. tostring(key))
		end
		return ""
	end
	return name
end

--!
-- The Builder Icons font. Pass true for the filled variant.
--!
function Icons.font(filled: boolean?): Font
	return if filled then filledFont else regularFont
end

--!
-- Turns a TextLabel/TextButton into an icon. The icon is drawn with the
-- object's TextColor3 and TextSize.
--!
function Icons.apply(object: TextLabel | TextButton, key: string, filled: boolean?)
	object.RichText = false
	object.FontFace = Icons.font(filled)
	object.Text = Icons.name(key)
end

--!
-- Returns a RichText snippet that draws the icon inline with other text.
-- The label using it must have RichText = true. Optional size is in pixels.
--!
function Icons.inline(key: string, filled: boolean?, size: number?): string
	local weight = filled and ' weight="bold"' or ""
	local sizeAttr = size and string.format(' size="%d"', size) or ""
	return string.format('<font family="%s"%s%s>%s</font>', Icons.FONT_FAMILY, weight, sizeAttr, Icons.name(key))
end

--!
-- Escapes user text (file names, URLs) so it is safe to place in a RichText
-- label next to an inline icon.
--!
function Icons.escape(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

--!
-- Icon key for a plugin file type ("Audio", "Video", ...); unknown types get
-- the generic file icon.
--!
function Icons.forFileType(fileType: string?): string
	return Icons.FILE_TYPE_KEYS[fileType or ""] or "fileDefault"
end

return Icons
