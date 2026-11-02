--!
-- DropOverlay
-- Creates the drag-and-drop overlay shown when a PluginDrag enters the widget.
--!

local DropOverlay = {}

--!
-- Creates the drop overlay frame.
-- @param themeColors table - current theme color palette
-- @return Frame - the drop overlay (parented by caller)
--!
function DropOverlay.create(themeColors)
	local dropOverlay = Instance.new("Frame")
	dropOverlay.Name = "DropOverlay"
	dropOverlay.Size = UDim2.new(1, 0, 1, 0)
	dropOverlay.BackgroundColor3 = themeColors.sendButton
	dropOverlay.BackgroundTransparency = 0.85
	dropOverlay.BorderSizePixel = 0
	dropOverlay.Visible = false
	dropOverlay.ZIndex = 30

	local dropOverlayCorner = Instance.new("UICorner")
	dropOverlayCorner.CornerRadius = UDim.new(0, 8)
	dropOverlayCorner.Parent = dropOverlay

	local dropOverlayStroke = Instance.new("UIStroke")
	dropOverlayStroke.Name = "DropStroke"
	dropOverlayStroke.Color = themeColors.sendButton
	dropOverlayStroke.Thickness = 3
	dropOverlayStroke.Transparency = 0.4
	dropOverlayStroke.Parent = dropOverlay

	local dropLabel = Instance.new("TextLabel")
	dropLabel.Name = "DropLabel"
	dropLabel.Size = UDim2.new(1, -20, 0, 40)
	dropLabel.Position = UDim2.new(0, 0, 0.5, -20)
	dropLabel.BackgroundTransparency = 1
	dropLabel.Text = "\u{1F4E5} Drop to attach"
	dropLabel.TextColor3 = themeColors.sendButtonText
	dropLabel.Font = Enum.Font.BuilderSansBold
	dropLabel.TextSize = 16
	dropLabel.ZIndex = 31
	dropLabel.BorderSizePixel = 0
	dropLabel.Parent = dropOverlay

	return dropOverlay
end

--!
-- Re-themes the drop overlay.
-- @param dropOverlay Frame - the drop overlay frame
-- @param themeColors table - current theme color palette
--!
function DropOverlay.recolor(dropOverlay, themeColors)
	dropOverlay.BackgroundColor3 = themeColors.sendButton
	dropOverlay.BackgroundTransparency = 0.85

	local stroke = dropOverlay:FindFirstChild("DropStroke")
	if stroke then
		stroke.Color = themeColors.sendButton
	end

	local dropLabel = dropOverlay:FindFirstChild("DropLabel")
	if dropLabel then
		dropLabel.TextColor3 = themeColors.sendButtonText
	end
end

return DropOverlay