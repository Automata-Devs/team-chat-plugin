--!strict
--[[
	PinsPanel

	The pinned messages of the open conversation, in a panel under the
	header's pin button (like Discord): each pin shows its author, date and
	message (markdown and all), with Jump (scroll to it and flash it) and
	Unpin. It closes on a click outside it, or on the pin button again.

	Usage:
		local pins = PinsPanel.create({ container = container, top = Header.HEIGHT, getThemeColors = getTheme,
			onJump = function(timestamp) ... end, onUnpin = function(timestamp) ... end })
		pins.setPins(list)   -- Services/Chat/Pins.list entries
		pins.toggle()
]]

local Author = require(script.Parent.Parent.Messages.Author)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local MessageText = require(script.Parent.Parent.Text.MessageText)
local Pointer = require(script.Parent.Pointer)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local TimeFormat = require(script.Parent.Parent.Parent.Util.TimeFormat)

local FONTS = Theme.FONTS
local WIDTH = 420
local EDGE = 8 -- from the chat's right edge
local TITLE_HEIGHT = 44
local AVATAR = 28
local Z = 15 -- over the chat, under the right-click menu (20) and dialogs (30+)

type Palette = { [string]: Color3 }

export type Options = {
	container: Frame,
	top: number, -- below the header
	getThemeColors: () -> Palette,
	onJump: (timestamp: number) -> (),
	onUnpin: (timestamp: number) -> (),
	onVisibility: ((open: boolean) -> ())?,
	ignoreClicksOn: { GuiObject }?, -- clicks here don't close it (the pin button toggles it)
}

local PinsPanel = {}

