--!strict
--[[
	Controls

	Settings controls in the Roblox style: a setting card (bold title with
	its control on the right, a divider, then a description), toggle
	switches, sliders and dropdowns. Each control animates through
	UI/Animation and reports changes with onChange; set(value) updates it
	without calling onChange (e.g. when settings load).

	Usage:
		local card = Controls.card(page, { key = "timestamps", title = "Timestamps",
			description = "Show the time next to names.", order = 3 }, palette)
		local toggle = Controls.toggle(card.control, { value = true, onChange = save }, palette)
		local slider = Controls.slider(card.below, { min = 12, max = 18, step = 1, value = 14,
			format = function(v) return v .. "px" end, onChange = save, overlay = overlay,
			labelParent = card.control }, palette)
		local dropdown = Controls.dropdown(card.control, { options = { "Auto", "Light" }, value = "Auto",
			onChange = save, overlay = overlay }, palette)

	`overlay` is an unclipped full-panel frame (the dialog's backdrop): open
	dropdown lists and slider drags live there so the scrolling card can't
	cut them off.
]]

local Animation = require(script.Parent.Parent.Animation)
local Foundation = require(script.Parent.Parent.Foundation)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

type Palette = { [string]: Color3 }

local FONTS = Theme.FONTS

local TOGGLE_SIZE = Vector2.new(40, 22)
local KNOB = 16
local DROPDOWN_WIDTH = 140
local DROPDOWN_ROW = 30

local Controls = {}

local function corner(gui: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = gui
end

local function zOf(parent: Instance): number
	return if parent:IsA("GuiObject") then parent.ZIndex else 1
end

--[=[
	A setting card: title + control slot on top, an optional full-width row
	(`below`, for sliders), a divider, the description.
	Returns { frame, control (Frame for the control, right-aligned), below, recolor }.
	The frame is named "Setting_<key>" and carries SearchText for filtering.
]=]
function Controls.card(
	parent: Instance,
	info: { key: string, title: string, description: string, order: number },
	palette: Palette
)
	local z = zOf(parent)
	local frame = Instance.new("Frame")
	frame.Name = "Setting_" .. info.key
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BorderSizePixel = 0
	frame.LayoutOrder = info.order
	frame.ZIndex = z
	frame:SetAttribute("SearchText", string.lower(info.title .. " " .. info.description))
	frame.Parent = parent
	corner(frame, UDim.new(0, 8))
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = frame

	local top = Instance.new("Frame")
	top.Name = "Top"
	top.Size = UDim2.new(1, 0, 0, 30)
	top.BackgroundTransparency = 1
	top.LayoutOrder = 1
	top.ZIndex = z
	top.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.FontFace = FONTS.bold
	title.TextSize = 14
	title.Text = info.title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = z
	title.Parent = top

	-- The control sits on the right; the title gets the rest (truncating if it must)
	local control = Instance.new("Frame")
	control.Name = "Control"
	control.AnchorPoint = Vector2.new(1, 0.5)
	control.Position = UDim2.new(1, 0, 0.5, 0)
	control.Size = UDim2.fromOffset(0, 30)
	control.AutomaticSize = Enum.AutomaticSize.X
	control.BackgroundTransparency = 1
	control.ZIndex = z
	control.Parent = top
	control:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		title.Size = UDim2.new(1, -(control.AbsoluteSize.X + 12), 1, 0)
	end)

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 3
	divider.ZIndex = z
	divider.Parent = frame

	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.Size = UDim2.new(1, 0, 0, 0)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.BackgroundTransparency = 1
	description.FontFace = FONTS.body
	description.TextSize = 13
	description.TextWrapped = true
	description.Text = info.description
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.LayoutOrder = 4
	description.ZIndex = z
	description.Parent = frame

	-- A full-width row under the title for wide controls (sliders); hidden
	-- until something is put in it
	local below = Instance.new("Frame")
	below.Name = "Below"
	below.Size = UDim2.new(1, 0, 0, 24)
	below.BackgroundTransparency = 1
	below.LayoutOrder = 2
	below.ZIndex = z
	below.Visible = false
	below.Parent = frame
	below.ChildAdded:Connect(function()
		below.Visible = true
	end)

	local self = { frame = frame, control = control, below = below }
	function self.recolor(colors: Palette)
		frame.BackgroundColor3 = colors.dialogSecondary
		title.TextColor3 = colors.messageText
		divider.BackgroundColor3 = colors.divider
		description.TextColor3 = colors.timestamp
	end
	self.recolor(palette)
	return self
end

--[=[
	A toggle switch. The knob springs across, squishes while pressed and the
	track brightens on hover. Returns { frame, set(value), get(), recolor(palette) }.
]=]
function Controls.toggle(parent: Instance, options: { value: boolean, onChange: (boolean) -> () }, palette: Palette)
	local colors = palette
	local z = zOf(parent)
	local value = options.value

	local switch = Instance.new("TextButton")
	switch.Name = "Toggle"
	switch.AnchorPoint = Vector2.new(0, 0.5)
	switch.Position = UDim2.new(0, 0, 0.5, 0)
	switch.Size = UDim2.fromOffset(TOGGLE_SIZE.X, TOGGLE_SIZE.Y)
	switch.Text = ""
	switch.AutoButtonColor = false
	switch.BorderSizePixel = 0
	switch.ZIndex = z + 1
	switch.Parent = parent
	corner(switch, UDim.new(1, 0))

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.ZIndex = z + 2
	knob.Parent = switch
	corner(knob, UDim.new(1, 0))

	local hovered, pressed = false, false
	local inset = (TOGGLE_SIZE.Y - KNOB) / 2

	local function trackColor(): Color3
		local base = if value then colors.sendButton else colors.scrollBar
		return if hovered then base:Lerp(Color3.new(1, 1, 1), 0.12) else base
	end

	-- Knob: wider while pressed (stretching toward where it will go)
	local function knobLayout(): (UDim2, UDim2)
		local width = if pressed then KNOB + 6 else KNOB
		local x = if value then TOGGLE_SIZE.X - width - inset else inset
		return UDim2.new(0, x, 0.5, 0), UDim2.fromOffset(width, KNOB)
	end

	local function render(animate: boolean)
		local position, size = knobLayout()
		switch:SetAttribute("On", value)
		if animate then
			Animation.tween(knob, "pop", { Position = position, Size = size })
			Animation.tween(switch, "smooth", { BackgroundColor3 = trackColor() })
		else
			knob.Position = position
			knob.Size = size
			switch.BackgroundColor3 = trackColor()
		end
	end
	render(false)

	switch.MouseEnter:Connect(function()
		hovered = true
		Animation.tween(switch, "quick", { BackgroundColor3 = trackColor() })
	end)
	switch.MouseLeave:Connect(function()
		hovered, pressed = false, false
		render(true)
	end)
	switch.MouseButton1Down:Connect(function()
		if not Animation.enabled() then
			return -- with animations off the knob keeps its shape
		end
		pressed = true
		local position, size = knobLayout()
		Animation.tween(knob, "quick", { Position = position, Size = size })
	end)
	switch.MouseButton1Click:Connect(function()
		pressed = false
		value = not value
		render(true)
		options.onChange(value)
	end)

	local self = { frame = switch }
	function self.set(newValue: boolean)
		if newValue == value then
			return -- e.g. the save after a click: don't cut its animation short
		end
		value = newValue
		render(false)
	end
	function self.get(): boolean
		return value
	end
	function self.recolor(newPalette: Palette)
		colors = newPalette
		render(false)
	end
	return self
end

--[=[
	A slider filling its parent's width; the value shows in `labelParent`
	(e.g. the card's control slot). Dragging works anywhere in the panel (a
	full-panel catcher in `overlay` follows the mouse).
	Returns { frame, set(value), get(), recolor(palette) }.
]=]
function Controls.slider(
	parent: Instance,
	options: {
		min: number,
		max: number,
		step: number,
		value: number,
		format: ((number) -> string)?,
		onChange: (number) -> (),
		overlay: GuiObject,
		labelParent: Instance,
	},
	palette: Palette
)
	local colors = palette
	local z = zOf(parent)
	local value = options.value

	local frame = Instance.new("Frame")
	frame.Name = "Slider"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.ZIndex = z
	frame.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.Size = UDim2.fromOffset(56, 30)
	label.BackgroundTransparency = 1
	label.FontFace = FONTS.mono
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.ZIndex = z + 1
	label.Parent = options.labelParent

	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 7, 0.5, 0)
	track.Size = UDim2.new(1, -14, 0, 4)
	track.Text = ""
	track.AutoButtonColor = false
	track.BorderSizePixel = 0
	track.ZIndex = z + 1
	track.Parent = frame
	corner(track, UDim.new(1, 0))
	-- A taller invisible hit area around the thin track
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.AnchorPoint = Vector2.new(0, 0.5)
	hit.Position = UDim2.new(0, -7, 0.5, 0)
	hit.Size = UDim2.new(1, 14, 0, 22)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = z + 3
	hit.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.ZIndex = z + 1
	fill.Parent = track
	corner(fill, UDim.new(1, 0))

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(14, 14)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.ZIndex = z + 2
	knob.Parent = track
	corner(knob, UDim.new(1, 0))

	local function fraction(): number
		return if options.max > options.min then (value - options.min) / (options.max - options.min) else 0
	end

	local function render()
		local f = fraction()
		fill.Size = UDim2.new(f, 0, 1, 0)
		knob.Position = UDim2.new(f, 0, 0.5, 0)
		label.Text = if options.format then options.format(value) else tostring(value)
		track.BackgroundColor3 = colors.scrollBar
		fill.BackgroundColor3 = colors.sendButton
		label.TextColor3 = colors.messageText
		frame:SetAttribute("Value", value)
	end
	render()

	-- Sets the value from a mouse x position (widget space)
	local function setFromX(x: number)
		local f = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		local raw = options.min + f * (options.max - options.min)
		local stepped = math.clamp(math.floor(raw / options.step + 0.5) * options.step, options.min, options.max)
		if stepped ~= value then
			value = stepped
			render()
			options.onChange(value)
		end
	end

	-- While dragging, a transparent catcher over the whole panel follows the mouse
	local catcher: TextButton? = nil
	local function stopDrag()
		if not catcher then
			return
		end
		catcher:Destroy()
		catcher = nil
		Animation.tween(knob, "quick", { Size = UDim2.fromOffset(14, 14) })
	end
	-- Press, hold and drag; letting go anywhere ends it. The release goes to
	-- whatever got the press (the track), so it's watched there too, and on
	-- the press's own input object.
	hit.InputEnded:Connect(function(ended)
		if ended.UserInputType == Enum.UserInputType.MouseButton1 then
			stopDrag()
		end
	end)
	hit.InputChanged:Connect(function(change)
		if catcher and change.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(change.Position.X)
		end
	end)
	hit.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		stopDrag()
		setFromX(input.Position.X)
		if Animation.enabled() then
			Animation.tween(knob, "quick", { Size = UDim2.fromOffset(18, 18) })
		end
		input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				stopDrag()
			end
		end)
		local drag = Instance.new("TextButton")
		drag.Name = "SliderDrag"
		drag.Size = UDim2.fromScale(1, 1)
		drag.BackgroundTransparency = 1
		drag.Text = ""
		drag.ZIndex = 200
		drag.Parent = options.overlay
		drag.InputChanged:Connect(function(change)
			if change.UserInputType == Enum.UserInputType.MouseMovement then
				setFromX(change.Position.X)
			end
		end)
		drag.InputEnded:Connect(function(ended)
			if ended.UserInputType == Enum.UserInputType.MouseButton1 then
				stopDrag()
			end
		end)
		drag.MouseLeave:Connect(stopDrag)
		catcher = drag
	end)

	local self = { frame = frame }
	function self.set(newValue: number)
		if newValue == value then
			return
		end
		value = math.clamp(newValue, options.min, options.max)
		render()
	end
	function self.get(): number
		return value
	end
	--[=[
		Moves the slider to a fraction of its track (0..1), as a drag would.
	]=]
	function self.dragTo(f: number)
		setFromX(track.AbsolutePosition.X + f * track.AbsoluteSize.X)
	end
	function self.recolor(newPalette: Palette)
		colors = newPalette
		render()
	end
	return self
