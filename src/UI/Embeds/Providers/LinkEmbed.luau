--!nonstrict
--[[
	LinkEmbed

	Generic fallback embed for any http(s) / www link: a compact one-row
	preview with a globe tile, the site's name (a friendly name for well-known
	sites, otherwise the domain), the short address below it, and an "open"
	arrow. Matches every URL at the lowest priority, so more specific
	providers (added later) will take precedence.

	To add a new embed type, copy this file, change Name/Priority/matches, and
	build different content inside the card body. No other file needs editing.
]]

local Browser = require(script.Parent.Parent.Parent.Parent.Core.Browser)
local Style = require(script.Parent.Parent.EmbedStyle)
local CardFrame = require(script.Parent.Parent.CardFrame)
local Theme = require(script.Parent.Parent.Parent.Parent.Config.Theme)
local Icons = require(script.Parent.Parent.Parent.Parent.Config.Icons)

local FONTS = Theme.FONTS

-- Friendly names for well-known sites (domain without "www.")
local SITE_NAMES = {
	["roblox.com"] = "Roblox",
	["create.roblox.com"] = "Roblox Creator Hub",
	["devforum.roblox.com"] = "Roblox DevForum",
	["github.com"] = "GitHub",
	["youtube.com"] = "YouTube",
	["youtu.be"] = "YouTube",
	["discord.com"] = "Discord",
	["discord.gg"] = "Discord",
	["docs.google.com"] = "Google Docs",
	["drive.google.com"] = "Google Drive",
	["x.com"] = "X",
	["twitter.com"] = "X",
}

-- Splits a URL into the site's display name and a short address
-- (no scheme, no "www.", no trailing slash).
local function describeUrl(url: string): (string, string)
	local withoutScheme = string.gsub(url, "^%a+://", "")
	withoutScheme = string.gsub(withoutScheme, "^www%.", "")
	local domain = string.lower(string.match(withoutScheme, "^[^/?#]+") or withoutScheme)
	domain = string.gsub(domain, ":%d+$", "") -- drop a port
	local shortAddress = string.gsub(withoutScheme, "/$", "")
	return SITE_NAMES[domain] or domain, shortAddress
end

local function iconLabel(name: string, iconKey: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	Icons.apply(label, iconKey)
	label.TextSize = size
	label.TextColor3 = color
	return label
end

local LinkEmbed = {
	Name = "LinkEmbed",
	Priority = 0,
}

function LinkEmbed.matches(_url)
	return true
end

function LinkEmbed.build(url, theme, _ctx)
	local siteName, shortAddress = describeUrl(url)
	local accent = Theme.LINK_COLOR
	local holder, card, body = CardFrame.create(theme, accent)
	local tile, icon, open = Style.ICON_TILE_SIZE, Style.ICON_SIZE, Style.OPEN_ICON_SIZE

	local row = Instance.new("Frame")
	row.Name = "Preview"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, tile)
	row.LayoutOrder = 1
	row.Parent = body

	-- Globe in a rounded tile tinted with the link color
	local iconTile = Instance.new("Frame")
	iconTile.Name = "IconTile"
	iconTile.Size = UDim2.fromOffset(tile, tile)
	iconTile.BackgroundColor3 = accent
	iconTile.BackgroundTransparency = 0.85
	iconTile.BorderSizePixel = 0
	iconTile.Parent = row

	local tileCorner = Instance.new("UICorner")
	tileCorner.CornerRadius = UDim.new(0, 8)
	tileCorner.Parent = iconTile

	local globe = iconLabel("Icon", "website", icon, accent)
	globe.Size = UDim2.fromScale(1, 1)
	globe.Parent = iconTile

	-- Site name over the short address, both single-line
	local textLeft = tile + Style.ICON_GAP
	local textRight = open + Style.ICON_GAP

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(textLeft, 0)
	title.Size = UDim2.new(1, -(textLeft + textRight), 0.5, 0)
	title.Text = siteName
	title.FontFace = FONTS.semibold
	title.TextSize = Style.TITLE_TEXT_SIZE
	title.TextColor3 = theme.messageText
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Bottom
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = row

	local address = Instance.new("TextLabel")
	address.Name = "Address"
	address.BackgroundTransparency = 1
	address.Position = UDim2.new(0, textLeft, 0.5, 1)
	address.Size = UDim2.new(1, -(textLeft + textRight), 0.5, -1)
	address.Text = shortAddress
	address.FontFace = FONTS.body
	address.TextSize = Style.BODY_TEXT_SIZE
	address.TextColor3 = theme.timestamp
	address.TextXAlignment = Enum.TextXAlignment.Left
	address.TextYAlignment = Enum.TextYAlignment.Top
	address.TextTruncate = Enum.TextTruncate.AtEnd
	address.Parent = row

	-- "Opens externally" arrow on the right
	local openIcon = iconLabel("OpenIcon", "openExternal", open, theme.timestamp)
	openIcon.AnchorPoint = Vector2.new(1, 0.5)
	openIcon.Position = UDim2.new(1, 0, 0.5, 0)
	openIcon.Size = UDim2.fromOffset(open, open)
	openIcon.Parent = row

	card.MouseButton1Click:Connect(function()
		Browser.open(url)
	end)

	return holder
end

function LinkEmbed.recolor(embed, theme)
	local row = embed:FindFirstChild("Preview", true)
	if not row then
		return
	end
	local title = row:FindFirstChild("Title")
	if title then
		title.TextColor3 = theme.messageText
	end
	local address = row:FindFirstChild("Address")
	if address then
		address.TextColor3 = theme.timestamp
	end
	local openIcon = row:FindFirstChild("OpenIcon")
	if openIcon then
		openIcon.TextColor3 = theme.timestamp
	end
end

return LinkEmbed
