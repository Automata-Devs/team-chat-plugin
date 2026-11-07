--!strict
--[[
	ContextMenu

	The right-click menu on messages: Add Reaction, Reply, Edit Message (your
	own text messages only), Pin / Unpin Message, Copy and (red, below a
	divider) Delete (your own messages only), opened next to the cursor and
	kept inside the panel. Its item
	style (icon + label, red for destructive actions) is also used by the plus
	menu through createItem().

	Usage:
		local menu = ContextMenu.create({ container = container, widget = widget, getThemeColors = getTheme })
		menu.handlers.reply = function(timestamp) ... end
		menu.handlers.react = function(timestamp) ... end -- opens the emoji picker
		menu.show(timestamp, { canEdit = true, canDelete = true, canPin = true, pinned = false, canReact = true })
		menu.createItem("Create Poll", "createPoll", 1, false, plusMenuFrame)
]]

local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Animation = require(script.Parent.Parent.Animation)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Pointer = require(script.Parent.Pointer)

local FONTS = Theme.FONTS

local CURSOR_OFFSET = 2 -- gap between the cursor and the menu
local EDGE_MARGIN = 4 -- minimum gap to the panel's edges
local DANGER_HOVER_TRANSPARENCY = 0.85 -- red tint behind a hovered destructive item

type Palette = { [string]: Color3 }

export type Options = {
	container: Frame,
	widget: any, -- DockWidgetPluginGui (GetRelativeMousePosition)
	getThemeColors: () -> Palette,
}

