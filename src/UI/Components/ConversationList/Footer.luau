--[[
	Footer

	The bottom of the conversation sidebar: icon buttons with tooltips
	(Settings, ...) and the expand/collapse toggle, last. Stacked on the
	rail, in a row when expanded.
]]

local Animation = require(script.Parent.Parent.Parent.Common.Animation)
local Icons = require(script.Parent.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local Shared = require(script.Parent.Shared)

local BUTTON_HEIGHT = 28
local GAP = 4
local TOGGLE_ORDER = 100

local Footer = {}

--[=[
	Builds the footer in the sidebar frame; `list` (the DMs) is sized to end above it.
]=]
function Footer.create(view: Shared.View, frame: Frame, list: ScrollingFrame)
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, -8)
	footer.BackgroundTransparency = 1
	footer.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = footer
	local padding = Instance.new("UIPadding")
	padding.Parent = footer

	local divider = Instance.new("Frame")
	divider.Name = "FooterDivider"
	divider.AnchorPoint = Vector2.new(0.5, 1)
	divider.BackgroundColor3 = view.colors.divider
	divider.BorderSizePixel = 0
	divider.Parent = frame
	Shared.corner(divider, UDim.new(1, 0))

	local buttons: { TextButton } = {}
	local toggle: TextButton? = nil

	local self = {}

	function self.layout()
		local expanded = view.list.expanded
		local count = #buttons
		layout.FillDirection = if expanded then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		layout.HorizontalAlignment = if expanded then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center
		padding.PaddingLeft = UDim.new(0, if expanded then 12 else 0)
		local height = if expanded then BUTTON_HEIGHT else count * BUTTON_HEIGHT + math.max(0, count - 1) * GAP
		footer.Size = UDim2.new(1, 0, 0, height)
		for _, button in ipairs(buttons) do
			button.Size = UDim2.fromOffset(if expanded then 32 else Shared.AVATAR_SIZE, BUTTON_HEIGHT)
		end
		divider.Position = UDim2.new(0.5, 0, 1, -(height + 14))
		divider.Size = if expanded then UDim2.new(1, -24, 0, 1) else UDim2.fromOffset(32, 2)
		list.Size = UDim2.new(1, 0, 1, -(Shared.LIST_TOP + height + 20))
		if toggle then
			toggle:SetAttribute("Tooltip", Language.t(if expanded then "sidebar.collapse" else "sidebar.expand"))
		end
	end

	--[=[
		Adds an icon button with a tooltip. Lower order = higher up (or
		further left); the toggle is last.
	]=]
	function self.addButton(
		name: string,
		iconKey: string,
		tooltipText: string,
		onClick: (() -> ())?,
		order: number?
	): TextButton
		local colors = view.colors
		local button = Instance.new("TextButton")
		button.Name = name
		button.BackgroundColor3 = colors.menuItemHover
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.TextColor3 = colors.timestamp
		button.TextSize = 18
		button.LayoutOrder = order or (#buttons + 1)
		button:SetAttribute("Tooltip", tooltipText)
		Icons.apply(button, iconKey)
		button.Parent = footer
		Shared.corner(button, UDim.new(0, 8))
		button.MouseEnter:Connect(function()
			Animation.tween(button, "quick", { BackgroundTransparency = 0 })
			button.TextColor3 = view.colors.messageText
			view.tooltip.show(button, Icons.escape(button:GetAttribute("Tooltip") or ""), view.list.expanded)
		end)
		button.MouseLeave:Connect(function()
			Animation.tween(button, "quick", { BackgroundTransparency = 1 })
			button.TextColor3 = view.colors.timestamp
			view.tooltip.hide()
		end)
		button.MouseButton1Click:Connect(function()
			view.tooltip.hide()
			if onClick then
				onClick()
			end
		end)
		table.insert(buttons, button)
		self.layout()
		return button
	end

	--[=[
		Adds the expand/collapse toggle; onToggle(expanded) asks for the other state.
	]=]
	function self.addToggle(onToggle: (expanded: boolean) -> ())
		toggle = self.addButton("Toggle", "sidebar", Language.t("sidebar.expand"), function()
			onToggle(not view.list.expanded)
		end, TOGGLE_ORDER)
		Language.changed:Connect(function()
			if toggle then
				toggle:SetAttribute(
					"Tooltip",
					Language.t(if view.list.expanded then "sidebar.collapse" else "sidebar.expand")
				)
			end
		end)
	end

	function self.recolor()
		divider.BackgroundColor3 = view.colors.divider
		for _, button in ipairs(buttons) do
			button.BackgroundColor3 = view.colors.menuItemHover
			button.TextColor3 = view.colors.timestamp
		end
	end

	return self
end

return Footer
