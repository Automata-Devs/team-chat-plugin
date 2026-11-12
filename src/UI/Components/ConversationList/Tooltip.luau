--[[
	Tooltip

	The sidebar's tooltip: next to the rail (names while collapsed, footer
	buttons), or above a footer button when expanded. It shows after
	hovering for Constants.TOOLTIP_DELAY; hiding (or another show) before
	then cancels it.
]]

local Constants = require(script.Parent.Parent.Parent.Parent.Config.Constants)
local Shared = require(script.Parent.Shared)
local Theme = require(script.Parent.Parent.Parent.Parent.Config.Theme)

local Tooltip = {}

function Tooltip.create(view: Shared.View, parent: Instance, frame: Frame)
	local colors = view.colors
	local label = Shared.label("SidebarTooltip", parent, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundTransparency = 0,
		BackgroundColor3 = colors.menuBack,
		TextColor3 = colors.messageText,
		FontFace = Theme.FONTS.semibold,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.None,
		RichText = true, -- names can carry the verified badge
		Visible = false,
		ZIndex = 60,
	})
	Shared.corner(label, UDim.new(0, 4))
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = colors.menuBorder
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label

	local token = 0

	local function place(target: GuiObject, text: string, above: boolean?)
		local origin = (parent :: any).AbsolutePosition
		label.Text = text
		if above then
			label.AnchorPoint = Vector2.new(0, 1)
			label.Position =
				UDim2.fromOffset(target.AbsolutePosition.X - origin.X, target.AbsolutePosition.Y - origin.Y - 6)
		else
			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.fromOffset(
				frame.AbsolutePosition.X - origin.X + frame.AbsoluteSize.X + 4,
				target.AbsolutePosition.Y - origin.Y + target.AbsoluteSize.Y / 2
			)
		end
		label.Visible = true
	end

	local self = {}

	function self.hide()
		token += 1
		label.Visible = false
	end

	--[=[
		Shows text next to target after the delay (above it when `above`).
		Rows show their names when the sidebar is expanded, so only `above`
		tooltips show then.
	]=]
	function self.show(target: GuiObject, text: string, above: boolean?)
		if view.list.expanded and not above then
			return
		end
		token += 1
		local shown = token
		task.delay(Constants.TOOLTIP_DELAY, function()
			if token == shown and target.Parent then
				place(target, text, above)
			end
		end)
	end

	function self.recolor()
		label.BackgroundColor3 = view.colors.menuBack
		label.TextColor3 = view.colors.messageText
		stroke.Color = view.colors.menuBorder
	end

	return self
end

return Tooltip
