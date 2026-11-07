--!strict
--[[
	MentionPills

	The rounded highlight behind each @mention and #tag, like Discord, and
	the rounded outline around `inline code` (its fill is RichText's <mark>
	behind the text; this adds the border and round corners).
	RichText's <mark> can't round its corners, and a TextBox can't show
	RichText while you type, so the highlight is a small rounded frame laid
	over the mention: UI/TextLayout measures where it is (markdown included).
	The frame
	is a see-through tint on top of the text, so mention text is drawn in a
	colour that comes out right under it (Theme mentionText).

	Works on message labels and on the message box. Re-measures when the
	text, size or wrapping changes.

	Usage:
		MentionPills.attach(label, palette)    -- once per label / text box
		MentionPills.recolor(label, palette)   -- after a theme change
]]

local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local Mentions = require(script.Parent.Parent.Parent.Util.Mentions)
local TextLayout = require(script.Parent.TextLayout)

local PILL_PADDING = 2 -- extra width on each side of the mention
local PILL_RADIUS = 4
local CODE_RADIUS = 4

type TextObject = TextLabel | TextBox

local MentionPills = {}

local palettes: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local renders: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function clear(object: Instance)
	for _, child in ipairs(object:GetChildren()) do
		if child.Name == "MentionPill" or child.Name == "CodePill" then
			child:Destroy()
		end
	end
end

-- The outline around `code` (the box itself is the text's <mark>)
local function makeCodeOutline(object: TextObject, x: number, y: number, width: number, height: number)
	local palette = palettes[object] or Theme.PALETTES.Dark
	local outline = Instance.new("Frame")
	outline.Name = "CodePill"
	outline.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	outline.Size = UDim2.fromOffset(math.ceil(width), math.ceil(height))
	outline.BackgroundTransparency = 1
	outline.BorderSizePixel = 0
	outline.ZIndex = object.ZIndex
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CODE_RADIUS)
	corner.Parent = outline
	local stroke = Instance.new("UIStroke")
	stroke.Color = palette.codeBorder or palette.divider
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = outline
	outline.Parent = object
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

-- What gets a pill: @mentions and #[object] tags (and an outline: `code`).
-- A message's doc knows them as runs; plain text (the message box) is
-- searched directly.
local function targets(doc, isMarkdown: boolean): { { start: number, finish: number, code: boolean? } }
	local found = {}
	if isMarkdown then
		for _, run in ipairs(doc.runs) do
			if run.style.mention or run.style.tag then
				table.insert(found, { start = run.start, finish = run.finish })
			elseif run.style.code and not run.style.block then
				table.insert(found, { start = run.start, finish = run.finish, code = true })
			end
		end
		return found
	end
	for _, mention in ipairs(Mentions.find(doc.plain)) do
		table.insert(found, { start = mention.start, finish = mention.finish })
	end
	local position = 1
	while true do
		local start, finish = string.find(doc.plain, "#%[[^%]\n]+%]", position)
		if not start then
			break
		end
		table.insert(found, { start = start, finish = finish })
		position = finish + 1
	end
	return found
end

--[=[
	Lays the pills over the mentions and tags in the object's text now
	(measuring yields, so it runs in its own thread; a newer call wins).
]=]
function MentionPills.render(object: TextObject)
	local version = (renders[object] or 0) + 1
	renders[object] = version
	clear(object)
	local doc, isMarkdown = TextLayout.docOf(object)
	local found = targets(doc, isMarkdown)
	if #found == 0 or object.AbsoluteSize.X <= 0 then
		return
	end
	task.spawn(function()
		local rects = {}
		for _, target in ipairs(found) do
			local rect = TextLayout.rect(object, doc, target.start, target.finish, isMarkdown)
			if rect then
				table.insert(rects, { rect = rect, code = target.code })
			end
		end
		if renders[object] ~= version or not object.Parent then
			return
		end
		clear(object)
		for _, item in ipairs(rects) do
			local rect = item.rect
			if item.code then
				makeCodeOutline(object, rect.x, rect.y, rect.width, rect.height)
			else
				makePill(object, rect.x, rect.y, rect.width, rect.height)
			end
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
		elseif child.Name == "CodePill" then
			local stroke = child:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = palette.codeBorder or palette.divider
			end
		end
	end
end

return MentionPills
