--!
-- AttachmentCards
-- The card under a file message for anything that isn't audio: a tinted
-- type icon, the file name, a type line and a download button. (Audio cards
-- are built in ChatUI and wired by AudioPlayback.)
--
-- Videos use this card too: Studio doesn't decode video in edit mode
-- (VideoFrame and VideoPlayer report playing but show no picture and play no
-- sound), so a player can't work inside a plugin. Download opens an uploaded
-- video's Roblox page, where it does play.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Browser = require(script.Parent.Parent.Parent.Core.Browser)

local FONTS = Theme.FONTS

local AttachmentCards = {}

local CARD_HEIGHT = 60

-- File type -> palette key used to tint its icon tile
local TYPE_COLOR_KEYS = {
	Video = "danger",
	Audio = "success",
	Mesh = "warning",
	Model = "warning",
	Script = "sendButton",
	Image = "sendButton",
}

local function typeColor(fileType: string?, themeColors)
	return themeColors[TYPE_COLOR_KEYS[fileType or ""] or "timestamp"]
end

local function isLocalOnly(fileUrl: string?): boolean
	return type(fileUrl) == "string" and string.sub(fileUrl, 1, 10) == "rbxtemp://"
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = if radius < 0 then UDim.new(1, 0) else UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, themeColors)
	local s = Instance.new("UIStroke")
	s.Name = "CardStroke"
	s.Color = themeColors.imageBorder
	s.Thickness = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function label(name: string, parent: Instance, props): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	for key, value in pairs(props) do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function iconButton(name: string, parent: Instance, iconKey: string, size: number, themeColors): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = themeColors.menuItemHover
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.TextColor3 = themeColors.messageText
	b.TextSize = math.floor(size * 0.55)
	Icons.apply(b, iconKey)
	corner(b, 6)
	b.MouseEnter:Connect(function()
		b.BackgroundTransparency = 0
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundTransparency = 1
	end)
	b.Parent = parent
	return b
end

-- "VIDEO · MP4 · LOCAL ONLY"
local function metaText(fileName: string, fileType: string?, fileUrl: string?): string
	local parts = { string.upper(fileType or "File") }
	local extension = string.match(fileName or "", "%.([%w]+)$")
	if extension then
		table.insert(parts, string.upper(extension))
	end
	if isLocalOnly(fileUrl) then
		table.insert(parts, "LOCAL ONLY")
	end
	return table.concat(parts, " · ")
end

-- Plugins can't save files to disk, so Download opens an uploaded file's
-- Roblox page in the browser. Local-only files have no page; openUrl copies
-- their ID to the clipboard instead.
local function download(fileUrl: string?)
	if not fileUrl or fileUrl == "" then
		return
	end
	local assetId = string.match(fileUrl, "^rbxassetid://(%d+)$")
	Browser.open(if assetId then "https://www.roblox.com/library/" .. assetId else fileUrl)
end

--!
-- Compact card for any file: tinted type icon, name, type line and a
-- download button.
--!
function AttachmentCards.createFile(
	container: Frame,
	fileName: string,
	fileUrl: string?,
	fileType: string?,
	themeColors,
	addBounds: (Frame) -> ()
)
	local card = Instance.new("Frame")
	card.Name = "FileCard"
	card.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
	card.BackgroundColor3 = themeColors.menuBack
	card.BorderSizePixel = 0
	card.LayoutOrder = 2
	card:SetAttribute("FileType", fileType)
	card.Parent = container
	addBounds(card)
	corner(card, 8)
	stroke(card, themeColors)

	local tint = typeColor(fileType, themeColors)
	local tile = Instance.new("Frame")
	tile.Name = "IconTile"
	tile.Size = UDim2.fromOffset(40, 40)
	tile.Position = UDim2.new(0, 10, 0.5, -20)
	tile.BackgroundColor3 = tint
	tile.BackgroundTransparency = 0.82
	tile.BorderSizePixel = 0
	tile.Parent = card
	corner(tile, 8)

	local icon = label("FileIcon", tile, {
		Size = UDim2.fromScale(1, 1),
		TextColor3 = tint,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	Icons.apply(icon, Icons.forFileType(fileType))

	label("FileName", card, {
		Size = UDim2.new(1, -110, 0, 18),
		Position = UDim2.fromOffset(60, 12),
		Text = fileName,
		TextColor3 = themeColors.menuItemText,
		FontFace = FONTS.semibold,
		TextSize = 13,
	})
	label("FileType", card, {
		Size = UDim2.new(1, -110, 0, 14),
		Position = UDim2.fromOffset(60, 32),
		Text = metaText(fileName, fileType, fileUrl),
		TextColor3 = themeColors.timestamp,
		FontFace = FONTS.mono,
		TextSize = 10,
	})

	local downloadButton = iconButton("DownloadButton", card, "download", 32, themeColors)
	downloadButton.AnchorPoint = Vector2.new(1, 0.5)
	downloadButton.Position = UDim2.new(1, -10, 0.5, 0)
	downloadButton.MouseButton1Click:Connect(function()
		download(fileUrl)
	end)

	return card
end

--!
-- Re-themes the attachment cards inside a file message container.
--!
function AttachmentCards.recolor(container: Instance, themeColors)
	for _, name in ipairs({ "FileCard", "AudioPlayerCard" }) do
		local card = container:FindFirstChild(name)
		if card and card:IsA("GuiObject") then
			card.BackgroundColor3 = themeColors.menuBack
			for _, d in ipairs(card:GetDescendants()) do
				if d.Name == "CardStroke" and d:IsA("UIStroke") then
					d.Color = themeColors.imageBorder
				elseif (d.Name == "FileName" or d.Name == "AudioFileName") and d:IsA("TextLabel") then
					d.TextColor3 = themeColors.menuItemText
				elseif (d.Name == "FileType" or d.Name == "PlaybackTime") and d:IsA("TextLabel") then
					d.TextColor3 = themeColors.timestamp
				elseif d:IsA("TextButton") and d.Name == "DownloadButton" then
					d.BackgroundColor3 = themeColors.menuItemHover
					d.TextColor3 = themeColors.messageText
				end
			end
			local tile = card:FindFirstChild("IconTile")
			if tile then
				local tint = typeColor(card:GetAttribute("FileType"), themeColors)
				tile.BackgroundColor3 = tint
				tile.FileIcon.TextColor3 = tint
			end
		end
	end
end

return AttachmentCards
