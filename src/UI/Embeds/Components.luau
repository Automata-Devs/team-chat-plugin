--!strict
--[[
	Components

	Buttons under a bot message, like Discord's message components: rows of
	up to five buttons in five styles (primary, secondary, success, danger,
	link). Link buttons open their URL; the others call onClick, which sends
	an interaction to the bot (Services/Bots.clickButton).

	Usage:
		local frame = Components.build(rows, palette, function(button) ... end)
		frame.LayoutOrder = 3
		frame.Parent = messageContainer
		Components.recolor(frame, palette)
]]

local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS
local BUTTON_HEIGHT = 30

local Components = {}

-- Background and text colour per style
local function colorsFor(style: string, palette): (Color3, Color3)
	if style == "primary" then
		return palette.sendButton, palette.sendButtonText
	elseif style == "success" then
		return palette.success, Color3.new(1, 1, 1)
	elseif style == "danger" then
		return palette.danger, Color3.new(1, 1, 1)
	end
	return palette.menuItemHover, palette.messageText -- secondary and link
end

local function paint(button: TextButton, palette)
	local background, text = colorsFor(button:GetAttribute("Style") or "secondary", palette)
	button.BackgroundColor3 = background
	button.TextColor3 = text
	button.BackgroundTransparency = if button:GetAttribute("Disabled") then 0.5 else 0
	button.TextTransparency = if button:GetAttribute("Disabled") then 0.4 else 0
end

--[=[
	Builds the rows. `rows`: { { { label, style, customId, url, disabled } } }.
]=]
function Components.build(rows: { { { [string]: any } } }, palette, onClick: ({ [string]: any }) -> ()): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Components"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 2)
	padding.Parent = frame

	for rowIndex, row in ipairs(rows) do
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = "Row_" .. rowIndex
		rowFrame.BackgroundTransparency = 1
		rowFrame.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
		rowFrame.LayoutOrder = rowIndex
		rowFrame.Parent = frame
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 6)
		rowLayout.Parent = rowFrame

		for index, info in ipairs(row) do
			local button = Instance.new("TextButton")
			button.Name = "Button_" .. tostring(info.customId or index)
			button.AutoButtonColor = not info.disabled
			button.BorderSizePixel = 0
			button.Size = UDim2.fromOffset(0, BUTTON_HEIGHT)
			button.AutomaticSize = Enum.AutomaticSize.X
			button.FontFace = FONTS.semibold
			button.TextSize = 13
			button.RichText = true
			button.Text = Icons.escape(info.label)
				.. (if info.style == "link" then "  " .. Icons.inline("openExternal", false, 12) else "")
			button.LayoutOrder = index
			button:SetAttribute("Style", info.style)
			button:SetAttribute("Disabled", info.disabled == true)
			button:SetAttribute("CustomId", info.customId)
			button.Parent = rowFrame
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = button
			local buttonPadding = Instance.new("UIPadding")
			buttonPadding.PaddingLeft = UDim.new(0, 14)
			buttonPadding.PaddingRight = UDim.new(0, 14)
			buttonPadding.Parent = button
			paint(button, palette)
			if not info.disabled then
				button.MouseButton1Click:Connect(function()
					onClick(info)
				end)
			end
		end
	end
	return frame
end

--[=[
	Re-themes a message's buttons.
]=]
function Components.recolor(frame: Instance, palette)
	for _, button in ipairs(frame:GetDescendants()) do
		if button:IsA("TextButton") then
			paint(button, palette)
		end
	end
end

return Components
