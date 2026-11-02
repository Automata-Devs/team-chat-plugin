--!strict
--[[
	Markdown

	Discord-style markdown for chat messages, turned into Roblox RichText.
	The result is a list of runs: pieces of plain text with the tags around
	them. Because every run knows where its text sits in the plain text
	(what the label shows, its ContentText), UI/TextLayout can measure any
	part of the message exactly, for link clicks and mention highlights.

	Lines:
		# Big header      ## Header      ### Small header      -# Subtext
		> Quote           - List item    * List item
		```               (a code block until the next ```)
	Inline:
		**bold**  *italic*  _italic_  __underline__  ~~strikethrough~~
		`code`  ||spoiler||  [text](https://link)  \*not italic\*
	Also found in plain text: links, @mentions and #[object] tags.

	Usage:
		local doc = Markdown.parse("**hi** @builderman", palette, { textSize = 15 })
		label.Text = doc.markup          -- doc.plain is what the label shows
		Markdown.slice(doc, 1, 2)        -- RichText for plain bytes 1..2 ("hi", still bold)
		Markdown.strip("**hi**")         -- "hi"
]]

local Theme = require(script.Parent.Parent.Config.Theme)
local Links = require(script.Parent.Links)
local Mentions = require(script.Parent.Mentions)

type Palette = { [string]: Color3 }

export type Style = {
	bold: boolean?,
	italic: boolean?,
	underline: boolean?,
	strike: boolean?,
	code: boolean?,
	spoiler: boolean?,
	size: number?,
	muted: boolean?, -- subtext and quote bars
	url: string?, -- a link (masked or typed)
	mention: string?, -- @name
	tag: string?, -- #[path]: an object in the place
}

export type Run = {
	text: string, -- plain text (what the label shows)
	open: string, -- RichText tags before it
	close: string, -- and after it
	style: Style,
	start: number, -- plain byte range in doc.plain
	finish: number,
}

export type Doc = {
	runs: { Run },
	plain: string,
	markup: string,
}

export type Options = {
	textSize: number?, -- the label's TextSize (headers scale from it)
	revealSpoilers: boolean?,
}

local Markdown = {}

local HEADER_SCALE = { 1.6, 1.35, 1.15 }
local SUBTEXT_SCALE = 0.8
local CODE_TRANSPARENCY = 0.4 -- the box behind `code`

local function escape(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function hex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	)
end

local function with(style: Style, changes: Style): Style
	local copy = table.clone(style)
	for key, value in pairs(changes) do
		(copy :: any)[key] = value
	end
	return copy
end

-- The last part of an object path, shown after the # ("Workspace.Map.Door" -> "Door")
function Markdown.tagName(path: string): string
	return string.match(path, "([^%.]+)$") or path
end

-- Opening and closing tags for a style (always in the same order, so runs nest cleanly)
local function tagsFor(style: Style, palette: Palette, options: Options): (string, string)
	local open, close = {}, {}
	local function wrap(o: string, c: string)
		table.insert(open, o)
		table.insert(close, 1, c)
	end
	if style.size then
		wrap(string.format('<font size="%d">', style.size), "</font>")
	end
	if style.spoiler and not options.revealSpoilers then
		-- Hidden: a solid box, text drawn see-through (its space is kept)
		wrap(string.format('<mark color="%s" transparency="0">', hex(palette.timestamp)), "</mark>")
		wrap('<font transparency="1">', "</font>")
	elseif style.spoiler then
		wrap(string.format('<mark color="%s" transparency="0.6">', hex(palette.timestamp)), "</mark>")
	end
	if style.code then
		wrap(
			string.format('<mark color="%s" transparency="%s">', hex(palette.inputFrame), tostring(CODE_TRANSPARENCY)),
			"</mark>"
		)
		wrap(Theme.richFont("mono"), "</font>")
	end
	if style.url then
		wrap(string.format('<font color="%s">', hex(Theme.LINK_COLOR)), "</font>")
		wrap("<u>", "</u>")
	elseif style.mention or style.tag then
		wrap(string.format('<font color="%s">', hex(palette.mentionText)), "</font>")
	elseif style.muted then
		wrap(string.format('<font color="%s">', hex(palette.timestamp)), "</font>")
	end
	if style.bold then
		wrap("<b>", "</b>")
	end
	if style.italic then
		wrap("<i>", "</i>")
	end
	if style.underline and not style.url then
		wrap("<u>", "</u>")
	end
	if style.strike then
		wrap("<s>", "</s>")
	end
	return table.concat(open), table.concat(close)
