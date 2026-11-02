--!
-- EmptyState
-- Creates the "No messages yet" placeholder shown when the chat has no messages.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT

local EmptyState = {}

--!
-- Creates the empty state frame.
-- @param themeColors table - current theme color palette
-- @return Frame - the empty state container (parented by caller)
--!
function EmptyState.create(themeColors)
	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.Size = UDim2.new(1, 0, 1, -Theme.INPUT_HEIGHT)
	emptyState.Position = UDim2.new(0, 0, 0, 0)
	emptyState.BackgroundTransparency = 1
	emptyState.BorderSizePixel = 0

	local emptyLayout = Instance.new("UIListLayout")
	emptyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	emptyLayout.FillDirection = Enum.FillDirection.Vertical
	emptyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	emptyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	emptyLayout.Padding = UDim.new(0, 10)
	emptyLayout.Parent = emptyState

	local emptyIcon = Instance.new("TextLabel")
	emptyIcon.Name = "Icon"
	emptyIcon.Size = UDim2.new(0, 48, 0, 48)
	emptyIcon.BackgroundTransparency = 1
	emptyIcon.Text = "\u{1F4AC}"
	emptyIcon.TextSize = 36
	emptyIcon.Font = FONT
	emptyIcon.LayoutOrder = 1
	emptyIcon.BorderSizePixel = 0
	emptyIcon.Parent = emptyState

	local emptyTitleLabel = Instance.new("TextLabel")
	emptyTitleLabel.Name = "Title"
	emptyTitleLabel.Size = UDim2.new(1, -20, 0, 24)
	emptyTitleLabel.BackgroundTransparency = 1
	emptyTitleLabel.Text = "No messages yet"
	emptyTitleLabel.TextColor3 = themeColors.emptyTitle
	emptyTitleLabel.Font = Enum.Font.BuilderSansMedium
	emptyTitleLabel.TextSize = 16
	emptyTitleLabel.LayoutOrder = 2
	emptyTitleLabel.BorderSizePixel = 0
	emptyTitleLabel.Parent = emptyState

	local emptySubtitle = Instance.new("TextLabel")
	emptySubtitle.Name = "Subtitle"
	emptySubtitle.Size = UDim2.new(1, -30, 0, 20)
	emptySubtitle.BackgroundTransparency = 1
	emptySubtitle.Text = "Send a message to start the conversation!"
	emptySubtitle.TextColor3 = themeColors.emptySubtitle
	emptySubtitle.Font = FONT
	emptySubtitle.TextSize = 13
	emptySubtitle.TextWrapped = true
	emptySubtitle.LayoutOrder = 3
	emptySubtitle.BorderSizePixel = 0
	emptySubtitle.Parent = emptyState

	return emptyState
end

--!
-- Re-themes the empty state.
-- @param emptyState Frame - the empty state frame
-- @param themeColors table - current theme color palette
--!
function EmptyState.recolor(emptyState, themeColors)
	local titleLabel = emptyState:FindFirstChild("Title")
	if titleLabel then
		titleLabel.TextColor3 = themeColors.emptyTitle
	end
	local subtitle = emptyState:FindFirstChild("Subtitle")
	if subtitle then
		subtitle.TextColor3 = themeColors.emptySubtitle
	end
end

return EmptyState