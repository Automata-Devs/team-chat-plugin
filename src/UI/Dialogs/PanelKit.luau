--!strict
--[[
	PanelKit

	Small building blocks for the Settings tabs that are panels rather than
	text (the admin dashboard and the developer portal): boxes, rows, stat
	tiles, buttons, text boxes and pills, styled like the rest of Settings.
	Panels re-draw their content on open and on theme changes, so these
	take the palette when they're made.

	Usage:
		local box = PanelKit.box(card, order, z, colors)
		PanelKit.button(row, "Save", "primary", 1, z, colors, function() ... end)
]]

local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS

type Palette = { [string]: Color3 }

local PanelKit = {}

local function corner(gui: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = gui
end

local function padding(gui: GuiObject, all: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, all)
	p.PaddingBottom = UDim.new(0, all)
	p.PaddingLeft = UDim.new(0, all)
	p.PaddingRight = UDim.new(0, all)
	p.Parent = gui
end

local function list(gui: GuiObject, horizontal: boolean, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Wraps = horizontal
	layout.Parent = gui
end

--[=[
	Removes what a panel drew (everything but its layout and padding).
]=]
function PanelKit.clear(parent: Instance, keep: { [Instance]: boolean }?)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") and not (keep and keep[child]) then
			child:Destroy()
		end
	end
end

--[=[
	A label. role: "heading" | "title" | "body" | "muted" | "mono".
]=]
function PanelKit.text(
	parent: Instance,
	text: string,
	role: string,
	order: number,
	z: number,
	colors: Palette
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.RichText = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = order
	label.ZIndex = z
	if role == "heading" then
		label.FontFace = FONTS.bold
		label.TextSize = 11
		label.Text = string.upper(text)
		label.TextColor3 = colors.timestamp
	elseif role == "title" then
		label.FontFace = FONTS.semibold
		label.TextSize = 15
		label.TextColor3 = colors.messageText
	elseif role == "mono" then
		label.FontFace = FONTS.mono
		label.TextSize = 12
		label.TextColor3 = colors.timestamp
	else
		label.FontFace = FONTS.body
		label.TextSize = if role == "muted" then 12 else 13
		label.TextColor3 = if role == "muted" then colors.timestamp else colors.messageText
	end
	label.Parent = parent
	return label
end

--[=[
	A rounded box (like a setting card) holding a vertical list.
]=]
function PanelKit.box(parent: Instance, order: number, z: number, colors: Palette): Frame
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.BackgroundColor3 = colors.dialogSecondary
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.LayoutOrder = order
	box.ZIndex = z
	box.Parent = parent
	corner(box, 8)
	padding(box, 12)
	list(box, false, 8)
	return box
end

--[=[
	A row: things side by side, wrapping onto a new line when narrow.
]=]
function PanelKit.row(parent: Instance, order: number, z: number): Frame
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = order
	row.ZIndex = z
	row.Parent = parent
	list(row, true, 6)
	return row
end

--[=[
	A button. style: "primary" | "secondary" | "danger".
]=]
function PanelKit.button(
	parent: Instance,
	text: string,
	style: string,
	order: number,
	z: number,
	colors: Palette,
	onClick: () -> ()
): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.AutoButtonColor = true
	button.BorderSizePixel = 0
	button.Size = UDim2.fromOffset(0, 28)
	button.AutomaticSize = Enum.AutomaticSize.X
	button.FontFace = FONTS.semibold
	button.TextSize = 12
	button.Text = text
	button.LayoutOrder = order
	button.ZIndex = z
	if style == "primary" then
		button.BackgroundColor3 = colors.dialogButton
		button.TextColor3 = colors.dialogButtonText
	elseif style == "danger" then
		button.BackgroundColor3 = colors.danger
		button.TextColor3 = Color3.new(1, 1, 1)
	else
		button.BackgroundColor3 = colors.menuItemHover
		button.TextColor3 = colors.messageText
	end
	button.Parent = parent
	corner(button, 6)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 12)
	p.PaddingRight = UDim.new(0, 12)
	p.Parent = button
	button.MouseButton1Click:Connect(onClick)
	return button
end

--[=[
	A one-line text box. Read-only ones can still be selected and copied.
]=]
function PanelKit.input(
	parent: Instance,
	text: string,
	placeholder: string,
	order: number,
	z: number,
	colors: Palette,
	options: { width: UDim?, readOnly: boolean?, mono: boolean? }?
): TextBox
	local opts = options or {}
	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.BackgroundColor3 = colors.dialogInput
	input.BorderSizePixel = 0
	input.Size = UDim2.new(opts.width or UDim.new(1, 0), UDim.new(0, 30))
	input.ClearTextOnFocus = false
	input.TextEditable = not opts.readOnly
	input.FontFace = if opts.mono then FONTS.mono else FONTS.body
	input.TextSize = 13
	input.TextColor3 = colors.dialogInputText
	input.PlaceholderColor3 = colors.placeholder
	input.PlaceholderText = placeholder
	input.Text = text
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.TextTruncate = Enum.TextTruncate.AtEnd
	input.LayoutOrder = order
	input.ZIndex = z
	input.Parent = parent
	corner(input, 6)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 10)
	p.PaddingRight = UDim.new(0, 10)
	p.Parent = input
	return input
end

--[=[
	A small coloured label (a status like "Online", a kind like "Web").
]=]
function PanelKit.pill(parent: Instance, text: string, color: Color3, order: number, z: number): TextLabel
	local pill = Instance.new("TextLabel")
	pill.Name = "Pill"
	pill.BackgroundColor3 = color
	pill.BackgroundTransparency = 0.8
	pill.BorderSizePixel = 0
	pill.Size = UDim2.fromOffset(0, 18)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.FontFace = FONTS.bold
	pill.TextSize = 10
	pill.TextColor3 = color
	pill.Text = string.upper(text)
	pill.LayoutOrder = order
	pill.ZIndex = z
	pill.Parent = parent
	corner(pill, 9)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 7)
	p.PaddingRight = UDim.new(0, 7)
	p.Parent = pill
	return pill
end

--[=[
	A stat tile: a big number and what it counts.
]=]
function PanelKit.tile(parent: Instance, label: string, value: string, order: number, z: number, colors: Palette): Frame
	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.BackgroundColor3 = colors.dialogSecondary
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(104, 58)
	tile.LayoutOrder = order
	tile.ZIndex = z
	tile.Parent = parent
	corner(tile, 8)
	padding(tile, 10)
	list(tile, false, 2)
	local number = PanelKit.text(tile, value, "title", 1, z, colors)
	number.Name = "Value"
	number.TextSize = 20
	number.FontFace = FONTS.bold
	local caption = PanelKit.text(tile, label, "muted", 2, z, colors)
	caption.Name = "Label"
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.AutomaticSize = Enum.AutomaticSize.None
	caption.Size = UDim2.new(1, 0, 0, 14)
	return tile
end

--[=[
	A round avatar (a Roblox user's headshot).
]=]
function PanelKit.avatar(
	parent: Instance,
	userId: number?,
	size: number,
	order: number,
	z: number,
	colors: Palette
): ImageLabel
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = colors.menuItemHover
	avatar.BorderSizePixel = 0
	avatar.Size = UDim2.fromOffset(size, size)
	avatar.Image = if userId and userId > 0
		then "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=48&h=48"
		else ""
	avatar.LayoutOrder = order
	avatar.ZIndex = z
	avatar.Parent = parent
	corner(avatar, size // 2)
	return avatar
end

return PanelKit
