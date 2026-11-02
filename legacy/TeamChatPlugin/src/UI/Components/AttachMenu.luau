--!
-- AttachMenu
-- Creates the expandable plus-button menu (Discord-style) with Poll and File options.
-- Also creates the full-widget click catcher for closing the menu.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT
local MENU_WIDTH = Theme.MENU_WIDTH
local MENU_ITEM_HEIGHT = Theme.MENU_ITEM_HEIGHT
local INPUT_HEIGHT = Theme.INPUT_HEIGHT

local AttachMenu = {}

--!
-- Creates the menu frame and click catcher.
-- @param themeColors table - current theme color palette
-- @return Frame menuFrame, TextButton menuClickCatcher, TextButton menuItemPoll, TextButton menuItemFile
--!
function AttachMenu.create(themeColors)
	local menuFrame = Instance.new("Frame")
	menuFrame.Name = "Menu"
	menuFrame.Size = UDim2.new(0, MENU_WIDTH, 0, 0)
	menuFrame.AutomaticSize = Enum.AutomaticSize.Y
	menuFrame.AnchorPoint = Vector2.new(0, 1)
	menuFrame.Position = UDim2.new(0, 4, 1, -(INPUT_HEIGHT + 8))
	menuFrame.BackgroundColor3 = themeColors.menuBack
	menuFrame.BorderSizePixel = 0
	menuFrame.Visible = false
	menuFrame.ZIndex = 10

	local menuCorner = Instance.new("UICorner")
	menuCorner.CornerRadius = UDim.new(0, 8)
	menuCorner.Parent = menuFrame

	local menuStroke = Instance.new("UIStroke")
	menuStroke.Name = "MenuStroke"
	menuStroke.Color = themeColors.menuBorder
	menuStroke.Thickness = 1
	menuStroke.Parent = menuFrame

	local menuLayout = Instance.new("UIListLayout")
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Padding = UDim.new(0, 0)
	menuLayout.Parent = menuFrame

	local menuPad = Instance.new("UIPadding")
	menuPad.PaddingTop = UDim.new(0, 4)
	menuPad.PaddingBottom = UDim.new(0, 4)
	menuPad.Parent = menuFrame

	-- Menu item: Create Poll
	local menuItemPoll = Instance.new("TextButton")
	menuItemPoll.Name = "MenuItemPoll"
	menuItemPoll.Size = UDim2.new(1, 0, 0, MENU_ITEM_HEIGHT)
	menuItemPoll.BackgroundColor3 = themeColors.menuBack
	menuItemPoll.Text = "  \u{1F4CA}  Create Poll"
	menuItemPoll.TextColor3 = themeColors.menuItemText
	menuItemPoll.Font = FONT
	menuItemPoll.TextSize = 14
	menuItemPoll.TextXAlignment = Enum.TextXAlignment.Left
	menuItemPoll.AutoButtonColor = true
	menuItemPoll.BorderSizePixel = 0
	menuItemPoll.ZIndex = 11
	menuItemPoll.Parent = menuFrame

	-- Menu item: Attach File(s)
	local menuItemFile = Instance.new("TextButton")
	menuItemFile.Name = "MenuItemFile"
	menuItemFile.Size = UDim2.new(1, 0, 0, MENU_ITEM_HEIGHT)
	menuItemFile.BackgroundColor3 = themeColors.menuBack
	menuItemFile.Text = "  \u{1F4CE}  Attach File(s)"
	menuItemFile.TextColor3 = themeColors.menuItemText
	menuItemFile.Font = FONT
	menuItemFile.TextSize = 14
	menuItemFile.TextXAlignment = Enum.TextXAlignment.Left
	menuItemFile.AutoButtonColor = true
	menuItemFile.BorderSizePixel = 0
	menuItemFile.ZIndex = 11
	menuItemFile.Parent = menuFrame

	-- Click catcher (covers full container to detect outside clicks)
	local menuClickCatcher = Instance.new("TextButton")
	menuClickCatcher.Name = "MenuClickCatcher"
	menuClickCatcher.Size = UDim2.new(1, 0, 1, 0)
	menuClickCatcher.Position = UDim2.new(0, 0, 0, 0)
	menuClickCatcher.BackgroundTransparency = 1
	menuClickCatcher.Text = ""
	menuClickCatcher.AutoButtonColor = false
	menuClickCatcher.Visible = false
	menuClickCatcher.ZIndex = 9

	return menuFrame, menuClickCatcher, menuItemPoll, menuItemFile
end

--!
-- Re-themes the attach menu.
-- @param menuFrame Frame
-- @param themeColors table
--!
function AttachMenu.recolor(menuFrame, themeColors)
	menuFrame.BackgroundColor3 = themeColors.menuBack

	local stroke = menuFrame:FindFirstChild("MenuStroke")
	if stroke then
		stroke.Color = themeColors.menuBorder
	end

	for _, child in ipairs(menuFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child.BackgroundColor3 = themeColors.menuBack
			child.TextColor3 = themeColors.menuItemText
		end
	end
end

return AttachMenu