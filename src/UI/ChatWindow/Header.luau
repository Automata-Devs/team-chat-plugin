--!strict
--[[
	Header

	The bar at the top of the chat: the open conversation ("Team Chat", or a
	DM's name with the verified badge when they're verified and their
	@username in small muted text). The plugin version is in the widget's
	title instead.

	Usage:
		local header = Header.create({ container = container, getThemeColors = getTheme })
		header.setTitle("builderman", { verified = true, subtitle = "@builderman" })
		header.recolor()
]]

local BadgeIcons = require(script.Parent.Parent.Components.BadgeIcons)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local HEIGHT = 36
local BADGE_SIZE = 15

type Palette = { [string]: Color3 }

export type TitleOptions = { verified: boolean?, subtitle: string? }

export type Header = {
	frame: Frame,
	setTitle: (title: string, options: TitleOptions?) -> (),
	recolor: () -> (),
}

local Header = {}

Header.HEIGHT = HEIGHT

--[=[
	Builds the header at the top of `options.container`.
]=]
function Header.create(options: { container: Frame, getThemeColors: () -> Palette }): Header
	local colors = options.getThemeColors

	local frame = Instance.new("Frame")
	frame.Name = "TopBar"
	frame.Size = UDim2.new(1, 0, 0, HEIGHT)
	frame.BackgroundColor3 = colors().inputFrame
	frame.BorderSizePixel = 0
	frame.ZIndex = 5
	frame.Parent = options.container

	-- Title, verified badge and @username in a row
	local row = Instance.new("Frame")
	row.Name = "TitleRow"
	row.Position = UDim2.fromOffset(12, 0)
	row.Size = UDim2.new(1, -24, 1, 0)
	row.BackgroundTransparency = 1
	row.ZIndex = 5
	row.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.fromScale(0, 1)
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = Theme.FONTS.heading
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = colors().messageText
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.LayoutOrder = 1
	titleLabel.ZIndex = 5
	titleLabel.Parent = row
	local shrink = Instance.new("UIFlexItem")
	shrink.FlexMode = Enum.UIFlexMode.Shrink
	shrink.Parent = titleLabel

	local badgeSlot = Instance.new("Frame")
	badgeSlot.Name = "Badges"
	badgeSlot.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
	badgeSlot.BackgroundTransparency = 1
	badgeSlot.LayoutOrder = 2
	badgeSlot.Visible = false
	badgeSlot.Parent = row
	local verifiedIcon = BadgeIcons.create(BadgeIcons.VERIFIED, BADGE_SIZE)
	verifiedIcon.ZIndex = 5
	for _, child in ipairs(verifiedIcon:GetDescendants()) do
		if child:IsA("GuiObject") then
			child.ZIndex = 5
		end
	end
	verifiedIcon.Parent = badgeSlot

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.fromScale(0, 1)
	subtitle.AutomaticSize = Enum.AutomaticSize.X
	subtitle.BackgroundTransparency = 1
	subtitle.FontFace = Theme.FONTS.body
	subtitle.TextSize = 12
	subtitle.TextColor3 = colors().timestamp
	subtitle.LayoutOrder = 3
	subtitle.ZIndex = 5
	subtitle.Visible = false
	subtitle.Parent = row

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(0, 1)
	divider.Position = UDim2.new(0, 0, 1, 0)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = colors().divider
	divider.BorderSizePixel = 0
	divider.ZIndex = 5
	divider.Parent = frame

	return {
		frame = frame,
		setTitle = function(newTitle: string, titleOptions: TitleOptions?)
			titleLabel.Text = Icons.escape(newTitle)
			badgeSlot.Visible = titleOptions ~= nil and titleOptions.verified == true
			local sub = titleOptions and titleOptions.subtitle
			subtitle.Text = if sub then Icons.escape(sub) else ""
			subtitle.Visible = sub ~= nil and sub ~= ""
		end,
		recolor = function()
			local palette = colors()
			frame.BackgroundColor3 = palette.inputFrame
			titleLabel.TextColor3 = palette.messageText
			subtitle.TextColor3 = palette.timestamp
			divider.BackgroundColor3 = palette.divider
		end,
	}
end

return Header
