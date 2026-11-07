--!strict
--[[
	Messages/Reactions

	The reactions under a message, styled like Roblox's chips: a capsule per
	emoji with how many people reacted and a round button to add another.
	Chips sit on a see-through tint of the text colour (so they suit any row
	tint) that brightens on hover and press; yours is filled with the text
	colour instead, like a selected Roblox chip. Clicking a chip adds or
	removes your reaction.

	Usage:
		Reactions.render(container, reactions, palette, {
			toggle = function(emoji) end,           -- a chip was clicked
			add = function() end,                   -- the add button was clicked
			hover = function(button, reaction) end, -- reaction is nil when the hover ends
		})
		Reactions.recolor(container, palette)
]]

local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS
local HEIGHT = 26
local EMOJI_SIZE = 16
local COUNT_SIZE = 14
local ICON_SIZE = 16

-- How see-through each chip's background is, by state. Others' reactions
-- are a tint of the text colour; yours are filled with it, softened a
-- little so it isn't glaring white (or black in Light).
local SURFACE = { rest = 0.9, hover = 0.84, press = 0.78 }
local SELECTED = { rest = 0.25, hover = 0.33, press = 0.4 }

type Palette = { [string]: Color3 }

export type Reaction = { emoji: string, count: number, mine: boolean, names: { string }? }

export type Handlers = {
	toggle: (emoji: string) -> (),
	add: () -> (),
	hover: ((button: GuiObject?, reaction: Reaction?) -> ())?,
}

local Reactions = {}

Reactions.LAYOUT_ORDER = 95 -- under the text, cards and buttons; above nothing

-- Each bar's palette since the last theme change (by recolor)
local palettes: { [Instance]: Palette } = setmetatable({}, { __mode = "k" }) :: any

local function capsule(parent: Instance)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(1, 0)
	object.Parent = parent
end

-- "rest", "hover" or "press", from the button's own attributes
local function stateOf(button: GuiButton): string
	if button:GetAttribute("Pressed") then
		return "press"
	elseif button:GetAttribute("Hovered") then
		return "hover"
	end
	return "rest"
end

local function paintPill(pill: TextButton, palette: Palette)
	local mine = pill:GetAttribute("Mine") == true
	local count = pill:GetAttribute("Count") or 0
	local emoji = pill:GetAttribute("Emoji") or ""
	pill.Text = string.format('<font size="%d">%s</font> %d', EMOJI_SIZE, emoji, count)
	pill.TextColor3 = if mine then palette.scrollBack else palette.messageText
	pill.BackgroundColor3 = palette.messageText
	pill.BackgroundTransparency = (if mine then SELECTED else SURFACE)[stateOf(pill)]
end

local function paintAdd(add: TextButton, palette: Palette)
	local state = stateOf(add)
	add.BackgroundColor3 = palette.messageText
	add.BackgroundTransparency = SURFACE[state]
	add.TextColor3 = if state == "rest" then palette.timestamp else palette.messageText
end

-- Hover and press states, repainted with the palette in use at the time
local function bindStates(button: TextButton, getPalette: () -> Palette, paint: (TextButton, Palette) -> ())
	local function set(attribute: string, on: boolean)
		button:SetAttribute(attribute, if on then true else nil)
		paint(button, getPalette())
	end
	button.MouseEnter:Connect(function()
		set("Hovered", true)
	end)
	button.MouseLeave:Connect(function()
		button:SetAttribute("Pressed", nil)
		set("Hovered", false)
	end)
	button.MouseButton1Down:Connect(function()
		set("Pressed", true)
	end)
	button.MouseButton1Up:Connect(function()
		set("Pressed", false)
	end)
end

--[=[
	Shows `reactions` under the message in `container` (a message row), or
	removes the bar when there are none. Rebuilt on every change.
]=]
function Reactions.render(container: Instance, reactions: { Reaction }, palette: Palette, handlers: Handlers)
	local old = container:FindFirstChild("Reactions")
	if old then
		old:Destroy()
	end
	if #reactions == 0 then
		return
	end

	local bar = Instance.new("Frame")
	bar.Name = "Reactions"
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, 0, 0, 0)
	bar.AutomaticSize = Enum.AutomaticSize.Y
	bar.LayoutOrder = Reactions.LAYOUT_ORDER
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Wraps = true
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = bar
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 2)
	padding.Parent = bar

	-- The palette now: a theme change repaints through recolor, which keeps
	-- the new one for the hover states
	local function currentPalette(): Palette
		return palettes[bar] or palette
	end

	for index, reaction in ipairs(reactions) do
		local pill = Instance.new("TextButton")
		pill.Name = "Reaction_" .. index
		pill.AutoButtonColor = false
		pill.BorderSizePixel = 0
		pill.Size = UDim2.fromOffset(0, HEIGHT)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.RichText = true
		pill.FontFace = FONTS.bold
		pill.TextSize = COUNT_SIZE
		pill.LayoutOrder = index
		pill:SetAttribute("Emoji", reaction.emoji)
		pill:SetAttribute("Count", reaction.count)
		pill:SetAttribute("Mine", reaction.mine)
		pill.Parent = bar
		capsule(pill)
		local pillPadding = Instance.new("UIPadding")
		pillPadding.PaddingLeft = UDim.new(0, 10)
		pillPadding.PaddingRight = UDim.new(0, 11)
		pillPadding.Parent = pill
		paintPill(pill, palette)
		bindStates(pill, currentPalette, paintPill)

		pill.MouseButton1Click:Connect(function()
			handlers.toggle(reaction.emoji)
		end)
		if handlers.hover then
			local hover = handlers.hover
			pill.MouseEnter:Connect(function()
				hover(pill, reaction)
			end)
			pill.MouseLeave:Connect(function()
				hover(nil, nil)
			end)
		end
	end

	-- Add another reaction: a round icon button
	local add = Instance.new("TextButton")
	add.Name = "AddReaction"
	add.AutoButtonColor = false
	add.BorderSizePixel = 0
	add.Size = UDim2.fromOffset(HEIGHT, HEIGHT)
	add.TextSize = ICON_SIZE
	add.LayoutOrder = #reactions + 1
	Icons.apply(add, "emoji")
	add.Parent = bar
	capsule(add)
	paintAdd(add, palette)
	bindStates(add, currentPalette, paintAdd)
	add.MouseButton1Click:Connect(function()
		handlers.add()
	end)
	if handlers.hover then
		local hover = handlers.hover
		add.MouseEnter:Connect(function()
			hover(add, nil)
		end)
		add.MouseLeave:Connect(function()
			hover(nil, nil)
		end)
	end

	bar.Parent = container
end

--[=[
	Re-themes the reactions under a message (after a theme change).
]=]
function Reactions.recolor(container: Instance, palette: Palette)
	local bar = container:FindFirstChild("Reactions")
	if not bar then
		return
	end
	palettes[bar] = palette
	for _, child in ipairs(bar:GetChildren()) do
		if child:IsA("TextButton") then
			if child.Name == "AddReaction" then
				paintAdd(child, palette)
			else
				paintPill(child, palette)
			end
		end
	end
end

return Reactions
