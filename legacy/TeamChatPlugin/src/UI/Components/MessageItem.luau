--!
-- MessageItem
-- Creates a message container frame with rich text and optional inline image.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local RichTextHelper = require(script.Parent.Parent.Parent.Utils.RichTextHelper)

local FONT = Theme.FONT
local MAX_IMAGE_HEIGHT = Theme.MAX_IMAGE_HEIGHT

local MessageItem = {}

--!
-- Creates a message container.
-- @param sender string - display name of the sender
-- @param timestamp number - message timestamp (used for LayoutOrder)
-- @param content string - message text content
-- @param imageUrl string? - optional image URL for inline image
-- @param themeColors table - current theme color palette
-- @return Frame - the message container
--!
function MessageItem.create(sender, timestamp, content, imageUrl, themeColors)
	local container = Instance.new("Frame")
	container.Name = "Message_" .. tostring(timestamp)
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Position = UDim2.new(0, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.LayoutOrder = timestamp
	container.BorderSizePixel = 0

	local containerLayout = Instance.new("UIListLayout")
	containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	containerLayout.Padding = UDim.new(0, -4)
	containerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	containerLayout.Parent = container

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextContent"
	textLabel.Font = FONT
	textLabel.TextSize = 14
	textLabel.TextColor3 = themeColors.messageText
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.new(1, 0, 0, 20)
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.RichText = true
	textLabel.TextWrapped = true
	textLabel.LayoutOrder = 1
	textLabel.BorderSizePixel = 0
	textLabel.Parent = container
	textLabel.Text = RichTextHelper.buildMessage(sender, content, timestamp, themeColors)

	if imageUrl and imageUrl ~= "" then
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "ImageAttachment"
		imageLabel.Image = imageUrl
		imageLabel.BackgroundColor3 = themeColors.scrollBack
		imageLabel.BorderColor3 = themeColors.imageBorder
		imageLabel.BorderSizePixel = 1
		imageLabel.ScaleType = Enum.ScaleType.Fit
		imageLabel.Size = UDim2.new(0, 200, 0, MAX_IMAGE_HEIGHT)
		imageLabel.LayoutOrder = 2
		imageLabel.Parent = container

		local imageCorner = Instance.new("UICorner")
		imageCorner.CornerRadius = UDim.new(0, 6)
		imageCorner.Parent = imageLabel

		imageLabel:GetPropertyChangedSignal("Image"):Connect(function()
			if imageLabel.Image == "" then
				imageLabel.Visible = false
			end
		end)
	end

	return container
end

--!
-- Re-themes an existing message container.
-- @param container Frame - the message container
-- @param themeColors table - current theme color palette
--!
function MessageItem.recolor(container, themeColors)
	local sender = container:GetAttribute("Sender")
	local content = container:GetAttribute("Content")
	local timestamp = container:GetAttribute("Timestamp")
	if not sender or not timestamp then return end
	if content == nil then content = "" end

	local textLabel = container:FindFirstChild("TextContent")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.TextColor3 = themeColors.messageText
		textLabel.Text = RichTextHelper.buildMessage(sender, content, timestamp, themeColors)
	end

	local imageLabel = container:FindFirstChild("ImageAttachment")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.BackgroundColor3 = themeColors.scrollBack
		imageLabel.BorderColor3 = themeColors.imageBorder
	end
end

return MessageItem