export type Handlers = {
	reply: ((timestamp: number) -> ())?,
	edit: ((timestamp: number) -> ())?,
	copy: ((timestamp: number) -> ())?,
	delete: ((timestamp: number) -> ())?,
	pin: ((timestamp: number, pinned: boolean) -> ())?, -- pinned: pin it (false: unpin)
	-- Add Reaction: pick an emoji for it (messageId: the saved message's name, when known)
	react: ((timestamp: number, messageId: string?) -> ())?,
}

export type ShowOptions = {
	canEdit: boolean?,
	canDelete: boolean?,
	canPin: boolean?,
	pinned: boolean?,
	canReact: boolean?,
	messageId: string?,
}

export type ContextMenu = {
	frame: Frame,
	handlers: Handlers,
	show: (timestamp: number, options: ShowOptions?) -> (),
	hide: () -> (),
	recolor: () -> (),
	createItem: (
		text: string,
		iconKey: string,
		layoutOrder: number,
		danger: boolean?,
		parent: GuiObject?
	) -> TextButton,
}

local ContextMenu = {}

--[=[
	Builds the (hidden) menu inside `options.container`.
]=]
function ContextMenu.create(options: Options): ContextMenu
	local container = options.container
	local widget = options.widget
	local colors = options.getThemeColors

	local frame = Instance.new("Frame")
	frame.Name = "ContextMenu"
	frame.Size = UDim2.new(0, 160, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = colors().menuBack
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 20
	frame.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = colors().menuBorder
	stroke.Thickness = 1
	stroke.Parent = frame

	local shadow = Instance.new("UIShadow")
	shadow.BlurRadius = UDim.new(0, 12)
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Transparency = 0.5
	shadow.Parent = frame

	-- Every item made with createItem (this menu's and the plus menu's), for recolor()
	local items: { { icon: TextLabel, label: TextLabel, danger: boolean } } = {}

	local function textColor(danger: boolean): Color3
		local palette = colors()
		return if danger then palette.danger else (palette.menuItemText or palette.messageText)
	end

	local function createItem(
		text: string,
		iconKey: string,
		layoutOrder: number,
		danger: boolean?,
		parent: GuiObject?,
		textKey: string? -- Core/Language key for the label (the Name stays English)
	): TextButton
		local isDanger = danger == true

		local item = Instance.new("TextButton")
		item.Name = text .. "Item"
		item.Size = UDim2.new(1, 0, 0, 30)
		item.BackgroundTransparency = 1
		item.Text = ""
		item.AutoButtonColor = false
		item.LayoutOrder = layoutOrder
		item.ZIndex = 21
		item.Parent = parent or frame

		local itemCorner = Instance.new("UICorner")
		itemCorner.CornerRadius = UDim.new(0, 4)
		itemCorner.Parent = item

		local itemPadding = Instance.new("UIPadding")
		itemPadding.PaddingLeft = UDim.new(0, 8)
		itemPadding.PaddingRight = UDim.new(0, 8)
		itemPadding.Parent = item

		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, 16, 1, 0)
		icon.BackgroundTransparency = 1
		Icons.apply(icon, iconKey)
		icon.TextSize = 16
		icon.ZIndex = 22
		icon.Parent = item

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Position = UDim2.fromOffset(26, 0)
		label.Size = UDim2.new(1, -26, 1, 0)
		label.BackgroundTransparency = 1
		if textKey then
			Language.bind(label, "Text", textKey)
		else
			label.Text = text
		end
		label.FontFace = FONTS.medium
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = 22
		label.Parent = item

		local color = textColor(isDanger)
		icon.TextColor3 = color
		label.TextColor3 = color

		item.MouseEnter:Connect(function()
			local palette = colors()
			if isDanger then
				item.BackgroundColor3 = palette.danger
				item.BackgroundTransparency = DANGER_HOVER_TRANSPARENCY
			else
				item.BackgroundColor3 = palette.menuItemHover
				item.BackgroundTransparency = 0
			end
		end)
		item.MouseLeave:Connect(function()
			item.BackgroundTransparency = 1
		end)

		table.insert(items, { icon = icon, label = label, danger = isDanger })
		return item
	end

	local addReaction = createItem("Add Reaction", "emoji", 1, nil, nil, "menu.addReaction")
	local replyItem = createItem("Reply", "reply", 2, nil, nil, "menu.reply")
	local editItem = createItem("Edit Message", "edit", 3, nil, nil, "menu.edit")
	local pinItem = createItem("Pin Message", "pinned", 4, nil, nil, "menu.pin")
	local unpinItem = createItem("Unpin Message", "pinned", 4, nil, nil, "menu.unpin")
	local copyItem = createItem("Copy", "copy", 5, nil, nil, "menu.copy")

	-- Thin separator so the destructive action sits apart at the bottom
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = colors().menuBorder
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 6
	divider.ZIndex = 21
	divider.Parent = frame

	local deleteItem = createItem("Delete", "delete", 7, true, nil, "menu.delete")

	local menu: ContextMenu
	local targetTimestamp: number? = nil
	local targetMessageId: string? = nil
	-- Where the menu was opened (widget coordinates), so it can be re-placed
	-- once its automatic height is known.
	local cursor = Vector2.zero

	-- Next to the cursor, flipped left/up when it would overflow, clamped inside.
	local function place()
		local bounds = container.AbsoluteSize
		local size = frame.AbsoluteSize
		local point = cursor - (container.AbsolutePosition - widget.AbsolutePosition)
		local x = point.X + CURSOR_OFFSET
		local y = point.Y + CURSOR_OFFSET
		if x + size.X > bounds.X - EDGE_MARGIN then
			x = point.X - CURSOR_OFFSET - size.X
		end
		if y + size.Y > bounds.Y - EDGE_MARGIN then
			y = point.Y - CURSOR_OFFSET - size.Y
		end
		x = math.clamp(x, EDGE_MARGIN, math.max(EDGE_MARGIN, bounds.X - size.X - EDGE_MARGIN))
		y = math.clamp(y, EDGE_MARGIN, math.max(EDGE_MARGIN, bounds.Y - size.Y - EDGE_MARGIN))
		frame.Position = UDim2.fromOffset(x, y)
	end

	-- AutomaticSize: the height can settle after the menu is shown
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if frame.Visible then
			place()
		end
	end)

	local function hide()
		frame.Visible = false
		targetTimestamp = nil
		targetMessageId = nil
	end

	local function run(handler: ((number) -> ())?)
		if targetTimestamp and handler then
			handler(targetTimestamp)
		end
		hide()
	end

	replyItem.MouseButton1Click:Connect(function()
		run(menu.handlers.reply)
	end)
	editItem.MouseButton1Click:Connect(function()
		run(menu.handlers.edit)
	end)
	copyItem.MouseButton1Click:Connect(function()
		run(menu.handlers.copy)
	end)
	deleteItem.MouseButton1Click:Connect(function()
		run(menu.handlers.delete)
	end)
	pinItem.MouseButton1Click:Connect(function()
		local handler = menu.handlers.pin
		run(if handler
			then function(timestamp)
				handler(timestamp, true)
			end
			else nil)
	end)
	unpinItem.MouseButton1Click:Connect(function()
		local handler = menu.handlers.pin
		run(if handler
			then function(timestamp)
				handler(timestamp, false)
			end
			else nil)
	end)
	addReaction.MouseButton1Click:Connect(function()
		local handler = menu.handlers.react
		local messageId = targetMessageId
		run(if handler
			then function(timestamp)
				handler(timestamp, messageId)
			end
			else nil)
	end)

	-- Any click outside the menu closes it (its padding and divider do nothing)
	container.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if frame.Visible and Pointer.isInside(frame, input.Position) then
				return
			end
			hide()
		end
	end)

	menu = {
		frame = frame,
		handlers = {},
		createItem = createItem,
		hide = hide,
		show = function(timestamp: number, showOptions: ShowOptions?)
			targetTimestamp = timestamp
			targetMessageId = showOptions and showOptions.messageId
			editItem.Visible = showOptions ~= nil and showOptions.canEdit == true
			deleteItem.Visible = showOptions ~= nil and showOptions.canDelete == true
			local canPin = showOptions ~= nil and showOptions.canPin == true
			local pinned = showOptions ~= nil and showOptions.pinned == true
			pinItem.Visible = canPin and not pinned
			unpinItem.Visible = canPin and pinned
			addReaction.Visible = showOptions ~= nil and showOptions.canReact == true and menu.handlers.react ~= nil
			divider.Visible = deleteItem.Visible
			cursor = widget:GetRelativeMousePosition()
			frame.Visible = true
			place()
			Animation.fadeIn(frame, "quick")
			Animation.popIn(frame, 0.94, "smooth")
		end,
		recolor = function()
			local palette = colors()
			frame.BackgroundColor3 = palette.menuBack
			stroke.Color = palette.menuBorder
			divider.BackgroundColor3 = palette.menuBorder
			for _, entry in ipairs(items) do
				local color = textColor(entry.danger)
				entry.icon.TextColor3 = color
				entry.label.TextColor3 = color
			end
		end,
	}
	return menu
end

return ContextMenu
