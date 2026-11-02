--!
-- SystemMessage
-- Creates a system-style message (italic gray text, no sender name).
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT

local SystemMessage = {}

--!
-- Creates a system message container.
-- @param text string - the message text
-- @param themeColors table - current theme color palette
-- @return Frame - the system message container
--!
function SystemMessage.create(text, themeColors)
	local container = Instance.new("Frame")
	container.Name = "SystemMessage_" .. tostring(os.time()) .. "_" .. math.random(100000, 999999)
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.LayoutOrder = os.time() * 1000 + math.random(1, 999)
	container.BorderSizePixel = 0

	local containerLayout = Instance.new("UIListLayout")
	containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	containerLayout.Padding = UDim.new(0, -4)
	containerLayout.Parent = container

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextContent"
	textLabel.Font = FONT
	textLabel.TextSize = 13
	textLabel.TextColor3 = themeColors.timestamp
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

	local escaped = string.gsub(text, "<", "&lt;")
	escaped = string.gsub(escaped, ">", "&gt;")
	textLabel.Text = string.format('<i><font color="%s">%s</font></i>', Theme.toHex(themeColors.timestamp), escaped)

	return container
end

--!
-- Re-themes a system message container.
-- @param container Frame
-- @param themeColors table
--!
function SystemMessage.recolor(container, themeColors)
	local textLabel = container:FindFirstChild("TextContent")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.TextColor3 = themeColors.timestamp
		-- Rebuild the rich text with new theme color
		local text = string.match(textLabel.Text, ">(.-)</font></i>")
		if text then
			textLabel.Text = string.format('<i><font color="%s">%s</font></i>', Theme.toHex(themeColors.timestamp), text)
		end
	end
end

return SystemMessage