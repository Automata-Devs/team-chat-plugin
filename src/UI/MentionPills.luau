--!strict
--[[
	MentionPills

	The rounded highlight behind each @mention, like Discord. RichText's <mark>
	can't round its corners, and a TextBox can't show RichText while you type,
	so the highlight is a small rounded frame laid over the mention: its
	position comes from measuring the text the way LinkHelper does. The frame
	is a see-through tint on top of the text, so mention text is drawn in a
	colour that comes out right under it (Theme mentionText).

	Works on message labels and on the message box. Re-measures when the
	text, size or wrapping changes.

	Usage:
		MentionPills.attach(label, palette)    -- once per label / text box
		MentionPills.recolor(label, palette)   -- after a theme change
]]

local Theme = require(script.Parent.Parent.Config.Theme)
local Mentions = require(script.Parent.Parent.Util.Mentions)
local LinkHelper = require(script.Parent.LinkHelper)

local PILL_PADDING = 2 -- extra width on each side of the mention
local PILL_RADIUS = 4

type TextObject = TextLabel | TextBox

local MentionPills = {}

local palettes: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local renders: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function clear(object: Instance)
	for _, child in ipairs(object:GetChildren()) do
		if child.Name == "MentionPill" then
			child:Destroy()
		end
	end
end

local function makePill(object: TextObject, x: number, y: number, width: number, height: number)
	local palette = palettes[object] or Theme.PALETTES.Dark
	local pill = Instance.new("Frame")
	pill.Name = "MentionPill"
	pill.Position = UDim2.fromOffset(math.floor(x - PILL_PADDING), math.floor(y))
	pill.Size = UDim2.fromOffset(math.ceil(width + PILL_PADDING * 2), math.ceil(height))
	pill.BackgroundColor3 = palette.mentionBack
	pill.BackgroundTransparency = Theme.MENTION_TRANSPARENCY
	pill.BorderSizePixel = 0
	pill.ZIndex = object.ZIndex
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, PILL_RADIUS)
	corner.Parent = pill
	pill.Parent = object
end

-- Where the text starts inside the object (its padding already moves children)
local function textTop(object: TextObject, contentHeight: number): number
	local padding = object:FindFirstChildOfClass("UIPadding")
	local inner = object.AbsoluteSize.Y
		- (if padding then padding.PaddingTop.Offset + padding.PaddingBottom.Offset else 0)
	if object.TextYAlignment == Enum.TextYAlignment.Center then
		return (inner - contentHeight) / 2
	elseif object.TextYAlignment == Enum.TextYAlignment.Bottom then
		return inner - contentHeight
	end
	return 0
end

local function innerWidth(object: TextObject): number
	local padding = object:FindFirstChildOfClass("UIPadding")
	return object.AbsoluteSize.X - (if padding then padding.PaddingLeft.Offset + padding.PaddingRight.Offset else 0)
end

--[=[
	Lays the pills over the mentions in the object's text now (measuring
	yields, so it runs in its own thread; a newer call wins).
]=]
function MentionPills.render(object: TextObject)
	local version = (renders[object] or 0) + 1
	renders[object] = version
	clear(object)
	local text = object.ContentText
	local mentions = Mentions.find(text)
	if #mentions == 0 or object.AbsoluteSize.X <= 0 then
		return
	end
	task.spawn(function()
		local font = object.FontFace
		local size = object.TextSize
		local width = innerWidth(object)
		local measure, firstCharOfLine = LinkHelper.measure, LinkHelper.firstCharOfLine
		local lineHeight = math.max(measure("Ag", font, size, width).Y, 1)
		local top = textTop(object, measure(text, font, size, width).Y)
		local rects = {}
		for _, mention in ipairs(mentions) do
			-- The line the mention's whole word ends on decides where it wraps to
			local wordEnd = (string.find(text, "%s", mention.finish + 1) or #text + 1) - 1
			local line = math.max(
				0,
				math.ceil(measure(string.sub(text, 1, wordEnd), font, size, width).Y / lineHeight - 0.01) - 1
			)
			local lineStart = if line == 0 then 1 else firstCharOfLine(text, font, size, width, line + 1, lineHeight)
			local x0 = if mention.start > lineStart
				then measure(string.sub(text, lineStart, mention.start - 1), font, size, width).X
				else 0
			local x1 = measure(string.sub(text, lineStart, mention.finish), font, size, width).X
			table.insert(rects, { x = x0, y = top + line * lineHeight, width = x1 - x0, height = lineHeight })
		end
		if renders[object] ~= version or not object.Parent then
			return
		end
		clear(object)
		for _, rect in ipairs(rects) do
			makePill(object, rect.x, rect.y, rect.width, rect.height)
		end
	end)
end

--[=[
	Keeps pills over the mentions in `object` as its text, size or wrapping
	changes.
]=]
function MentionPills.attach(object: TextObject, palette)
	palettes[object] = palette
	local function update()
		MentionPills.render(object)
	end
	object:GetPropertyChangedSignal("Text"):Connect(update)
	object:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	object:GetPropertyChangedSignal("TextSize"):Connect(update)
	update()
end

--[=[
	Re-themes an object's pills.
]=]
function MentionPills.recolor(object: TextObject, palette)
	palettes[object] = palette
	for _, child in ipairs(object:GetChildren()) do
		if child.Name == "MentionPill" and child:IsA("Frame") then
			child.BackgroundColor3 = palette.mentionBack
		end
	end
end

return MentionPills
