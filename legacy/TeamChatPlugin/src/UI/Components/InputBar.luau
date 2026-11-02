--!
-- InputBar
-- Creates the input area: attach button, text box, and send button.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT
local INPUT_HEIGHT = Theme.INPUT_HEIGHT

local InputBar = {}

--!
-- Creates the input frame with attach button, text box, and send button.
-- @param themeColors table - current theme color palette
-- @return Frame inputFrame, TextButton attachButton, TextBox textBox, TextButton sendButton
--!
function InputBar.create(themeColors)
	local inputFrame = Instance.new("Frame")
	inputFrame.Name = "InputFrame"
	inputFrame.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
	inputFrame.Position = UDim2.new(0, 0, 1, -INPUT_HEIGHT)
	inputFrame.BackgroundColor3 = themeColors.inputFrame
	inputFrame.BorderSizePixel = 0

	-- Attach (plus) button
	local attachButton = Instance.new("TextButton")
	attachButton.Name = "AttachButton"
	attachButton.Size = UDim2.new(0, 33, 0, 33)
	attachButton.Position = UDim2.new(0, 8, 0, 8)
	attachButton.BackgroundColor3 = themeColors.attachButton
	attachButton.Text = "+"
	attachButton.TextColor3 = themeColors.attachIcon
	attachButton.Font = Enum.Font.BuilderSansMedium
	attachButton.TextSize = 20
	attachButton.AutoButtonColor = true
	attachButton.BorderSizePixel = 0
	attachButton.Parent = inputFrame

	local attachCorner = Instance.new("UICorner")
	attachCorner.CornerRadius = UDim.new(0, 6)
	attachCorner.Parent = attachButton

	-- Text box for typing messages
	local textBox = Instance.new("TextBox")
	textBox.Name = "InputBox"
	textBox.Size = UDim2.new(1, -100, 0, 33)
	textBox.Position = UDim2.new(0, 45, 0, 8)
	textBox.BackgroundColor3 = themeColors.inputBox
	textBox.TextColor3 = themeColors.textBoxText
	textBox.PlaceholderText = "Type a message..."
	textBox.PlaceholderColor3 = themeColors.placeholder
	textBox.Font = FONT
	textBox.TextSize = 14
	textBox.TextScaled = false
	textBox.TextWrapped = true -- Wrap long messages onto multiple lines (like TextBoxExample)
	textBox.MultiLine = false
	textBox.TextYAlignment = Enum.TextYAlignment.Center
	textBox.Text = ""
	textBox.ClearTextOnFocus = false
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.BorderSizePixel = 0
	textBox.ClipsDescendants = false -- Let the box grow with wrapped text
	textBox.Parent = inputFrame

	local textBoxCorner = Instance.new("UICorner")
	textBoxCorner.CornerRadius = UDim.new(1, 0) -- Pill shape at single-line height
	textBoxCorner.Parent = textBox

	local textBoxPadding = Instance.new("UIPadding")
	textBoxPadding.PaddingLeft = UDim.new(0, 7)
	textBoxPadding.PaddingRight = UDim.new(0, 5)
	textBoxPadding.PaddingTop = UDim.new(0, 5)
	textBoxPadding.PaddingBottom = UDim.new(0, 5)
	textBoxPadding.Parent = textBox

	-- Send button
	local sendButton = Instance.new("TextButton")
	sendButton.Name = "SendButton"
	sendButton.Size = UDim2.new(0, 33, 0, 33)
	sendButton.Position = UDim2.new(1, -41, 0, 8)
	sendButton.BackgroundColor3 = themeColors.sendButton
	sendButton.Text = "\u{2192}"
	sendButton.TextColor3 = themeColors.sendButtonText
	sendButton.Font = Enum.Font.BuilderSansBold
	sendButton.TextSize = 20
	sendButton.AutoButtonColor = true
	sendButton.BorderSizePixel = 0
	sendButton.Parent = inputFrame

	local sendCorner = Instance.new("UICorner")
	sendCorner.CornerRadius = UDim.new(0, 6)
	sendCorner.Parent = sendButton

	-- Divider line above input
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Position = UDim2.new(0, 0, 1, -INPUT_HEIGHT)
	divider.BackgroundColor3 = themeColors.divider
	divider.BorderSizePixel = 0

	return inputFrame, attachButton, textBox, sendButton, divider
end

--!
-- Re-themes the input bar elements.
-- @param inputFrame Frame
-- @param themeColors table
--!
function InputBar.recolor(inputFrame, themeColors)
	inputFrame.BackgroundColor3 = themeColors.inputFrame

	local divider = inputFrame.Parent and inputFrame.Parent:FindFirstChild("Divider")
	if divider and divider:IsA("Frame") then
		divider.BackgroundColor3 = themeColors.divider
	end

	local attachButton = inputFrame:FindFirstChild("AttachButton")
	if attachButton then
		attachButton.BackgroundColor3 = themeColors.attachButton
		attachButton.TextColor3 = themeColors.attachIcon
	end

	local textBox = inputFrame:FindFirstChild("InputBox")
	if textBox then
		textBox.BackgroundColor3 = themeColors.inputBox
		textBox.TextColor3 = themeColors.textBoxText
		textBox.PlaceholderColor3 = themeColors.placeholder
	end

	local sendButton = inputFrame:FindFirstChild("SendButton")
	if sendButton then
		sendButton.BackgroundColor3 = themeColors.sendButton
		sendButton.TextColor3 = themeColors.sendButtonText
	end
end

return InputBar