function PinsPanel.create(options: Options)
	local container = options.container
	local colors = options.getThemeColors
	local pins: { { [string]: any } } = {}

	local frame = Instance.new("Frame")
	frame.Name = "PinsPanel"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -EDGE, 0, options.top + 4)
	frame.BackgroundColor3 = colors().menuBack
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = Z
	frame.Parent = container
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = colors().menuBorder
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local shadow = Instance.new("UIShadow")
	shadow.BlurRadius = UDim.new(0, 16)
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Transparency = 0.5
	shadow.Parent = frame

	-- Title bar: a pin and "Pinned Messages"
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 0)
	title.Size = UDim2.new(1, -28, 0, TITLE_HEIGHT)
	title.FontFace = FONTS.semibold
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = Z + 1
	title.Parent = frame
	local titleDivider = Instance.new("Frame")
	titleDivider.Name = "Divider"
	titleDivider.Position = UDim2.fromOffset(0, TITLE_HEIGHT)
	titleDivider.Size = UDim2.new(1, 0, 0, 1)
	titleDivider.BorderSizePixel = 0
	titleDivider.ZIndex = Z + 1
	titleDivider.Parent = frame

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(0, TITLE_HEIGHT + 1)
	list.Size = UDim2.new(1, 0, 1, -(TITLE_HEIGHT + 1))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ZIndex = Z + 1
	list.Parent = frame
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = list
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 10)
	listPadding.PaddingBottom = UDim.new(0, 10)
	listPadding.PaddingLeft = UDim.new(0, 10)
	listPadding.PaddingRight = UDim.new(0, 12)
	listPadding.Parent = list

	local self = { frame = frame }

	-- What a pinned poll, file or image shows instead of its text
	local function textOf(entry): string
		if entry.messageType == "Poll" and entry.pollData then
			return "\u{1F4CA} " .. tostring(entry.pollData.question or "")
		elseif entry.messageType == "File" then
			return "\u{1F4CE} "
				.. tostring(entry.fileName or "")
				.. (if (entry.content or "") ~= "" then "\n" .. entry.content else "")
		elseif (entry.content or "") == "" and entry.imageUrl then
			return "\u{1F5BC}\u{FE0F} " .. Language.t("pins.image")
		end
		return entry.content or ""
	end

	local function button(parent: Instance, name: string, text: string, order: number, palette: Palette): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.AutomaticSize = Enum.AutomaticSize.X
		b.Size = UDim2.fromOffset(0, 22)
		b.BackgroundColor3 = palette.menuItemHover
		b.AutoButtonColor = true
		b.FontFace = FONTS.semibold
		b.TextSize = 12
		b.TextColor3 = palette.messageText
		b.Text = text
		b.LayoutOrder = order
		b.ZIndex = Z + 3
		b.Parent = parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = b
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 8)
		p.PaddingRight = UDim.new(0, 8)
		p.Parent = b
		return b
	end

	local function card(entry, order: number, palette: Palette)
		local item = Instance.new("Frame")
		item.Name = "Pin_" .. tostring(entry.timestamp)
		item.BackgroundColor3 = palette.scrollBack
		item.BorderSizePixel = 0
		item.Size = UDim2.new(1, 0, 0, 0)
		item.AutomaticSize = Enum.AutomaticSize.Y
		item.LayoutOrder = order
		item.ZIndex = Z + 2
		item:SetAttribute("Timestamp", entry.timestamp)
		item.Parent = list
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = item
		local s = Instance.new("UIStroke")
		s.Color = palette.divider
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = item
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, AVATAR + 18)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = item
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 2)
		layout.Parent = item

		-- Name, date and the buttons in one row; the avatar hangs left of it
		local row = Instance.new("Frame")
		row.Name = "Header"
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 22)
		row.LayoutOrder = 1
		row.ZIndex = Z + 2
		row.Parent = item

		local senderId = entry.senderId or 0
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.Position = UDim2.fromOffset(-(AVATAR + 8), 0)
		avatar.Size = UDim2.fromOffset(AVATAR, AVATAR)
		avatar.BackgroundColor3 = palette.menuItemHover
		avatar.ZIndex = Z + 3
		avatar.Image = if senderId > 0
			then "rbxthumb://type=AvatarHeadShot&id=" .. tostring(senderId) .. "&w=48&h=48"
			else ""
		avatar.Parent = row
		local ac = Instance.new("UICorner")
		ac.CornerRadius = UDim.new(1, 0)
		ac.Parent = avatar

		local name = Instance.new("TextLabel")
		name.Name = "Name"
		name.BackgroundTransparency = 1
		name.AutomaticSize = Enum.AutomaticSize.X
		name.Size = UDim2.fromScale(0, 1)
		name.FontFace = FONTS.semibold
		name.TextSize = 14
		name.TextColor3 = palette.messageText
		name.Text = Icons.escape(Author.nameOf(entry.sender or "", senderId))
		name.RichText = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = Z + 3
		name.Parent = row
		local when = Instance.new("TextLabel")
		when.Name = "Time"
		when.BackgroundTransparency = 1
		when.AutomaticSize = Enum.AutomaticSize.X
		when.Size = UDim2.fromScale(0, 1)
		when.FontFace = FONTS.body
		when.TextSize = 11
		when.TextColor3 = palette.timestamp
		local clock = TimeFormat.formatPlain(entry.timestamp)
		when.Text = os.date("%d/%m/%Y", entry.timestamp) .. (if clock ~= "" then " " .. clock else "")
		when.TextXAlignment = Enum.TextXAlignment.Left
		when.ZIndex = Z + 3
		when.Parent = row
		local function placeTime()
			when.Position = UDim2.fromOffset(name.AbsoluteSize.X + 6, 0)
		end
		name:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTime)
		placeTime()

		local actions = Instance.new("Frame")
		actions.Name = "Actions"
		actions.BackgroundTransparency = 1
		actions.AnchorPoint = Vector2.new(1, 0)
		actions.Position = UDim2.fromScale(1, 0)
		actions.AutomaticSize = Enum.AutomaticSize.X
		actions.Size = UDim2.fromScale(0, 1)
		actions.ZIndex = Z + 3
		actions.Parent = row
		local actionsLayout = Instance.new("UIListLayout")
		actionsLayout.FillDirection = Enum.FillDirection.Horizontal
		actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		actionsLayout.Padding = UDim.new(0, 4)
		actionsLayout.Parent = actions
		button(actions, "Jump", Language.t("pins.jump"), 1, palette).MouseButton1Click:Connect(function()
			self.close()
			options.onJump(entry.timestamp)
		end)
		local unpin = button(actions, "Unpin", "", 2, palette)
		Icons.apply(unpin, "close")
		unpin.TextSize = 14
		unpin.MouseButton1Click:Connect(function()
			options.onUnpin(entry.timestamp)
		end)

		-- The message, with its markdown
		local text = Instance.new("TextLabel")
		text.Name = "TextContent"
		text.BackgroundTransparency = 1
		text.Size = UDim2.new(1, 0, 0, 0)
		text.AutomaticSize = Enum.AutomaticSize.Y
		text.FontFace = FONTS.body
		text.TextSize = 14
		text.TextColor3 = palette.messageText
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.TextWrapped = true
		text.RichText = true
		text.LayoutOrder = 2
		text.ZIndex = Z + 3
		text.Parent = item
		MessageText.set(text, textOf(entry), palette, { edited = entry.editedAt ~= nil })
		MessageText.attachClicks(text)
	end

	-- Up to 420 wide and 70% of the chat's height (it scrolls after that)
	local function place()
		local width = math.min(WIDTH, container.AbsoluteSize.X - EDGE * 2)
		local maxHeight = math.max(120, (container.AbsoluteSize.Y - options.top) * 0.7)
		local wanted = TITLE_HEIGHT + 1 + list.AbsoluteCanvasSize.Y
		frame.Size = UDim2.fromOffset(width, math.clamp(wanted, 120, maxHeight))
	end
	list:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(place)
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	local function render()
		local palette = colors()
		frame.BackgroundColor3 = palette.menuBack
		stroke.Color = palette.menuBorder
		titleDivider.BackgroundColor3 = palette.menuBorder
		title.TextColor3 = palette.messageText
		title.Text = Language.t("pins.title")
		list.ScrollBarImageColor3 = palette.scrollBar
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if #pins == 0 then
			local empty = Instance.new("TextLabel")
			empty.Name = "Empty"
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 0)
			empty.AutomaticSize = Enum.AutomaticSize.Y
			empty.FontFace = FONTS.body
			empty.TextSize = 13
			empty.TextWrapped = true
			empty.RichText = true
			empty.TextColor3 = palette.timestamp
			empty.Text = "<b>" .. Language.t("pins.empty") .. "</b>\n" .. Language.t("pins.emptyHint")
			empty.ZIndex = Z + 2
			empty.Parent = list
		end
		for index, entry in ipairs(pins) do
			card(entry, index, palette)
		end
		place()
	end

	function self.setPins(newPins: { { [string]: any } })
		pins = newPins
		if frame.Visible then
			render()
		end
	end
	function self.isOpen(): boolean
		return frame.Visible
	end
	function self.open()
		render()
		frame.Visible = true
		list.CanvasPosition = Vector2.zero
		if options.onVisibility then
			options.onVisibility(true)
		end
	end
	function self.close()
		if not frame.Visible then
			return
		end
		frame.Visible = false
		if options.onVisibility then
			options.onVisibility(false)
		end
	end
	function self.toggle()
		if frame.Visible then
			self.close()
		else
			self.open()
		end
	end
	function self.recolor()
		if frame.Visible then
			render()
		end
	end

	-- A click outside closes it
	container.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not frame.Visible then
			return
		end
		if Pointer.isInside(frame, input.Position) then
			return
		end
		for _, ignored in ipairs(options.ignoreClicksOn or {}) do
			if Pointer.isInside(ignored, input.Position) then
				return
			end
		end
		self.close()
	end)

	return self
end

return PinsPanel
