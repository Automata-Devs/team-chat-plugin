--!strict
--[[
	TextLayout

	Where text sits inside a TextLabel or TextBox, measured the way Roblox
	lays it out (TextService, with RichText for markdown). Used for clicking
	links, spoilers and #tags in messages, and for the rounded highlight
	behind @mentions and #tags (UI/MentionPills).

	Every label shows a Util/Markdown doc: messages register theirs with
	setDoc; anything else (the message box) is measured as plain text.

	Lines can have different heights (headers), so instead of counting lines
	this measures prefixes: the height of the text up to a character is the
	bottom of that character's line. Words wrap as a whole, so a character's
	line is found from the end of its word.

	Usage:
		TextLayout.setDoc(label, doc)
		TextLayout.rect(label, doc, fromByte, toByte)   -- { x, y, width, height } (yields)
		TextLayout.hitTest(label, x, y)                  -- the Markdown run under a point (yields)
]]

local TextService = game:GetService("TextService")

local Markdown = require(script.Parent.Parent.Util.Markdown)

type Doc = Markdown.Doc
type TextObject = TextLabel | TextBox

export type Rect = { x: number, y: number, width: number, height: number }

local TextLayout = {}

local docs: { [Instance]: Doc } = setmetatable({}, { __mode = "k" }) :: any

function TextLayout.setDoc(object: Instance, doc: Doc?)
	docs[object] = doc
end

--[=[
	The doc an object shows: its registered one, or its text as plain text.
]=]
function TextLayout.docOf(object: TextObject): (Doc, boolean)
	local doc = docs[object]
	if doc then
		return doc, true
	end
	return Markdown.plainDoc(object.ContentText), false
end

local function padding(object: TextObject): UIPadding?
	return object:FindFirstChildOfClass("UIPadding")
end

function TextLayout.innerWidth(object: TextObject): number
	local pad = padding(object)
	return object.AbsoluteSize.X - (if pad then pad.PaddingLeft.Offset + pad.PaddingRight.Offset else 0)
end

-- Size of some (rich) text in the object's font, wrapped at its width
local function measure(object: TextObject, text: string, rich: boolean): Vector2
	if text == "" then
		return Vector2.zero
	end
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = object.FontFace
	params.Size = object.TextSize
	params.Width = TextLayout.innerWidth(object)
	params.RichText = rich
	local ok, size = pcall(TextService.GetTextBoundsAsync, TextService, params)
	params:Destroy()
	return if ok then size else Vector2.zero
end

-- A measuring session for one object and doc (caches prefix heights)
local function session(object: TextObject, doc: Doc, rich: boolean)
	local plain = doc.plain
	-- Byte index where each character starts, and where each ends
	local starts, ends = {}, {}
	for position, code in utf8.codes(plain) do
		table.insert(starts, position)
		table.insert(ends, position + #utf8.char(code) - 1)
	end
	local count = #starts
	local heights: { [number]: number } = {}

	local function markup(fromChar: number, toChar: number): string
		if toChar < fromChar then
			return ""
		end
		return if rich
			then Markdown.slice(doc, starts[fromChar], ends[toChar])
			else string.sub(plain, starts[fromChar], ends[toChar])
	end

	-- The last character of the word that character k is in
	local function wordEnd(k: number): number
		local e = k
		while e < count do
			local nextChar = string.sub(plain, starts[e + 1], ends[e + 1])
			if string.match(nextChar, "^%s$") then
				break
			end
			e += 1
		end
		return e
	end

	-- Bottom of character k's line (the height of everything up to its word's end)
	local function bottom(k: number): number
		local e = wordEnd(k)
		local cached = heights[e]
		if cached then
			return cached
		end
		local h = measure(object, markup(1, e), rich).Y
		heights[e] = h
		return h
	end

	-- The first character on character k's line
	local function lineStart(k: number): number
		local target = bottom(k)
		local low, high = 1, k
		while low < high do
			local mid = (low + high) // 2
			if bottom(mid) >= target then
				high = mid
			else
				low = mid + 1
			end
		end
		return low
	end

	local function top(k: number): number
		local first = lineStart(k)
		return if first > 1 then bottom(first - 1) else 0
	end

	local function widthOf(fromChar: number, toChar: number): number
		return measure(object, markup(fromChar, toChar), rich).X
	end

	return {
		count = count,
		starts = starts,
		ends = ends,
		bottom = bottom,
		lineStart = lineStart,
		top = top,
		widthOf = widthOf,
		total = function(): number
			return measure(object, if rich then doc.markup else plain, rich).Y
		end,
	}
end

-- Where the text starts vertically (TextBoxes center their text)
local function textTop(object: TextObject, contentHeight: number): number
	local pad = padding(object)
	local inner = object.AbsoluteSize.Y - (if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0)
	if object.TextYAlignment == Enum.TextYAlignment.Center then
		return (inner - contentHeight) / 2
	elseif object.TextYAlignment == Enum.TextYAlignment.Bottom then
		return inner - contentHeight
	end
	return 0
end

-- Character index (1-based) of a plain byte
local function charAt(starts: { number }, byte: number): number
	for i = #starts, 1, -1 do
		if starts[i] <= byte then
			return i
		end
	end
	return 1
end

