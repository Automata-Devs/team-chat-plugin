--!strict
--[[
	Messages/Reactions

	The reactions under a message, like Discord: a pill per emoji with how
	many people reacted (yours outlined in the accent colour) and a button
	to add another. Clicking a pill adds or removes your reaction.

	Usage:
		Reactions.render(container, reactions, palette, {
			toggle = function(emoji) end,           -- a pill was clicked
			add = function() end,                   -- the add button was clicked
			hover = function(button, reaction) end, -- reaction is nil when the hover ends
		})
		Reactions.recolor(container, palette)
]]

local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS
local HEIGHT = 24
local MINE_TINT = 0.82 -- how see-through your reactions' accent background is

type Palette = { [string]: Color3 }

export type Reaction = { emoji: string, count: number, mine: boolean, names: { string }? }

export type Handlers = {
	toggle: (emoji: string) -> (),
	add: () -> (),
	hover: ((button: GuiObject?, reaction: Reaction?) -> ())?,
}

local Reactions = {}

Reactions.LAYOUT_ORDER = 95 -- under the text, cards and buttons; above nothing

local function corner(parent: Instance)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, 8)
	object.Parent = parent
end

local function paintPill(pill: TextButton, palette: Palette)
	local mine = pill:GetAttribute("Mine") == true
	local count = pill:GetAttribute("Count") or 0
	local emoji = pill:GetAttribute("Emoji") or ""
	local countColor = if mine then palette.sendButton else palette.timestamp
	pill.Text = string.format('%s <font color="#%s"><b>%d</b></font>', emoji, countColor:ToHex(), count)
	pill.TextColor3 = palette.messageText
	pill.BackgroundColor3 = if mine then palette.sendButton else palette.inputBox
	pill.BackgroundTransparency = if mine then MINE_TINT else 0
	local stroke = pill:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if mine then palette.sendButton else palette.divider
		stroke.Transparency = if mine then 0 else 1
	end
end

local function paintAdd(add: TextButton, palette: Palette)
	add.BackgroundColor3 = palette.inputBox
	add.TextColor3 = palette.timestamp
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
	layout.Padding = UDim.new(0, 4)
	layout.Parent = bar
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 2)
	padding.PaddingBottom = UDim.new(0, 2)
	padding.Parent = bar

	for index, reaction in ipairs(reactions) do
		local pill = Instance.new("TextButton")
		pill.Name = "Reaction_" .. index
		pill.AutoButtonColor = false
		pill.BorderSizePixel = 0
		pill.Size = UDim2.fromOffset(0, HEIGHT)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.RichText = true
		pill.FontFace = FONTS.medium
		pill.TextSize = 14
		pill.LayoutOrder = index
		pill:SetAttribute("Emoji", reaction.emoji)
		pill:SetAttribute("Count", reaction.count)
		pill:SetAttribute("Mine", reaction.mine)
		pill.Parent = bar
		corner(pill)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 1
		stroke.Parent = pill
		local pillPadding = Instance.new("UIPadding")
		pillPadding.PaddingLeft = UDim.new(0, 8)
		pillPadding.PaddingRight = UDim.new(0, 8)
		pillPadding.Parent = pill
		paintPill(pill, palette)

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

	-- Add another reaction
	local add = Instance.new("TextButton")
	add.Name = "AddReaction"
	add.AutoButtonColor = false
	add.BorderSizePixel = 0
	add.Size = UDim2.fromOffset(30, HEIGHT)
	add.TextSize = 15
	add.LayoutOrder = #reactions + 1
	Icons.apply(add, "emoji")
	add.Parent = bar
	corner(add)
	paintAdd(add, palette)
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
