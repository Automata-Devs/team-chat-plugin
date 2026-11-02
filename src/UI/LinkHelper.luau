--!strict
--[[
	LinkHelper

	Makes links inside a message's TextLabel clickable. Roblox RichText has no
	hyperlinks, so a click is mapped to a character by measuring the label's
	text (TextService) and checked against the link ranges from Util/Links.
	Plugins can't change the mouse cursor, so links are only underlined.

	Usage:
		local meta = Links.buildMeta(sender, content, timestamp)
		LinkHelper.attach(textLabel, meta, function(url)
			-- couldn't open: it was copied to the clipboard
		end)
]]

local TextService = game:GetService("TextService")

local Browser = require(script.Parent.Parent.Core.Browser)
local Links = require(script.Parent.Parent.Util.Links)
local TimeFormat = require(script.Parent.Parent.Util.TimeFormat)

type LinkMeta = Links.LinkMeta

local LinkHelper = {}

-- Measures text with the same engine (and font face) the TextLabel uses for wrapping.
local function measure(text: string, font: Font, textSize: number, width: number): Vector2
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = font
	params.Size = textSize
	params.Width = width
	local ok, size = pcall(TextService.GetTextBoundsAsync, TextService, params)
	params:Destroy()
	return if ok then size else Vector2.zero
end

-- Measured line height per label (keyed by text + width); weak so labels can be collected
local lineHeightCache: { [TextLabel]: { key: string, lineHeight: number } } = setmetatable({}, { __mode = "k" }) :: any

-- Smallest prefix of `text` whose height reaches `lineCount` lines (binary search).
local function firstCharOfLine(
	text: string,
	font: Font,
	textSize: number,
	width: number,
	lineCount: number,
	lineHeight: number
): number
	local low, high = 1, #text
	while low < high do
		local mid = (low + high) // 2
		if measure(string.sub(text, 1, mid), font, textSize, width).Y >= lineCount * lineHeight - 0.5 then
			high = mid
		else
			low = mid + 1
		end
	end
	return low
end

-- Shared with MentionPills, which places highlights by the same measurements
LinkHelper.measure = measure
LinkHelper.firstCharOfLine = firstCharOfLine

--[=[
	The link under a point (relative to the label's top-left corner), or nil.
]=]
function LinkHelper.hitTest(textLabel: TextLabel, meta: LinkMeta, mouseX: number, mouseY: number): Links.Link?
	local width = textLabel.AbsoluteSize.X
	if width <= 0 or mouseY < 0 then
		return nil
	end
	-- The clock format / timestamp setting may have changed since the label was built.
	if TimeFormat.format(meta.timestamp) ~= meta.timeStr then
		Links.relayout(meta)
	end

	local font = textLabel.FontFace
	local textSize = textLabel.TextSize
	local text = meta.plainText
	if #text == 0 then
		return nil
	end

	local cacheKey = text .. "|" .. tostring(width)
	local cache = lineHeightCache[textLabel]
	if not cache or cache.key ~= cacheKey then
		cache = { key = cacheKey, lineHeight = math.max(measure("Ag", font, textSize, width).Y, 1) }
		lineHeightCache[textLabel] = cache
	end
	local lineHeight = cache.lineHeight

	local totalLines = math.max(1, math.ceil(measure(text, font, textSize, width).Y / lineHeight - 0.01))
	local line = math.floor(mouseY / lineHeight)
	if line >= totalLines then
		return nil
	end

	local lineStart = firstCharOfLine(text, font, textSize, width, line + 1, lineHeight)
	local lineEnd = #text
	if line + 1 < totalLines then
		lineEnd = firstCharOfLine(text, font, textSize, width, line + 2, lineHeight) - 1
	end
	if lineEnd < lineStart then
		return nil
	end

	-- Largest prefix of the line that fits before mouseX
	local lineText = string.sub(text, lineStart, lineEnd)
	local low, high = 0, #lineText
	while low < high do
		local mid = math.ceil((low + high) / 2)
		if measure(string.sub(lineText, 1, mid), font, textSize, width).X <= mouseX then
			low = mid
		else
			high = mid - 1
		end
	end

	-- The click lands on the character just after the fitting prefix
	local position = lineStart + low - meta.contentOffset + 1
	for _, link in ipairs(meta.links) do
		if
			(position >= link.start and position <= link.finish)
			or (position + 1 >= link.start and position + 1 <= link.finish)
		then
			return link
		end
	end
	return nil
end

--[=[
	Opens a link when it's clicked inside `textLabel`. `onOpenFail(url)` runs
	when the browser couldn't be opened (the link was copied instead).
	The connection lives as long as the label. `meta` is read on every click,
	so updating it (an edited message) updates the links.
]=]
function LinkHelper.attach(textLabel: TextLabel, meta: LinkMeta, onOpenFail: ((string) -> ())?)
	textLabel.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local link = LinkHelper.hitTest(
			textLabel,
			meta,
			input.Position.X - textLabel.AbsolutePosition.X,
			input.Position.Y - textLabel.AbsolutePosition.Y
		)
		if link and not Browser.open(link.url) and onOpenFail then
			onOpenFail(link.url)
		end
	end)
end

return LinkHelper
