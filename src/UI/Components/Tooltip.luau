--!strict
--[[
	Tooltip

	A small rounded label shown above a hovered element (badges next to
	names), styled like the sidebar's tooltips, centered on it and kept
	inside the parent's width. Put it in an unscaled parent (the widget):
	positions come from AbsolutePosition. Text is rich text. It appears after
	hovering for Constants.TOOLTIP_DELAY seconds.

	Usage:
		local tooltip = Tooltip.create(container, palette)
		tooltip.show(target, "<b>Verified</b>\nThis account is verified")
		tooltip.hide()
		tooltip.recolor(palette)
]]

local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

type Palette = { [string]: Color3 }

local GAP = 6 -- between the tooltip and its target
local EDGE = 6 -- kept from the parent's edges
local MAX_WIDTH = 260
local Z = 60

local Tooltip = {}

function Tooltip.create(parent: GuiBase2d, palette: Palette)
	local label = Instance.new("TextLabel")
	label.Name = "Tooltip"
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.AnchorPoint = Vector2.new(0, 1)
	label.BackgroundColor3 = palette.menuBack
	label.BorderSizePixel = 0
	label.TextColor3 = palette.messageText
	label.FontFace = Theme.FONTS.body
	label.TextSize = 12
	label.LineHeight = 1.1
	label.RichText = true
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Visible = false
	label.ZIndex = Z
	label.Parent = parent :: Instance

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(MAX_WIDTH, math.huge)
	sizeConstraint.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = palette.menuBorder
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label

	local current: GuiObject? = nil
	local pending = 0 -- bumped by every show/hide, so a delayed show can tell it's stale
	local self = { label = label }

	-- Centered above the target, moved back inside the parent if needed
	local function place()
		local target = current
		if not target then
			return
		end
		local origin = parent.AbsolutePosition
		local width = label.AbsoluteSize.X
		local centerX = target.AbsolutePosition.X - origin.X + target.AbsoluteSize.X / 2
		local x = math.clamp(centerX - width / 2, EDGE, math.max(EDGE, parent.AbsoluteSize.X - width - EDGE))
		label.Position = UDim2.fromOffset(x, target.AbsolutePosition.Y - origin.Y - GAP)
	end
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	--[=[
		Shows the tooltip above `target` after the hover delay (right away
		with `immediate`). A hide() before then cancels it.
	]=]
	function self.show(target: GuiObject, text: string, immediate: boolean?)
		pending += 1
		local token = pending
		current = target
		local function reveal()
			if pending ~= token or current ~= target or not target.Parent then
				return
			end
			label.Text = text
			label.Visible = true
			place()
		end
		if immediate then
			reveal()
		else
			task.delay(Constants.TOOLTIP_DELAY, reveal)
		end
	end

	--[=[
		Hides the tooltip (only if it belongs to `target`, when given).
	]=]
	function self.hide(target: GuiObject?)
		if target and target ~= current then
			return
		end
		pending += 1
		current = nil
		label.Visible = false
	end

	function self.recolor(colors: Palette)
		label.BackgroundColor3 = colors.menuBack
		label.TextColor3 = colors.messageText
		stroke.Color = colors.menuBorder
	end

	return self
end

return Tooltip
