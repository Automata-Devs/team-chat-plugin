--!strict
--[[
	EmojiPicker

	A small panel to pick an emoji for a reaction, like Discord's: a search
	box, a grid of emoji (the ones you use most first) and the hovered
	emoji's :name: at the bottom. It opens next to the cursor, kept inside
	the panel; Enter picks the first match, and Escape or a click outside
	closes it.

	Usage:
		local picker = EmojiPicker.create({
			container = container, widget = widget, getThemeColors = getTheme,
			getMousePosition = function() return widget:GetRelativeMousePosition() end,
			getScore = function(entry) return timesUsed end,
		})
		picker.open(function(entry) ... end) -- entry: { name, emoji, aliases }
		picker.pick("thumbsup")               -- as if clicked (tests)
		picker.close()
]]

local Animation = require(script.Parent.Parent.Animation)
local EmojiData = require(script.Parent.Parent.Parent.Util.EmojiData)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Foundation = require(script.Parent.Parent.Foundation)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Pointer = require(script.Parent.Pointer)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS
local WIDTH = 300
local HEIGHT = 320
local CELL = 34
local SEARCH_HEIGHT = 32
local FOOTER_HEIGHT = 30
local PADDING = 8
local EDGE_MARGIN = 4
local CURSOR_OFFSET = 2
local Z = 30

type Palette = { [string]: Color3 }
type Entry = EmojiData.Entry

export type Options = {
	container: Frame,
	widget: any,
	getThemeColors: () -> Palette,
	getMousePosition: () -> Vector2,
	getScore: ((Entry) -> number)?,
}

export type EmojiPicker = {
	frame: Frame,
	open: (onPick: (Entry) -> ()) -> (),
	pick: (name: string) -> boolean,
	close: () -> (),
	isOpen: () -> boolean,
	recolor: () -> (),
}

local EmojiPicker = {}