end

--[=[
	A dropdown: a button with the current value; clicking it opens the
	options below it (in `overlay`). Returns { frame, set(value), get(),
	open(), close(), choose(option), recolor(palette) }.
]=]
function Controls.dropdown(
	parent: Instance,
	options: {
		options: { string },
		value: string,
		labels: ({ [string]: string } | (string) -> string)?, -- shown text per option (a table or a function)
		onChange: (string) -> (),
		overlay: GuiObject,
	},
	palette: Palette
)
	local colors = palette
	local z = zOf(parent)
	local value = options.value
	local function textOf(option: string): string
		local labels = options.labels
		if type(labels) == "function" then
			return labels(option)
		end
		return labels and labels[option] or option
	end

	local button = Instance.new("TextButton")
	button.Name = "Dropdown"
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.Position = UDim2.new(0, 0, 0.5, 0)
	button.Size = UDim2.fromOffset(DROPDOWN_WIDTH, 30)
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.ZIndex = z + 1
	button.Parent = parent
	corner(button, UDim.new(0, 8))
	local stroke = Foundation.stroke(button, palette)

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.Position = UDim2.fromOffset(10, 0)
	label.Size = UDim2.new(1, -36, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = FONTS.medium
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = z + 2
	label.Parent = button

	local chevron = Instance.new("TextLabel")
	chevron.Name = "Chevron"
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -8, 0.5, 0)
	chevron.Size = UDim2.fromOffset(16, 16)
	chevron.BackgroundTransparency = 1
	chevron.TextSize = 14
	chevron.ZIndex = z + 2
	Icons.apply(chevron, "chevronDown")
	chevron.Parent = button

	local list: Frame? = nil
	local backdrop: TextButton? = nil

	local function render()
		label.Text = textOf(value)
		Foundation.input(button, colors)
		label.TextColor3 = colors.messageText
		chevron.TextColor3 = colors.timestamp
		button:SetAttribute("Value", value)
	end
	render()

	local self = { frame = button }

	function self.close()
		if backdrop then
			backdrop:Destroy()
			backdrop = nil
		end
		if list then
			local closing = list
			list = nil
			Animation.fadeOut(closing, "exit", function()
				closing:Destroy()
			end)
		end
		Animation.tween(chevron, "quick", { Rotation = 0 })
	end

	function self.choose(option: string)
		self.close()
		if option ~= value then
			value = option
			render()
			options.onChange(value)
		end
	end

	function self.open()
		if list then
			return
		end
		local overlay = options.overlay
		local origin = overlay.AbsolutePosition
		-- Clicking anywhere else closes it
		local catch = Instance.new("TextButton")
		catch.Name = "DropdownBackdrop"
		catch.Size = UDim2.fromScale(1, 1)
		catch.BackgroundTransparency = 1
		catch.Text = ""
		catch.ZIndex = 150
		catch.Parent = overlay
		catch.MouseButton1Click:Connect(self.close)
		backdrop = catch

		local menu = Instance.new("Frame")
		menu.Name = "DropdownList"
		menu.Position = UDim2.fromOffset(
			button.AbsolutePosition.X - origin.X,
			button.AbsolutePosition.Y - origin.Y + button.AbsoluteSize.Y + 4
		)
		menu.Size = UDim2.fromOffset(button.AbsoluteSize.X, #options.options * DROPDOWN_ROW + 8)
		menu.BackgroundColor3 = colors.menuBack
		menu.BorderSizePixel = 0
		menu.ZIndex = 151
		menu.Parent = overlay
		corner(menu, UDim.new(0, 8))
		local menuStroke = Instance.new("UIStroke")
		menuStroke.Color = colors.menuBorder
		menuStroke.Parent = menu
		local menuPadding = Instance.new("UIPadding")
		menuPadding.PaddingTop = UDim.new(0, 4)
		menuPadding.PaddingLeft = UDim.new(0, 4)
		menuPadding.PaddingRight = UDim.new(0, 4)
		menuPadding.Parent = menu
		local menuLayout = Instance.new("UIListLayout")
		menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
		menuLayout.Parent = menu
		-- Flip above the button when it would run off the bottom
		if menu.Position.Y.Offset + menu.Size.Y.Offset > overlay.AbsoluteSize.Y - 8 then
			menu.Position =
				UDim2.fromOffset(menu.Position.X.Offset, button.AbsolutePosition.Y - origin.Y - menu.Size.Y.Offset - 4)
		end

		for i, option in ipairs(options.options) do
			local row = Instance.new("TextButton")
			row.Name = "Option_" .. option
			row.Size = UDim2.new(1, 0, 0, DROPDOWN_ROW)
			row.BackgroundColor3 = colors.menuItemHover
			row.BackgroundTransparency = if option == value then 0 else 1
			row.AutoButtonColor = false
			row.BorderSizePixel = 0
			row.FontFace = if option == value then FONTS.semibold else FONTS.medium
			row.TextSize = 13
			row.TextColor3 = colors.messageText
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Text = textOf(option)
			row.LayoutOrder = i
			row.ZIndex = 152
			row.Parent = menu
			corner(row, UDim.new(0, 4))
			local rowPadding = Instance.new("UIPadding")
			rowPadding.PaddingLeft = UDim.new(0, 8)
			rowPadding.Parent = row
			row.MouseEnter:Connect(function()
				if option ~= value then
					Animation.tween(row, "quick", { BackgroundTransparency = 0.5 })
				end
			end)
			row.MouseLeave:Connect(function()
				if option ~= value then
					Animation.tween(row, "quick", { BackgroundTransparency = 1 })
				end
			end)
			row.MouseButton1Click:Connect(function()
				self.choose(option)
			end)
		end
		list = menu
		Animation.fadeIn(menu, "quick")
		Animation.tween(chevron, "quick", { Rotation = 180 })
	end

	button.MouseButton1Click:Connect(function()
		if list then
			self.close()
		else
			self.open()
		end
	end)
	button.MouseEnter:Connect(function()
		Animation.tween(stroke, "quick", { Color = colors.sendButton, Transparency = 0 })
	end)
	button.MouseLeave:Connect(function()
		Animation.tween(stroke, "quick", { Color = colors.tint, Transparency = Theme.STROKE.default })
	end)

	function self.set(newValue: string)
		if newValue == value then
			return
		end
		value = newValue
		render()
	end
	function self.get(): string
		return value
	end
	function self.isOpen(): boolean
		return list ~= nil
	end
	function self.recolor(newPalette: Palette)
		colors = newPalette
		render()
	end
	return self
end

return Controls
