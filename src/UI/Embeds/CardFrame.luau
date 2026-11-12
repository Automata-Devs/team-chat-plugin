--!nonstrict
--[[
	CardFrame

	Builds the shared shell every embed uses, so providers only have to fill
	in content.

	Structure (only Body has a layout, so nothing else is pushed around):
	  EmbedHolder (Frame, auto height, outer spacing)
	    Card (TextButton, auto height, rounded + stroke, clickable)
	      AccentBar (Frame, inset on the left, absolutely positioned)
	      Body (Frame, auto height, padding + vertical list layout)
	        <provider content goes here>
]]

local Style = require(script.Parent.EmbedStyle)

local CardFrame = {}

-- Current palette per card, so the hover highlight follows theme changes
local themeByCard = setmetatable({}, { __mode = "k" })

--[=[
	Creates the embed shell.
	Returns holder (root), card (clickable button), body (content parent)
]=]
function CardFrame.create(theme, accentColor)
	local holder = Instance.new("Frame")
	holder.Name = "EmbedHolder"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.new(1, 0, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y

	local holderPadding = Instance.new("UIPadding")
	holderPadding.PaddingTop = UDim.new(0, Style.HOLDER_PADDING_TOP)
	holderPadding.PaddingBottom = UDim.new(0, Style.HOLDER_PADDING_BOTTOM)
	holderPadding.PaddingRight = UDim.new(0, Style.HOLDER_PADDING_RIGHT)
	holderPadding.Parent = holder

	local card = Instance.new("TextButton")
	card.Name = "Card"
	card.Text = ""
	card.AutoButtonColor = false -- soft hover highlight below instead of the default flash
	card.BackgroundColor3 = theme.inputFrame
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = holder
	themeByCard[card] = theme

	local widthConstraint = Instance.new("UISizeConstraint")
	widthConstraint.MaxSize = Vector2.new(Style.CARD_MAX_WIDTH, 100000)
	widthConstraint.Parent = card

	card.MouseEnter:Connect(function()
		card.BackgroundColor3 = themeByCard[card].menuItemHover
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundColor3 = themeByCard[card].inputFrame
	end)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Style.CARD_CORNER_RADIUS)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Name = "CardStroke"
	stroke.Color = theme.divider
	stroke.Transparency = Style.CARD_STROKE_TRANSPARENCY
	stroke.Parent = card

	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.BackgroundColor3 = accentColor
	accentBar.BorderSizePixel = 0
	accentBar.Position = UDim2.new(0, Style.ACCENT_LEFT, 0, Style.ACCENT_VERTICAL_INSET)
	accentBar.Size = UDim2.new(0, Style.ACCENT_WIDTH, 1, -Style.ACCENT_VERTICAL_INSET * 2)
	accentBar.ZIndex = 2
	accentBar.Parent = card

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, Style.ACCENT_CORNER_RADIUS)
	accentCorner.Parent = accentBar

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Parent = card

	local bodyPadding = Instance.new("UIPadding")
	bodyPadding.PaddingTop = UDim.new(0, Style.BODY_PADDING_TOP)
	bodyPadding.PaddingBottom = UDim.new(0, Style.BODY_PADDING_BOTTOM)
	bodyPadding.PaddingLeft = UDim.new(0, Style.BODY_PADDING_LEFT)
	bodyPadding.PaddingRight = UDim.new(0, Style.BODY_PADDING_RIGHT)
	bodyPadding.Parent = body

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, Style.ROW_SPACING)
	bodyLayout.Parent = body

	return holder, card, body
end

--[=[
	Creates a text row for a card body. Rows wrap and grow in height instead
	of overflowing, so long URLs or paths can never break the card.
	options: { Name, Text, Font, TextSize, TextColor3, LayoutOrder, Truncate, RichText }
	Font may be an Enum.Font or a Font (e.g. Theme.FONTS.mono).
	RichText is off unless options.RichText == true (needed for inline icons).
]=]
function CardFrame.createTextRow(parent, options)
	local label = Instance.new("TextLabel")
	label.Name = options.Name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	if typeof(options.Font) == "Font" then
		label.FontFace = options.Font
	else
		label.Font = options.Font
	end
	label.TextSize = options.TextSize
	label.TextColor3 = options.TextColor3
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.RichText = options.RichText == true
	label.LayoutOrder = options.LayoutOrder or 0
	if options.Truncate then
		-- Single line with "..." (height is fixed to one line of text)
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.new(1, 0, 0, options.TextSize + 2)
	else
		label.TextWrapped = true
	end
	label.Text = options.Text
	label.Parent = parent
	return label
end

--[=[
	Re-applies theme colors to the shell. Provider-specific colors are handled
	by the provider's own recolor function.
]=]
function CardFrame.recolor(holder, theme)
	local card = holder:FindFirstChild("Card")
	if not card then
		return
	end
	themeByCard[card] = theme
	card.BackgroundColor3 = theme.inputFrame
	local stroke = card:FindFirstChild("CardStroke")
	if stroke then
		stroke.Color = theme.divider
	end
end

return CardFrame
