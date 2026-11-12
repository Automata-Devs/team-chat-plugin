--[[
	Settings

	Joins several dialogs into one Settings window with its tabs on the left,
	like Discord's settings: one window, a tab column in its own shade on the
	left, a divider, and the open dialog's card as the page. Tabs come in
	groups under small headings (Team Chat, Manage, Info) and the plugin's
	version sits at the bottom of the column. Picking a tab swaps the page
	without re-opening the window (Animation fades the new page in). In a
	narrow panel the column shows icons only.
]]

local Animation = require(script.Parent.Parent.Common.Animation)
local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS
local NAV_WIDE = 168 -- icons and names
local NAV_NARROW = 52 -- icons only
local NARROW_BELOW = 460 -- panel width where the column switches to icons only
local RADIUS = 16 -- the window's corners (the same as ModalKit's card)
local NAV_PADDING = 10
local ITEM_HEIGHT = 32
local ICON_LEFT = 4
local ICON_SIZE = 28
local FOOTER_HEIGHT = 36
local WINDOW_MIN_HEIGHT = 540 -- every tab is this tall (the modal maximum), or the panel height if smaller

local SettingsTabs = {}

local function corner(parent: Instance, radius: number)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius)
	object.Parent = parent
end

--[=[
	tabs: { { name: string, icon: string, labelKey: string?, titleKey: string?,
	         group: string?, dialog: { modal, open(...), close(), isVisible() } } }
	name identifies the tab; labelKey / titleKey are Core/Language keys for
	its name in the column and its window title; group puts it under the
	heading "tab.group.<group>" (tabs of a group are listed together).
	getThemeColors: () -> palette
	Returns { open(name?, ...), close(), toggle(), isOpen(), current(), recolor() }
]=]
function SettingsTabs.create(tabs, getThemeColors)
	-- per dialog: { window, frame, fill, divider, footer, stroke, headings, items, owner }
	local navs = {}
	local self = {}

	local function paint()
		local colors = getThemeColors()
		local navBack = colors.navBack or colors.menuBack
		local selectedBack = colors.navSelected or colors.menuItemHover
		for _, nav in ipairs(navs) do
			nav.window.BackgroundColor3 = navBack
			nav.stroke.Color = colors.dialogBorder
			nav.fill.BackgroundColor3 = colors.dialogBack
			nav.divider.BackgroundColor3 = colors.dialogBorder
			nav.footer.TextColor3 = colors.timestamp
			for _, heading in ipairs(nav.headings) do
				(heading:FindFirstChild("Text") :: TextLabel).TextColor3 = colors.timestamp;
				(heading:FindFirstChild("Rule") :: Frame).BackgroundColor3 = colors.dialogBorder
			end
			for name, item in pairs(nav.items) do
				local selected = name == nav.owner
				item.BackgroundColor3 = selectedBack
				item.BackgroundTransparency = if selected then 0 else 1
				local label = item:FindFirstChild("Label") :: TextLabel
				local icon = item:FindFirstChild("Icon") :: TextLabel
				local pill = item:FindFirstChild("Pill") :: Frame
				label.TextColor3 = if selected then colors.messageText else colors.timestamp
				label.FontFace = if selected then FONTS.semibold else FONTS.medium
				icon.TextColor3 = if selected then colors.sendButton else colors.timestamp
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

	local function navOf(tab)
		for _, nav in ipairs(navs) do
			if nav.owner == tab.name then
				return nav
			end
		end
		return nil
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

	--[=[
		Opens a tab (General when none is given). From another tab it swaps
		the page in place; extra arguments go to the dialog's open().
	]=]
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
		local nav = navOf(target)
		if switching and nav then
			-- The page fades in: so does the strip that squares its left corners
			Animation.fadeIn(nav.fill, "quick")
		end
	end

	function self.close()
		for _, tab in ipairs(tabs) do
			if tab.dialog.isVisible() then
				tab.dialog.close()
			end
		end
	end

	--[=[
		Closes the window if it's open, otherwise opens it on General.
	]=]
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
		local z = modal.contentZIndex - 2 -- the overlay's; the card is z + 1
		if owner.titleKey then
			Language.bind(modal.title, "Text", owner.titleKey)
		end
		-- Each page keeps its own title and icon; one height for every tab, so
		-- switching doesn't make the window jump
		modal.minHeight = WINDOW_MIN_HEIGHT
		-- The window draws the outline: the card's own would curve at the divider
		local cardStroke = card:FindFirstChild("DialogStroke")
		if cardStroke and cardStroke:IsA("UIStroke") then
			cardStroke.Enabled = false
		end

		-- The window behind the column and the page: one rounded shape with
		-- one outline. Its right part is under the card (same corners).
		local window = Instance.new("Frame")
		window.Name = "SettingsWindow"
		window.BorderSizePixel = 0
		window.ZIndex = z
		window.Parent = overlay
		corner(window, RADIUS)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Parent = window

		-- Squares the page's left corners against the column
		local fill = Instance.new("Frame")
		fill.Name = "CornerFill"
		fill.BorderSizePixel = 0
		fill.Size = UDim2.new(0, RADIUS + 2, 1, 0)
		fill.ZIndex = z + 1
		fill.Parent = window

		local divider = Instance.new("Frame")
		divider.Name = "Divider"
		divider.BorderSizePixel = 0
		divider.Size = UDim2.new(0, 1, 1, 0)
		divider.ZIndex = z + 1
		divider.Parent = window

		-- The plugin's version at the bottom of the column
		local footer = Instance.new("TextLabel")
		footer.Name = "Version"
		footer.AnchorPoint = Vector2.new(0, 1)
		footer.Position = UDim2.new(0, 0, 1, 0)
		footer.BackgroundTransparency = 1
		footer.FontFace = FONTS.medium
		footer.TextSize = 11
		footer.TextXAlignment = Enum.TextXAlignment.Left
		footer.TextTruncate = Enum.TextTruncate.AtEnd
		footer.ZIndex = z + 2
		footer.Parent = window
		Language.bind(footer, "Text", "tab.version", { version = Constants.PLUGIN_VERSION })
		local footerPadding = Instance.new("UIPadding")
		footerPadding.PaddingLeft = UDim.new(0, NAV_PADDING + 10)
		footerPadding.Parent = footer

		-- The column's tabs (see-through: the window is its background)
		local frame = Instance.new("Frame")
		frame.Name = "SettingsNav"
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ZIndex = z + 1
		frame.Parent = overlay
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 2)
		layout.Parent = frame
		local navPadding = Instance.new("UIPadding")
		navPadding.PaddingTop = UDim.new(0, 16) -- the first heading lines up with the page title
		navPadding.PaddingLeft = UDim.new(0, NAV_PADDING)
		navPadding.PaddingRight = UDim.new(0, NAV_PADDING)
		navPadding.PaddingBottom = UDim.new(0, FOOTER_HEIGHT)
		navPadding.Parent = frame

		-- clicking the column (or anywhere in the window) doesn't close it
		table.insert(modal.insideGuis, window)
		table.insert(modal.insideGuis, frame)
		local nav = {
			window = window,
			frame = frame,
			fill = fill,
			divider = divider,
			footer = footer,
			stroke = stroke,
			headings = {},
			items = {},
			owner = owner.name,
		}

		-- A group's heading: its name, or a thin rule when the column is narrow
		local function addHeading(group: string, order: number, first: boolean)
			local heading = Instance.new("Frame")
			heading.Name = "Group_" .. group
			heading.BackgroundTransparency = 1
			heading.LayoutOrder = order
			heading.ZIndex = z + 2
			heading:SetAttribute("First", first)
			heading.Parent = frame
			local text = Instance.new("TextLabel")
			text.Name = "Text"
			text.AnchorPoint = Vector2.new(0, 1)
			text.Position = UDim2.new(0, 0, 1, -4)
			text.Size = UDim2.new(1, 0, 0, 16)
			text.BackgroundTransparency = 1
			text.FontFace = FONTS.bold
			text.TextSize = 12
			text.TextXAlignment = Enum.TextXAlignment.Left
			text.TextTruncate = Enum.TextTruncate.AtEnd
			text.ZIndex = z + 2
			text.Parent = heading
			Language.bind(text, "Text", "tab.group." .. group)
			local textPadding = Instance.new("UIPadding")
			textPadding.PaddingLeft = UDim.new(0, 10)
			textPadding.Parent = text
			local rule = Instance.new("Frame")
			rule.Name = "Rule"
			rule.AnchorPoint = Vector2.new(0.5, 0.5)
			rule.Position = UDim2.fromScale(0.5, 0.5)
			rule.Size = UDim2.new(1, -8, 0, 1)
			rule.BorderSizePixel = 0
			rule.ZIndex = z + 2
			rule.Parent = heading
			table.insert(nav.headings, heading)
		end

		local order = 0
		local lastGroup: string? = nil
		for _, tab in ipairs(tabs) do
			if tab.group and tab.group ~= lastGroup then
				order += 1
				addHeading(tab.group, order, lastGroup == nil)
			end
			lastGroup = tab.group or lastGroup
			order += 1

			local item = Instance.new("TextButton")
			item.Name = "Tab_" .. tab.name
			item.Size = UDim2.new(1, 0, 0, ITEM_HEIGHT)
			item.Text = ""
			item.AutoButtonColor = false
			item.BorderSizePixel = 0
			item.LayoutOrder = order
			item.ZIndex = z + 2
			item.Parent = frame
			corner(item, 8)

			-- The open tab's accent, inside its highlight
			local pill = Instance.new("Frame")
			pill.Name = "Pill"
			pill.AnchorPoint = Vector2.new(0, 0.5)
			pill.Position = UDim2.new(0, 0, 0.5, 0)
			pill.Size = UDim2.fromOffset(3, 16)
			pill.BorderSizePixel = 0
			pill.ZIndex = z + 3
			pill.Parent = item
			corner(pill, 2)

			local icon = Instance.new("TextLabel")
			icon.Name = "Icon"
			icon.Position = UDim2.fromOffset(ICON_LEFT, 0)
			icon.Size = UDim2.fromOffset(ICON_SIZE, ITEM_HEIGHT)
			icon.BackgroundTransparency = 1
			icon.TextSize = 16
			icon.ZIndex = z + 3
			Icons.apply(icon, tab.icon)
			icon.Parent = item

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Position = UDim2.fromOffset(ICON_LEFT + ICON_SIZE + 4, 0)
			label.Size = UDim2.new(1, -(ICON_LEFT + ICON_SIZE + 8), 1, 0)
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

		-- The column and the card side by side, centered together as one
		-- window; icons only when narrow
		local function layoutNav()
			local narrow = overlay.AbsoluteSize.X < NARROW_BELOW
			local width = if narrow then NAV_NARROW else NAV_WIDE
			for _, item in pairs(nav.items) do
				(item:FindFirstChild("Label") :: TextLabel).Visible = not narrow
			end
			for _, heading in ipairs(nav.headings) do
				local first = heading:GetAttribute("First") == true
				heading.Size =
					UDim2.new(1, 0, 0, if narrow then (if first then 0 else 13) else (if first then 22 else 34))
				heading.Visible = not (narrow and first);
				(heading:FindFirstChild("Text") :: TextLabel).Visible = not narrow;
				(heading:FindFirstChild("Rule") :: Frame).Visible = narrow and not first
			end
			footer.Visible = not narrow
			navPadding.PaddingBottom = UDim.new(0, if narrow then NAV_PADDING else FOOTER_HEIGHT)
			-- The column takes room beside the card; ModalKit sizes the card in what's left
			if modal.reservedWidth ~= width then
				modal.reservedWidth = width
				modal.refit()
			end
			card.Position = UDim2.new(0.5, width / 2, 0.5, 0)
			local origin = overlay.AbsolutePosition
			local left = card.AbsolutePosition.X - origin.X - width
			local top = card.AbsolutePosition.Y - origin.Y
			window.Position = UDim2.fromOffset(left, top)
			window.Size = UDim2.fromOffset(width + card.AbsoluteSize.X, card.AbsoluteSize.Y)
			frame.Position = UDim2.fromOffset(left, top)
			frame.Size = UDim2.fromOffset(width, card.AbsoluteSize.Y)
			fill.Position = UDim2.fromOffset(width, 0)
			divider.Position = UDim2.fromOffset(width - 1, 0)
			footer.Size = UDim2.fromOffset(width, FOOTER_HEIGHT)
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