end

type Builder = { runs: { Run }, palette: Palette, options: Options }

local function push(builder: Builder, text: string, style: Style)
	if text == "" then
		return
	end
	local open, close = tagsFor(style, builder.palette, builder.options)
	table.insert(builder.runs, { text = text, open = open, close = close, style = style, start = 0, finish = 0 })
end

-- Plain text: split out links, @mentions and #[object] tags
local function pushText(builder: Builder, text: string, style: Style)
	if style.code or style.url then
		push(builder, text, style)
		return
	end
	local found = {}
	for _, link in ipairs(Links.find(text)) do
		table.insert(
			found,
			{ start = link.start, finish = link.finish, style = { url = link.url }, shown = link.display }
		)
	end
	for _, mention in ipairs(Mentions.find(text)) do
		table.insert(found, { start = mention.start, finish = mention.finish, style = { mention = mention.name } })
	end
	local position = 1
	while true do
		local start, finish, path = string.find(text, "#%[([^%]\n]+)%]", position)
		if not start then
			break
		end
		table.insert(
			found,
			{ start = start, finish = finish, style = { tag = path }, shown = "#" .. Markdown.tagName(path) }
		)
		position = finish + 1
	end
	table.sort(found, function(a, b)
		return a.start < b.start
	end)
	position = 1
	for _, item in ipairs(found) do
		if item.start >= position then
			push(builder, string.sub(text, position, item.start - 1), style)
			push(builder, item.shown or string.sub(text, item.start, item.finish), with(style, item.style))
			position = item.finish + 1
		end
	end
	push(builder, string.sub(text, position), style)
end

local PAIRS = { ["**"] = "bold", ["__"] = "underline", ["~~"] = "strike", ["||"] = "spoiler" }

local function isWordChar(char: string): boolean
	return char ~= "" and string.match(char, "^[%w]$") ~= nil
end

local function parseInline(builder: Builder, text: string, style: Style)
	local buffer = {}
	local function flush()
		if #buffer > 0 then
			pushText(builder, table.concat(buffer), style)
			buffer = {}
		end
	end
	local i = 1
	local length = #text
	while i <= length do
		local char = string.sub(text, i, i)
		local two = string.sub(text, i, i + 1)
		if char == "\\" and i < length and string.match(string.sub(text, i + 1, i + 1), "%p") then
			-- \* shows a literal *
			table.insert(buffer, string.sub(text, i + 1, i + 1))
			i += 2
			continue
		end
		if char == "`" then
			local close = string.find(text, "`", i + 1, true)
			if close and close > i + 1 then
				flush()
				push(builder, string.sub(text, i + 1, close - 1), with(style, { code = true }))
				i = close + 1
				continue
			end
		end
		if char == "[" then
			local label, url = string.match(text, "^%[([^%]\n]+)%]%((https?://[^%s%)]+)%)", i)
			if label and url then
				flush()
				parseInline(builder, label, with(style, { url = url }))
				i += #label + #url + 4
				continue
			end
		end
		local pairName = PAIRS[two]
		if pairName then
			local close = string.find(text, two, i + 2, true)
			-- ***bold italic***: the closing ** is the last two of the stars
			while close and string.sub(text, close + 2, close + 2) == char do
				close += 1
			end
			if close and close > i + 2 then
				flush()
				parseInline(builder, string.sub(text, i + 2, close - 1), with(style, { [pairName] = true } :: any))
				i = close + 2
				continue
			end
		end
		if char == "*" or char == "_" then
			local close = string.find(text, char, i + 1, true)
			local before = if i > 1 then string.sub(text, i - 1, i - 1) else ""
			local opens = string.sub(text, i + 1, i + 1) ~= " "
			if char == "_" then
				-- _italic_ only at word edges (snake_case stays as it is)
				opens = opens and not isWordChar(before)
				if close and isWordChar(string.sub(text, close + 1, close + 1)) then
					close = nil
				end
			end
			if opens and close and close > i + 1 and string.sub(text, close - 1, close - 1) ~= " " then
				flush()
				parseInline(builder, string.sub(text, i + 1, close - 1), with(style, { italic = true }))
				i = close + 1
				continue
			end
		end
		table.insert(buffer, char)
		i += 1
	end
	flush()
