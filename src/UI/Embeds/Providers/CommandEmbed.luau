--!nonstrict
--[[
	CommandEmbed

	The card a command replies with, like a Discord bot embed: a coloured
	edge, a title, a short description, an optional avatar on the right,
	labelled fields (inline ones sit three to a row) and a small footer.
	It never matches a link; commands build it from a spec through
	ctx.addEmbed (see Commands/_Template). Registered as a provider so theme
	changes recolor it like any other embed.

	spec = {
	    title = "builderman",
	    description = "@builderman",          -- optional
	    thumbnailUserId = 156,                 -- optional: their avatar on the right
	    color = Color3?,                       -- optional: the edge (default: Roblox blue)
	    fields = { { name = "User ID", value = "156", inline = true }, ... },
	    footer = "Requested by …",             -- optional
	}
]]

local Style = require(script.Parent.Parent.EmbedStyle)
local CardFrame = require(script.Parent.Parent.CardFrame)
local Theme = require(script.Parent.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS

local THUMBNAIL_SIZE = 48
local FIELD_GAP = 8 -- between inline fields
local FIELD_SPACING = 6 -- below each field

local CommandEmbed = {
	Name = "Command",
	Priority = -100,
}

function CommandEmbed.matches(_url: string): boolean
	return false
end

function CommandEmbed.build(_url, _theme, _ctx)
	error("CommandEmbed is built from a spec: use CommandEmbed.fromSpec")
end

local function label(parent: Instance, name: string, text: string, font: Font, size: number, order: number): TextLabel
	return CardFrame.createTextRow(parent, {
		Name = name,
		Text = text,
		Font = font,
		TextSize = size,
		TextColor3 = Color3.new(1, 1, 1), -- recolor() sets the real colour
		LayoutOrder = order,
	})
end

--[=[
	Builds the card for a spec.
]=]
function CommandEmbed.fromSpec(spec, theme): GuiObject
	local holder, _card, body = CardFrame.create(theme, spec.color or theme.sendButton)
	holder.Name = "Embed"
	holder:SetAttribute("EmbedProvider", CommandEmbed.Name)
	holder:SetAttribute("UsesThemeAccent", spec.color == nil)

	-- Title and description, with room on the right for the avatar
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 0)
	top.AutomaticSize = Enum.AutomaticSize.Y
	top.LayoutOrder = 1
	top.Parent = body

	local column = Instance.new("Frame")
	column.Name = "Column"
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(1, if spec.thumbnailUserId then -(THUMBNAIL_SIZE + 10) else 0, 0, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.Parent = top
	local columnLayout = Instance.new("UIListLayout")
	columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnLayout.Padding = UDim.new(0, 2)
	columnLayout.Parent = column

	if spec.title then
		label(column, "Title", spec.title, FONTS.bold, Style.TITLE_TEXT_SIZE + 1, 1)
	end
	if spec.description and spec.description ~= "" then
		label(column, "Description", spec.description, FONTS.body, Style.BODY_TEXT_SIZE + 1, 2)
	end

	if spec.thumbnailUserId then
		local thumbnail = Instance.new("ImageLabel")
		thumbnail.Name = "Thumbnail"
		thumbnail.AnchorPoint = Vector2.new(1, 0)
		thumbnail.Position = UDim2.fromScale(1, 0)
		thumbnail.Size = UDim2.fromOffset(THUMBNAIL_SIZE, THUMBNAIL_SIZE)
		thumbnail.BorderSizePixel = 0
		thumbnail.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(spec.thumbnailUserId) .. "&w=150&h=150"
		thumbnail.Parent = top
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = thumbnail
	end

	-- Fields: inline ones wrap three to a row, the rest take the whole row
	if spec.fields and #spec.fields > 0 then
		local fields = Instance.new("Frame")
		fields.Name = "Fields"
		fields.BackgroundTransparency = 1
		fields.Size = UDim2.new(1, 0, 0, 0)
		fields.AutomaticSize = Enum.AutomaticSize.Y
		fields.LayoutOrder = 2
		fields.Parent = body
		local fieldsPadding = Instance.new("UIPadding")
		fieldsPadding.PaddingTop = UDim.new(0, 6)
		fieldsPadding.Parent = fields
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Wraps = true
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, FIELD_GAP)
		layout.Parent = fields

		for i, field in ipairs(spec.fields) do
			local box = Instance.new("Frame")
			box.Name = "Field_" .. i
			box.BackgroundTransparency = 1
			box.Size = if field.inline
				then UDim2.new(1 / 3, -math.ceil(FIELD_GAP * 2 / 3), 0, 0)
				else UDim2.new(1, 0, 0, 0)
			box.AutomaticSize = Enum.AutomaticSize.Y
			box.LayoutOrder = i
			box.Parent = fields
			local boxLayout = Instance.new("UIListLayout")
			boxLayout.SortOrder = Enum.SortOrder.LayoutOrder
			boxLayout.Padding = UDim.new(0, 1)
			boxLayout.Parent = box
			local boxPadding = Instance.new("UIPadding")
			boxPadding.PaddingBottom = UDim.new(0, FIELD_SPACING)
			boxPadding.Parent = box
			label(box, "FieldName", field.name, FONTS.bold, Style.BODY_TEXT_SIZE, 1)
			label(box, "FieldValue", tostring(field.value), FONTS.body, Style.BODY_TEXT_SIZE + 1, 2)
		end
	end

	if spec.footer and spec.footer ~= "" then
		label(body, "Footer", spec.footer, FONTS.body, Style.FOOTER_TEXT_SIZE, 3)
	end

	CommandEmbed.recolor(holder, theme)
	return holder
end

function CommandEmbed.recolor(embed: GuiObject, theme)
	local card = embed:FindFirstChild("Card")
	if not card then
		return
	end
	if embed:GetAttribute("UsesThemeAccent") then
		local accent = card:FindFirstChild("AccentBar")
		if accent then
			accent.BackgroundColor3 = theme.sendButton
		end
	end
	for _, item in ipairs(card:GetDescendants()) do
		if item:IsA("TextLabel") then
			if item.Name == "Title" or item.Name == "FieldName" then
				item.TextColor3 = theme.messageText
			elseif item.Name == "Footer" then
				item.TextColor3 = theme.timestamp
			else
				item.TextColor3 = theme.menuItemText or theme.messageText
			end
		elseif item.Name == "Thumbnail" and item:IsA("ImageLabel") then
			item.BackgroundColor3 = theme.menuItemHover
		end
	end
end

return CommandEmbed
