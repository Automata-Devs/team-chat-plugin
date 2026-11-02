--!
-- SettingsTabs
-- Joins several dialogs into one Settings window with its tabs on the left
-- (General, Badges, What's New, About), like Discord's settings: a nav
-- column attached to the left edge of each dialog's card. Picking a tab
-- swaps the page without re-opening the window (Animation fades the new
-- page in). In a narrow panel the nav shows icons only.
--!

local Animation = require(script.Parent.Parent.Animation)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS
local NAV_WIDE = 150 -- icons and names
local NAV_NARROW = 48 -- icons only
local NARROW_BELOW = 460 -- panel width where the nav switches to icons only
local OVERLAP = 10 -- the nav tucks under the card's rounded left edge
local ITEM_HEIGHT = 34
local WINDOW_MIN_HEIGHT = 540 -- every tab is this tall (the modal maximum), or the panel height if smaller

local SettingsTabs = {}

--!
-- tabs: { { name: string, icon: string, labelKey: string?, titleKey: string?,
--          dialog: { modal, open(...), close(), isVisible() } } }
-- name identifies the tab; labelKey / titleKey are Core/Language keys for
-- its name in the column and its window title.
-- getThemeColors: () -> palette
-- Returns { open(name?, ...), close(), toggle(), isOpen(), current(), recolor() }
--!
function SettingsTabs.create(tabs, getThemeColors)
	local navs = {} -- per dialog: { frame, stroke, items = { [name] = TextButton }, owner }
	local self = {}

	local function paint()
		local colors = getThemeColors()
		for _, nav in ipairs(navs) do
			nav.frame.BackgroundColor3 = colors.menuBack
			nav.stroke.Color = colors.dialogBorder
			nav.heading.TextColor3 = colors.timestamp
			for name, item in pairs(nav.items) do
				local selected = name == nav.owner
				item.BackgroundColor3 = colors.menuItemHover
				item.BackgroundTransparency = if selected then 0 else 1
				local label = item:FindFirstChild("Label") :: TextLabel
				local icon = item:FindFirstChild("Icon") :: TextLabel
				local pill = item:FindFirstChild("Pill") :: Frame
				local color = if selected then colors.messageText else colors.timestamp
				label.TextColor3 = color
				label.FontFace = if selected then FONTS.semibold else FONTS.medium
				icon.TextColor3 = if selected then colors.sendButton else color
				pill.BackgroundColor3 = colors.sendButton
				pill.Visible = selected
			end
		end
	end

	local function find(name: string?)
		for _, tab in ipairs(tabs) do
			if tab.name == name then
				return tab
			end
		end
		return tabs[1]
	end

	function self.current(): string?
		for _, tab in ipairs(tabs) do
			if tab.dialog.isVisible() then
				return tab.name
			end
		end
		return nil
	end

	function self.isOpen(): boolean
		return self.current() ~= nil
	end

	--!
	-- Opens a tab (General when none is given). From another tab it swaps
	-- the page in place; extra arguments go to the dialog's open().
	--!
	function self.open(name: string?, ...)
		local target = find(name)
		local switching = false
		for _, tab in ipairs(tabs) do
			if tab ~= target and tab.dialog.isVisible() then
				switching = true
				tab.dialog.modal.instantNext = true
				tab.dialog.close()
			end
		end
		if switching or target.dialog.isVisible() then
			target.dialog.modal.instantNext = "switch"
		end
		target.dialog.open(...)
	end

	function self.close()
		for _, tab in ipairs(tabs) do
			if tab.dialog.isVisible() then
				tab.dialog.close()
			end
		end
	end

	--!
	-- Closes the window if it's open, otherwise opens it on General.
	--!
	function self.toggle()
		if self.isOpen() then
			self.close()
		else
			self.open()
		end
	end

	function self.recolor()
		paint()
	end

	for _, owner in ipairs(tabs) do
		local modal = owner.dialog.modal
		local card = modal.card :: ScrollingFrame
		local overlay = modal.overlay :: Frame
		local z = modal.contentZIndex
		if owner.titleKey then
			Language.bind(modal.title, "Text", owner.titleKey)
		end
		-- Each page keeps its own title and icon; one height for every tab, so
		-- switching doesn't make the window jump
		modal.minHeight = WINDOW_MIN_HEIGHT
		local padding = card:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingLeft = UDim.new(0, 18 + OVERLAP)
		end

		local frame = Instance.new("Frame")
		frame.Name = "SettingsNav"
		frame.BorderSizePixel = 0
		frame.ZIndex = z + 1 -- above the card's edge it tucks under
		frame.Parent = overlay
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Parent = frame
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = frame
		local navPadding = Instance.new("UIPadding")
		navPadding.PaddingTop = UDim.new(0, 18) -- the heading lines up with the title
		navPadding.PaddingLeft = UDim.new(0, 6)
		navPadding.PaddingRight = UDim.new(0, 6 + OVERLAP)
		navPadding.Parent = frame

		-- Small heading above the tabs (hidden when the nav shows icons only)
		local heading = Instance.new("TextLabel")
		heading.Name = "Heading"
		heading.Size = UDim2.new(1, 0, 0, 32)
		heading.BackgroundTransparency = 1
		heading.Text = "TEAM CHAT"
		heading.FontFace = FONTS.bold
		heading.TextSize = 11
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.LayoutOrder = 0
		heading.ZIndex = z + 2
		heading.Parent = frame
		local headingPadding = Instance.new("UIPadding")
		headingPadding.PaddingLeft = UDim.new(0, 10)
		headingPadding.Parent = heading

		table.insert(modal.insideGuis, frame) -- clicking the tabs doesn't close the window
		local nav = { frame = frame, stroke = stroke, heading = heading, items = {}, owner = owner.name }
		for i, tab in ipairs(tabs) do
			local item = Instance.new("TextButton")
			item.Name = "Tab_" .. tab.name
			item.Size = UDim2.new(1, 0, 0, ITEM_HEIGHT)
			item.Text = ""
			item.AutoButtonColor = false
			item.BorderSizePixel = 0
			item.LayoutOrder = i
			item.ZIndex = z + 2
			item.Parent = frame
			local itemCorner = Instance.new("UICorner")
			itemCorner.CornerRadius = UDim.new(0, 6)
			itemCorner.Parent = item

			local pill = Instance.new("Frame")
			pill.Name = "Pill"
			pill.AnchorPoint = Vector2.new(0, 0.5)
			pill.Position = UDim2.new(0, -6, 0.5, 0)
			pill.Size = UDim2.fromOffset(3, 18)
			pill.BorderSizePixel = 0
			pill.ZIndex = z + 3
			pill.Parent = item
			local pillCorner = Instance.new("UICorner")
			pillCorner.CornerRadius = UDim.new(1, 0)
			pillCorner.Parent = pill

			local icon = Instance.new("TextLabel")
			icon.Name = "Icon"
			icon.Size = UDim2.fromOffset(36, ITEM_HEIGHT)
			icon.BackgroundTransparency = 1
			icon.TextSize = 17
			icon.ZIndex = z + 3
			Icons.apply(icon, tab.icon)
			icon.Parent = item

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Position = UDim2.fromOffset(36, 0)
			label.Size = UDim2.new(1, -40, 1, 0)
			label.BackgroundTransparency = 1
			if tab.labelKey then
				Language.bind(label, "Text", tab.labelKey)
			else
				label.Text = tab.name
			end
			label.TextSize = 13
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.ZIndex = z + 3
			label.Parent = item

			item.MouseEnter:Connect(function()
				if nav.owner ~= tab.name then
					Animation.tween(item, "quick", { BackgroundTransparency = 0.5 })
				end
			end)
			item.MouseLeave:Connect(function()
				if nav.owner ~= tab.name then
					Animation.tween(item, "quick", { BackgroundTransparency = 1 })
				end
			end)
			item.MouseButton1Click:Connect(function()
				if tab ~= owner then
					self.open(tab.name)
				end
			end)
			nav.items[tab.name] = item
		end

		-- Card and nav side by side, centered together; icons only when narrow
		local function layoutNav()
			local narrow = overlay.AbsoluteSize.X < NARROW_BELOW
			local width = if narrow then NAV_NARROW else NAV_WIDE
			for _, item in pairs(nav.items) do
				(item:FindFirstChild("Label") :: TextLabel).Visible = not narrow
			end
			nav.heading.TextTransparency = if narrow then 1 else 0
			-- The nav takes room beside the card; ModalKit sizes the card in what's left
			if modal.reservedWidth ~= width - OVERLAP then
				modal.reservedWidth = width - OVERLAP
				modal.refit()
			end
			card.Position = UDim2.new(0.5, (width - OVERLAP) / 2, 0.5, 0)
			local origin = overlay.AbsolutePosition
			frame.Size = UDim2.fromOffset(width + OVERLAP, card.AbsoluteSize.Y)
			frame.Position =
				UDim2.fromOffset(card.AbsolutePosition.X - origin.X - width, card.AbsolutePosition.Y - origin.Y)
		end
		card:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutNav)
		card:GetPropertyChangedSignal("AbsolutePosition"):Connect(layoutNav)
		overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutNav)
		overlay:GetPropertyChangedSignal("Visible"):Connect(function()
			if overlay.Visible then
				task.defer(layoutNav)
			end
		end)
		layoutNav()
		table.insert(navs, nav)
	end
	paint()

	return self
end

return SettingsTabs