function EmojiPicker.create(options: Options): EmojiPicker
	local container = options.container
	local colors = options.getThemeColors

	local frame = Instance.new("Frame")
	frame.Name = "EmojiPicker"
	frame.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Active = true
	frame.ZIndex = Z
	frame.Parent = container
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Parent = frame
	local shadow = Instance.new("UIShadow")
	shadow.BlurRadius = UDim.new(0, 14)
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Transparency = 0.5
	shadow.Parent = frame

	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.Position = UDim2.fromOffset(PADDING, PADDING)
	search.Size = UDim2.new(1, -PADDING * 2, 0, SEARCH_HEIGHT)
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.Text = ""
	search.FontFace = FONTS.body
	search.TextSize = 14
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.ZIndex = Z + 1
	search.Parent = frame
	Language.bind(search, "PlaceholderText", "reactions.search")
	local searchCorner = Instance.new("UICorner")
	searchCorner.CornerRadius = UDim.new(0, 8)
	searchCorner.Parent = search
	local searchPadding = Instance.new("UIPadding")
	searchPadding.PaddingLeft = UDim.new(0, 30)
	searchPadding.PaddingRight = UDim.new(0, 10)
	searchPadding.Parent = search
	-- A magnifying glass in the box, like Roblox's search fields
	local searchIcon = Instance.new("TextLabel")
	searchIcon.Name = "Icon"
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, -22, 0.5, 0)
	searchIcon.Size = UDim2.fromOffset(16, 16)
	searchIcon.BackgroundTransparency = 1
	searchIcon.TextSize = 14
	searchIcon.ZIndex = Z + 2
	Icons.apply(searchIcon, "search")
	searchIcon.Parent = search

	local gridTop = PADDING * 2 + SEARCH_HEIGHT
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(0, gridTop)
	grid.Size = UDim2.new(1, 0, 1, -(gridTop + FOOTER_HEIGHT))
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ZIndex = Z + 1
	grid.Parent = frame
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(CELL, CELL)
	gridLayout.CellPadding = UDim2.fromOffset(2, 2)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = grid
	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingLeft = UDim.new(0, PADDING - 2)
	gridPadding.PaddingRight = UDim.new(0, PADDING - 2)
	gridPadding.PaddingBottom = UDim.new(0, 4)
	gridPadding.Parent = grid

	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.Position = UDim2.fromOffset(0, gridTop + 24)
	empty.Size = UDim2.new(1, 0, 0, 20)
	empty.BackgroundTransparency = 1
	empty.FontFace = FONTS.body
	empty.TextSize = 13
	empty.Visible = false
	empty.ZIndex = Z + 1
	empty.Parent = frame
	Language.bind(empty, "Text", "reactions.none")

	-- The hovered emoji and its :name:
	local footer = Instance.new("TextLabel")
	footer.Name = "Preview"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT)
	footer.BorderSizePixel = 0
	footer.FontFace = FONTS.medium
	footer.TextSize = 13
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextTruncate = Enum.TextTruncate.AtEnd
	footer.RichText = true
	footer.ZIndex = Z + 1
	footer.Parent = frame
	local footerPadding = Instance.new("UIPadding")
	footerPadding.PaddingLeft = UDim.new(0, PADDING + 4)
	footerPadding.PaddingRight = UDim.new(0, PADDING)
	footerPadding.Parent = footer
	local footerCorner = Instance.new("UICorner")
	footerCorner.CornerRadius = UDim.new(0, 8)
	footerCorner.Parent = footer

	local onPicked: ((Entry) -> ())? = nil
	local results: { Entry } = {}
	local buttons: { [string]: TextButton } = {} -- by name
	local cursor = Vector2.zero

	local function showHint()
		footer.Text = Language.t("reactions.hint")
	end

	local function close()
		frame.Visible = false
		onPicked = nil
		if search:IsFocused() then
			search:ReleaseFocus()
		end
	end

	local function choose(entry: Entry)
		local callback = onPicked
		close()
		if callback then
			callback(entry)
		end
	end

	local function paint()
		local palette = colors()
		frame.BackgroundColor3 = palette.menuBack
		stroke.Color = palette.menuBorder
		Foundation.input(search, palette)
		searchIcon.TextColor3 = palette.placeholder or palette.timestamp
		search.TextColor3 = palette.textBoxText or palette.messageText
		search.PlaceholderColor3 = palette.placeholder or palette.timestamp
		grid.ScrollBarImageColor3 = palette.scrollBar or palette.timestamp
		empty.TextColor3 = palette.timestamp
		footer.BackgroundColor3 = palette.inputFrame
		footer.TextColor3 = palette.timestamp
		for _, button in pairs(buttons) do
			button.BackgroundColor3 = palette.menuItemHover
		end
	end

	for _, entry in ipairs(EmojiData.search("")) do
		local button = Instance.new("TextButton")
		button.Name = "Emoji_" .. entry.name
		button.Text = entry.emoji
		button.TextSize = 22
		button.FontFace = FONTS.body
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.BackgroundTransparency = 1
		button.ZIndex = Z + 2
		button.Parent = grid
		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button
		button.MouseEnter:Connect(function()
			button.BackgroundTransparency = 0
			footer.Text = string.format("%s  :%s:", entry.emoji, entry.name)
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = 1
			showHint()
		end)
		button.MouseButton1Click:Connect(function()
			choose(entry)
		end)
		buttons[entry.name] = button
	end

	-- Shows the emoji matching the search (all of them when it's empty),
	-- the ones you use most first
	local function filter()
		results = EmojiData.search(search.Text, options.getScore)
		local shown = {}
		for rank, entry in ipairs(results) do
			local button = buttons[entry.name]
			if button then
				button.LayoutOrder = rank
				shown[entry.name] = true
			end
		end
		for name, button in pairs(buttons) do
			button.Visible = shown[name] == true
		end
		empty.Visible = #results == 0
		grid.CanvasPosition = Vector2.zero
	end
	search:GetPropertyChangedSignal("Text"):Connect(function()
		if frame.Visible then
			filter()
		end
	end)
	search.FocusLost:Connect(function(enterPressed: boolean, input: InputObject?)
		if not frame.Visible then
			return
		end
		if enterPressed then
			if results[1] then
				choose(results[1])
			end
		elseif input and input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)

	-- Next to the cursor, flipped left/up when it would overflow, clamped inside
	local function place()
		local bounds = container.AbsoluteSize
		local point = cursor - (container.AbsolutePosition - options.widget.AbsolutePosition)
		local x = point.X + CURSOR_OFFSET
		local y = point.Y + CURSOR_OFFSET
		if x + WIDTH > bounds.X - EDGE_MARGIN then
			x = point.X - CURSOR_OFFSET - WIDTH
		end
		if y + HEIGHT > bounds.Y - EDGE_MARGIN then
			y = point.Y - CURSOR_OFFSET - HEIGHT
		end
		x = math.clamp(x, EDGE_MARGIN, math.max(EDGE_MARGIN, bounds.X - WIDTH - EDGE_MARGIN))
		y = math.clamp(y, EDGE_MARGIN, math.max(EDGE_MARGIN, bounds.Y - HEIGHT - EDGE_MARGIN))
		frame.Position = UDim2.fromOffset(x, y)
	end

	-- A click outside closes it
	container.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and frame.Visible then
			if not Pointer.isInside(frame, input.Position) then
				close()
			end
		end
	end)

	paint()
	showHint()

	return {
		frame = frame,
		open = function(onPick: (Entry) -> ())
			onPicked = onPick
			cursor = options.getMousePosition()
			search.Text = ""
			filter()
			showHint()
			frame.Visible = true
			place()
			Animation.popIn(frame, 0.94, "smooth")
			search:CaptureFocus()
		end,
		pick = function(name: string): boolean
			local entry = EmojiData.get(name)
			if not entry or not frame.Visible then
				return false
			end
			choose(entry)
			return true
		end,
		close = close,
		isOpen = function(): boolean
			return frame.Visible
		end,
		recolor = paint,
	}
end

return EmojiPicker