--[=[
	The box around plain bytes `from`..`to` (one line), relative to the
	object's content area (its padding already moves children). Yields.
]=]
function TextLayout.rect(object: TextObject, doc: Doc, from: number, to: number, rich: boolean?): Rect?
	local s = session(object, doc, rich ~= false)
	if s.count == 0 then
		return nil
	end
	local first, last = charAt(s.starts, from), charAt(s.starts, to)
	local lineFirst = s.lineStart(last)
	local y = s.top(last)
	local height = s.bottom(last) - y
	local x0 = if first > lineFirst then s.widthOf(lineFirst, first - 1) else 0
	local x1 = s.widthOf(lineFirst, last)
	return { x = x0, y = textTop(object, s.total()) + y, width = x1 - x0, height = height }
end

-- One measuring session per object while its text and size stay the same
-- (the cursor and selection in the message box measure often)
local cachedSessions: { [Instance]: { key: string, session: any } } = setmetatable({}, { __mode = "k" }) :: any

local function cachedSession(object: TextObject, doc: Doc)
	local key = doc.markup .. "\0" .. tostring(TextLayout.innerWidth(object)) .. "\0" .. tostring(object.TextSize)
	local cached = cachedSessions[object]
	if cached and cached.key == key then
		return cached.session
	end
	local s = session(object, doc, true)
	cachedSessions[object] = { key = key, session = s }
	return s
end

--[=[
	Where the text cursor goes in a label showing `doc`: before plain byte
	`cursor` (a TextBox's CursorPosition), as { x, y, height } in the
	content area. Yields.
]=]
function TextLayout.caret(object: TextObject, doc: Doc, cursor: number): Rect
	local s = cachedSession(object, doc)
	local plain = doc.plain
	local lineHeight = measure(object, "Ag", false).Y
	local top = textTop(object, if s.count > 0 then s.total() else lineHeight)
	if s.count == 0 or cursor <= 1 then
		return { x = 0, y = top, width = 0, height = lineHeight }
	end
	local before = charAt(s.starts, math.min(cursor - 1, #plain))
	local beforeChar = string.sub(plain, s.starts[before], s.ends[before])
	local atChar = if cursor <= #plain then string.sub(plain, cursor, cursor) else ""
	-- After a newline: the start of the next line
	if beforeChar == "\n" then
		local height = measure(object, string.sub(plain, 1, s.ends[before]) .. "x", false).Y
		return { x = 0, y = top + height - lineHeight, width = 0, height = lineHeight }
	end
	-- Before a letter: its left edge (it may have wrapped onto the next line)
	if atChar ~= "" and not string.match(atChar, "%s") then
		local at = charAt(s.starts, cursor)
		local lineFirst = s.lineStart(at)
		local y = s.top(at)
		local x = if at > lineFirst then s.widthOf(lineFirst, at - 1) else 0
		return { x = x, y = top + y, width = 0, height = s.bottom(at) - y }
	end
	-- Otherwise: the right edge of the character before
	local lineFirst = s.lineStart(before)
	local y = s.top(before)
	return { x = s.widthOf(lineFirst, before), y = top + y, width = 0, height = s.bottom(before) - y }
end

--[=[
	The boxes covering plain bytes `from`..`to` of a label showing `doc`,
	one per line they're on (for drawing a selection). Yields.
]=]
function TextLayout.lineRects(object: TextObject, doc: Doc, from: number, to: number): { Rect }
	local s = cachedSession(object, doc)
	local rects = {}
	if s.count == 0 or to < from then
		return rects
	end
	local top = textTop(object, s.total())
	local first, last = charAt(s.starts, from), charAt(s.starts, to)
	local k = first
	while k <= last do
		local lineFirst = s.lineStart(k)
		local lineBottom = s.bottom(k)
		-- The last character on k's line (or of the selection)
		local low, high = k, last
		while low < high do
			local mid = (low + high + 1) // 2
			if s.bottom(mid) <= lineBottom then
				low = mid
			else
				high = mid - 1
			end
		end
		local lineTop = s.top(k)
		local x0 = if k > lineFirst then s.widthOf(lineFirst, k - 1) else 0
		local x1 = s.widthOf(lineFirst, low)
		table.insert(rects, { x = x0, y = top + lineTop, width = math.max(x1 - x0, 3), height = lineBottom - lineTop })
		k = low + 1
	end
	return rects
end

--[=[
	The Markdown run under a point (relative to the object's top-left). Yields.
]=]
function TextLayout.hitTest(object: TextObject, x: number, y: number): Markdown.Run?
	local doc, rich = TextLayout.docOf(object)
	local s = session(object, doc, rich)
	if s.count == 0 or y < 0 then
		return nil
	end
	y -= textTop(object, s.total())
	-- The first character whose line reaches down to y starts that line
	local low, high = 1, s.count
	if s.bottom(s.count) < y then
		return nil
	end
	while low < high do
		local mid = (low + high) // 2
		if s.bottom(mid) >= y then
			high = mid
		else
			low = mid + 1
		end
	end
	local lineFirst = low
	local lineBottom = s.bottom(lineFirst)
	-- The line's last character
	low, high = lineFirst, s.count
	while low < high do
		local mid = (low + high + 1) // 2
		if s.bottom(mid) <= lineBottom then
			low = mid
		else
			high = mid - 1
		end
	end
	local lineLast = low
	if s.widthOf(lineFirst, lineLast) < x then
		return nil
	end
	-- The last character that still ends left of x; the one after it is under x
	low, high = lineFirst - 1, lineLast
	while low < high do
		local mid = (low + high + 1) // 2
		if s.widthOf(lineFirst, mid) <= x then
			low = mid
		else
			high = mid - 1
		end
	end
	local hit = math.min(low + 1, lineLast)
	return Markdown.runAt(doc, s.starts[hit])
end

return TextLayout