end

local function finish(builder: Builder): Doc
	local plain, markup = {}, {}
	local position = 1
	for _, run in ipairs(builder.runs) do
		run.start = position
		run.finish = position + #run.text - 1
		position += #run.text
		table.insert(plain, run.text)
		table.insert(markup, run.open .. escape(run.text) .. run.close)
	end
	return { runs = builder.runs, plain = table.concat(plain), markup = table.concat(markup) }
end

--[=[
	Parses a message into runs (see the top of this file).
]=]
function Markdown.parse(content: string?, palette: Palette?, options: Options?): Doc
	local opts = options or {}
	local builder: Builder = { runs = {}, palette = palette or Theme.PALETTES.Dark, options = opts }
	local textSize = opts.textSize or 15
	local lines = string.split(content or "", "\n")
	local inCode = false
	for index, line in ipairs(lines) do
		if index > 1 then
			push(builder, "\n", {})
		end
		if string.match(line, "^```") then
			-- A fence line: starts or ends a code block (a language name after it is ignored)
			inCode = not inCode
			local rest = string.match(line, "^```(.-)```$")
			if rest and rest ~= "" then
				push(builder, rest, { code = true })
				inCode = false
			end
			continue
		end
		if inCode then
			push(builder, line, { code = true })
			continue
		end
		local level, header = string.match(line, "^(#+) (.+)$")
		if level and #level <= 3 then
			parseInline(builder, header, { bold = true, size = math.floor(textSize * HEADER_SCALE[#level] + 0.5) })
			continue
		end
		local subtext = string.match(line, "^%-# (.+)$")
		if subtext then
			parseInline(builder, subtext, { muted = true, size = math.floor(textSize * SUBTEXT_SCALE + 0.5) })
			continue
		end
		local quote = string.match(line, "^> ?(.*)$")
		if quote then
			push(builder, "\u{258E} ", { muted = true })
			parseInline(builder, quote, {})
			continue
		end
		local indent, item = string.match(line, "^(%s*)[%-%*] (.+)$")
		if item then
			push(builder, indent .. "\u{2022} ", {})
			parseInline(builder, item, {})
			continue
		end
		parseInline(builder, line, {})
	end
	return finish(builder)
end

--[=[
	A doc for text that isn't markdown (one plain run), e.g. the message box.
]=]
function Markdown.plainDoc(text: string): Doc
	local builder: Builder = { runs = {}, palette = Theme.PALETTES.Dark, options = {} }
	push(builder, text, {})
	return finish(builder)
end

--[=[
	Adds a run at the end of a doc (e.g. a small "(edited)").
]=]
function Markdown.append(doc: Doc, text: string, open: string, close: string)
	local start = #doc.plain + 1
	table.insert(
		doc.runs,
		{ text = text, open = open, close = close, style = {}, start = start, finish = start + #text - 1 }
	)
	doc.plain ..= text
	doc.markup ..= open .. escape(text) .. close
end

--[=[
	RichText for plain bytes `from`..`to` of a doc, keeping each run's tags.
]=]
function Markdown.slice(doc: Doc, from: number, to: number): string
	local parts = {}
	for _, run in ipairs(doc.runs) do
		if run.finish >= from and run.start <= to then
			local a = math.max(from, run.start) - run.start + 1
			local b = math.min(to, run.finish) - run.start + 1
			table.insert(parts, run.open .. escape(string.sub(run.text, a, b)) .. run.close)
		end
	end
	return table.concat(parts)
end

--[=[
	The run that plain byte `index` belongs to.
]=]
function Markdown.runAt(doc: Doc, index: number): Run?
	for _, run in ipairs(doc.runs) do
		if index >= run.start and index <= run.finish then
			return run
		end
	end
	return nil
end

--[=[
	The links in a doc (typed and masked), for link previews.
]=]
function Markdown.urls(doc: Doc): { string }
	local urls, seen = {}, {}
	for _, run in ipairs(doc.runs) do
		local url = run.style.url
		if url and not seen[url] then
			seen[url] = true
			table.insert(urls, url)
		end
	end
	return urls
end

--[=[
	The text without markdown (for one-line previews and notifications).
]=]
function Markdown.strip(content: string?): string
	return Markdown.parse(content, nil, { revealSpoilers = true }).plain
end

return Markdown
