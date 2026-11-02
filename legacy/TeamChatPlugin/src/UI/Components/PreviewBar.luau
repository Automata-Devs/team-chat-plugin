--!
-- PreviewBar
-- Creates the pending attachment preview bar shown above the input area.
-- Manages thumbnail, label, and remove button.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT
local PREVIEW_HEIGHT = Theme.PREVIEW_HEIGHT

local PreviewBar = {}

--!
-- Creates the preview bar frame.
-- @param themeColors table - current theme color palette
-- @return Frame - the preview bar (parented by caller)
--!
function PreviewBar.create(themeColors)
	local previewBar = Instance.new("Frame")
	previewBar.Name = "PreviewBar"
	previewBar.Size = UDim2.new(1, 0, 0, PREVIEW_HEIGHT)
	previewBar.Position = UDim2.new(0, 0, 1, -(Theme.INPUT_HEIGHT + PREVIEW_HEIGHT))
	previewBar.BackgroundColor3 = themeColors.inputFrame
	previewBar.BorderSizePixel = 0
	previewBar.Visible = false
	previewBar.ZIndex = 5

	local previewPadding = Instance.new("UIPadding")
	previewPadding.PaddingLeft = UDim.new(0, 8)
	previewPadding.PaddingRight = UDim.new(0, 8)
	previewPadding.PaddingTop = UDim.new(0, 4)
	previewPadding.PaddingBottom = UDim.new(0, 4)
	previewPadding.Parent = previewBar

	local previewThumbnail = Instance.new("ImageLabel")
	previewThumbnail.Name = "Thumbnail"
	previewThumbnail.Size = UDim2.new(0, 28, 0, 28)
	previewThumbnail.Position = UDim2.new(0, 0, 0.5, -14)
	previewThumbnail.BackgroundColor3 = themeColors.scrollBack
	previewThumbnail.BorderColor3 = themeColors.previewBorder
	previewThumbnail.BorderSizePixel = 1
	previewThumbnail.ScaleType = Enum.ScaleType.Fit
	previewThumbnail.ZIndex = 6
	previewThumbnail.Parent = previewBar

	local previewThumbCorner = Instance.new("UICorner")
	previewThumbCorner.CornerRadius = UDim.new(0, 4)
	previewThumbCorner.Parent = previewThumbnail

	local previewLabel = Instance.new("TextLabel")
	previewLabel.Name = "Label"
	previewLabel.Size = UDim2.new(1, -70, 1, 0)
	previewLabel.Position = UDim2.new(0, 36, 0, 0)
	previewLabel.BackgroundTransparency = 1
	previewLabel.Text = "Image attached"
	previewLabel.TextColor3 = themeColors.messageText
	previewLabel.Font = FONT
	previewLabel.TextSize = 12
	previewLabel.TextXAlignment = Enum.TextXAlignment.Left
	previewLabel.ZIndex = 6
	previewLabel.BorderSizePixel = 0
	previewLabel.Parent = previewBar

	local previewRemove = Instance.new("TextButton")
	previewRemove.Name = "Remove"
	previewRemove.Size = UDim2.new(0, 24, 0, 24)
	previewRemove.Position = UDim2.new(1, -24, 0.5, -12)
	previewRemove.BackgroundColor3 = themeColors.attachButton
	previewRemove.Text = "\u{00D7}"
	previewRemove.TextColor3 = themeColors.attachIcon
	previewRemove.Font = FONT
	previewRemove.TextSize = 12
	previewRemove.AutoButtonColor = true
	previewRemove.ZIndex = 6
	previewRemove.BorderSizePixel = 0
	previewRemove.Parent = previewBar

	local previewRemoveCorner = Instance.new("UICorner")
	previewRemoveCorner.CornerRadius = UDim.new(0, 4)
	previewRemoveCorner.Parent = previewRemove

	return previewBar
end

--!
-- Re-themes the preview bar.
-- @param previewBar Frame - the preview bar frame
-- @param themeColors table - current theme color palette
--!
function PreviewBar.recolor(previewBar, themeColors)
	previewBar.BackgroundColor3 = themeColors.inputFrame

	local thumbnail = previewBar:FindFirstChild("Thumbnail")
	if thumbnail then
		thumbnail.BackgroundColor3 = themeColors.scrollBack
		thumbnail.BorderColor3 = themeColors.previewBorder
	end

	local label = previewBar:FindFirstChild("Label")
	if label then
		label.TextColor3 = themeColors.messageText
	end

	local remove = previewBar:FindFirstChild("Remove")
	if remove then
		remove.BackgroundColor3 = themeColors.attachButton
		remove.TextColor3 = themeColors.attachIcon
	end
end

return PreviewBar