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

local Foundation = require(script.Parent.Parent.Foundation)
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
		label.TextSize = 12
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
	A button. style: "primary" | "secondary" | "danger", drawn as
	Foundation's emphasis, standard and alert buttons; or a chip for a
	pick-one switch: "choice", and "selected" for the chosen one (filled
	with the text colour, like a Roblox filter chip).
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
	button.BorderSizePixel = 0
	button.Size = UDim2.fromOffset(0, 32)
	button.AutomaticSize = Enum.AutomaticSize.X
	button.FontFace = FONTS.semibold
	button.TextSize = 13
	button.Text = text
	button.LayoutOrder = order
	button.ZIndex = z
	Foundation.button(
		button,
		colors,
		if style == "primary"
			then "emphasis"
			elseif style == "danger" then "alert"
			elseif style == "selected" then "subEmphasis"
			else "standard"
	)
	button:SetAttribute("Selected", if style == "selected" then true else nil)
	button.Parent = parent
	corner(button, if style == "selected" or style == "choice" then 999 else 8)
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
	Foundation.input(input, colors)
	input.BorderSizePixel = 0
	input.Size = UDim2.new(opts.width or UDim.new(1, 0), UDim.new(0, 32))
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
	corner(input, 8)
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
	pill.TextSize = 11
	pill.TextColor3 = color
	pill.Text = text
	pill.LayoutOrder = order
	pill.ZIndex = z
	pill.Parent = parent
	corner(pill, 999)
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
	-- Wider for long values ("06/11 13:09", "Moderator") so they stay on one line
	tile.Size = UDim2.fromOffset(if (utf8.len(value) or #value) > 6 then 150 else 104, 58)
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

--[=[
	Section tabs: a row of chips (round buttons), the selected one filled
	like a chosen Roblox filter chip. items: { { key, label } }. onSelect(key)
	when one is clicked.
]=]
function PanelKit.tabs(
	parent: Instance,
	items: { { key: string, label: string } },
	selected: string,
	order: number,
	z: number,
	colors: Palette,
	onSelect: (string) -> ()
): Frame
	local row = PanelKit.row(parent, order, z)
	row.Name = "Tabs"
	for index, item in ipairs(items) do
		local tab = PanelKit.button(
			row,
			item.label,
			if item.key == selected then "selected" else "choice",
			index,
			z,
			colors,
			function()
				onSelect(item.key)
			end
		)
		tab.Name = "Tab_" .. item.key
	end
	return row
end

--[=[
	A column chart: one bar per value, its label under it ("" for none).
	The tallest bar fills `height` (100).
]=]
function PanelKit.barChart(
	parent: Instance,
	values: { number },
	labels: { string },
	order: number,
	z: number,
	colors: Palette,
	options: { height: number?, color: Color3? }?
): Frame
	local opts = options or {}
	local height = opts.height or 100
	local max = 1
	for _, value in ipairs(values) do
		max = math.max(max, value)
	end
	local chart = Instance.new("Frame")
	chart.Name = "Chart"
	chart.BackgroundTransparency = 1
	chart.Size = UDim2.new(1, 0, 0, height + 34)
	chart.LayoutOrder = order
	chart.ZIndex = z
	chart.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalFlex = Enum.UIFlexAlignment.Fill
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = chart
	for index, value in ipairs(values) do
		local column = Instance.new("Frame")
		column.Name = "Column_" .. index
		column.BackgroundTransparency = 1
		column.Size = UDim2.new(0, 4, 1, 0)
		column.LayoutOrder = index
		column.ZIndex = z
		column.Parent = chart
		local barHeight = math.max(if value > 0 then 2 else 0, math.floor(height * value / max + 0.5))
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new(0, 0, 1, -18)
		bar.Size = UDim2.new(1, 0, 0, barHeight)
		bar.BackgroundColor3 = opts.color or colors.sendButton
		bar.BorderSizePixel = 0
		bar.ZIndex = z
		bar:SetAttribute("Value", value)
		bar.Parent = column
		corner(bar, 2)
		local count = Instance.new("TextLabel")
		count.Name = "Value"
		count.BackgroundTransparency = 1
		count.AnchorPoint = Vector2.new(0, 1)
		count.Position = UDim2.new(0, 0, 1, -20 - barHeight)
		count.Size = UDim2.new(1, 0, 0, 14)
		count.FontFace = FONTS.mono
		count.TextSize = 10
		count.TextColor3 = colors.timestamp
		count.Text = if value > 0 then tostring(value) else ""
		count.ZIndex = z
		count.Parent = column
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0, 1)
		label.Position = UDim2.fromScale(0, 1)
		label.Size = UDim2.new(1, 0, 0, 16)
		label.FontFace = FONTS.body
		label.TextSize = 10
		label.TextColor3 = colors.timestamp
		label.Text = labels[index] or ""
		label.ZIndex = z
		label.Parent = column
	end
	return chart
end

--[=[
	Horizontal bars, one per item ({ label, value, detail? }) in the order
	given: for top lists (most active people, most used commands).
]=]
function PanelKit.bars(
	parent: Instance,
	items: { { label: string, value: number, detail: string? } },
	order: number,
	z: number,
	colors: Palette
): Frame
	local max = 1
	for _, item in ipairs(items) do
		max = math.max(max, item.value)
	end
	local stack = Instance.new("Frame")
	stack.Name = "Bars"
	stack.BackgroundTransparency = 1
	stack.Size = UDim2.new(1, 0, 0, 0)
	stack.AutomaticSize = Enum.AutomaticSize.Y
	stack.LayoutOrder = order
	stack.ZIndex = z
	stack.Parent = parent
	list(stack, false, 6)
	for index, item in ipairs(items) do
		local row = Instance.new("Frame")
		row.Name = "Bar_" .. index
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 22)
		row.LayoutOrder = index
		row.ZIndex = z
		row.Parent = stack
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = colors.sendButton
		fill.BackgroundTransparency = 0.6
		fill.BorderSizePixel = 0
		fill.Size = UDim2.new(math.max(item.value / max, 0.02), 0, 1, 0)
		fill.ZIndex = z
		fill.Parent = row
		corner(fill, 4)
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(8, 0)
		label.Size = UDim2.new(1, -60, 1, 0)
		label.FontFace = FONTS.medium
		label.TextSize = 12
		label.TextColor3 = colors.messageText
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.RichText = true
		label.Text = item.label
			.. (if item.detail then '  <font transparency="0.4">' .. item.detail .. "</font>" else "")
		label.ZIndex = z + 1
		label.Parent = row
		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.BackgroundTransparency = 1
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -8, 0, 0)
		value.Size = UDim2.new(0, 50, 1, 0)
		value.FontFace = FONTS.mono
		value.TextSize = 12
		value.TextColor3 = colors.messageText
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.Text = tostring(item.value)
		value.ZIndex = z + 1
		value.Parent = row
	end
	return stack
end

--[=[
	Code you can select and copy (read-only, monospace, as tall as it is).
]=]
function PanelKit.codeBox(parent: Instance, code: string, order: number, z: number, colors: Palette): TextBox
	local box = Instance.new("TextBox")
	box.Name = "Code"
	box.BackgroundColor3 = colors.codeBack or colors.dialogInput
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.ClearTextOnFocus = false
	box.TextEditable = false
	box.MultiLine = true
	box.TextWrapped = true
	box.FontFace = FONTS.mono
	box.TextSize = 12
	box.TextColor3 = colors.codeText or colors.dialogInputText
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.Text = code
	box.LayoutOrder = order
	box.ZIndex = z
	box.Parent = parent
	corner(box, 8)
	padding(box, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = colors.codeBorder or colors.dialogBorder
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	return box
end

return PanelKit
