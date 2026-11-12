--[[
	Messages/Announcement

	The highlighted announcement card (/broadcast): accent bar, header with
	the megaphone, sender and time, and the message body.
]]

local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local RichText = require(script.Parent.Parent.Parent.Util.RichText)
local Shared = require(script.Parent.Shared)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local TimeFormatter = require(script.Parent.Parent.Parent.Util.TimeFormat)
local UsernameColors = require(script.Parent.Parent.Parent.Util.UsernameColors)

local FONT = Theme.FONT
local FONTS = Theme.FONTS

local Announcement = {}

--[=[
	Builds the header line of an announcement card: megaphone +
	"Announcement" (bold, in Roblox blue) + sender + the time, like the
	author line of a message.
]=]
function Announcement.buildHeader(sender, timestamp, themeColors)
	local time = TimeFormatter.formatPlain(timestamp)
	return string.format(
		'<font color="%s">%s %sAnnouncement</font></font>  ·  <font color="%s"><b>%s</b></font>%s',
		RichText.toHex(themeColors.sendButton),
		Icons.inline("announcement"),
		Theme.richFont("sans", "bold"),
		RichText.toHex(UsernameColors.getNameColor(sender)),
		RichText.escape(sender),
		if time ~= ""
			then string.format('  ·  <font color="%s">%s</font>', RichText.toHex(themeColors.timestamp), time)
			else ""
	)
end

--[=[
	Creates a highlighted announcement card (Discord-style broadcast).
]=]
function Announcement.create(sender, timestamp, content, themeColors, replyRef)
	local card = Instance.new("Frame")
	card.Name = "Announcement_" .. tostring(timestamp)
	card.Size = UDim2.new(1, -4, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = timestamp
	card.BackgroundColor3 = themeColors.inputFrame
	card.BorderSizePixel = 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = themeColors.divider
	cardStroke.Transparency = 0.35
	cardStroke.Parent = card

	-- Colored accent bar along the left edge. The card has no layout of its
	-- own (a bar the card's full height inside the list made the auto-sized
	-- card grow without end); the text goes in Content, like Embeds/CardFrame.
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(0, 3, 1, 0)
	accentBar.Position = UDim2.new(0, 0, 0, 0)
	accentBar.BackgroundColor3 = themeColors.sendButton
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 2
	accentBar.Parent = card
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 8)
	accentCorner.Parent = accentBar

	local inner = Instance.new("Frame")
	inner.Name = "Content"
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.new(1, 0, 0, 0)
	inner.AutomaticSize = Enum.AutomaticSize.Y
	inner.Parent = card

	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingTop = UDim.new(0, 10)
	cardPadding.PaddingBottom = UDim.new(0, 10)
	cardPadding.PaddingLeft = UDim.new(0, 14)
	cardPadding.PaddingRight = UDim.new(0, 12)
	cardPadding.Parent = inner

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = inner

	local layoutOrder = 1

	-- Reply reference (if present)
	if replyRef and replyRef.sender then
		local replyRow = Shared.createReplyReference(replyRef, themeColors)
		replyRow.LayoutOrder = layoutOrder
		replyRow.Parent = inner
		layoutOrder = layoutOrder + 1
	end

	-- Header: megaphone + "Announcement" + sender + timestamp
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 17)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.TextSize = 12
	header.TextColor3 = themeColors.timestamp
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.RichText = true
	header.Text = Announcement.buildHeader(sender, timestamp, themeColors)
	header.LayoutOrder = layoutOrder
	header.Parent = inner

	layoutOrder = layoutOrder + 1

	-- Message body
	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.FontFace = FONTS.semibold
	body.TextSize = Shared.textSize
	body.TextColor3 = themeColors.messageText
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Text = content or "" -- plain text label: no escaping needed
	body.LayoutOrder = layoutOrder
	body.Parent = inner

	return card
end

return Announcement
