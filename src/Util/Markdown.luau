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
		> Quote           >>> Quote (the rest of the message)
		- List item       * List item    (indented: a nested item)
		```lua            (a code block until a line ending in ```)
	Inline:
		**bold**  *italic*  _italic_  __underline__  ~~strikethrough~~
		`code`  ||spoiler||  [text](https://link)  \*not italic\*
	Also found in plain text: links, @mentions and #[object] tags.

	Code blocks and quotes are boxes in a message, not text: Markdown.blocks
	splits a message into text, code and quote parts (UI/MessageText draws
	each). Markdown.parse still reads them, as monospace lines and "▎" bars,
	for places that show one line of text (previews, notifications).

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
	block: boolean?, -- a line of a ``` code block (shown in one label)
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
	plain: boolean?, -- no room around `code` (for Markdown.strip)
}

-- A part of a message: text, a ``` code block, or a > quote
export type Block = {
	kind: "text" | "code" | "quote",
	text: string,
	language: string?, -- ```lua
}

local Markdown = {}

local HEADER_SCALE = { 1.6, 1.35, 1.15 }
local SUBTEXT_SCALE = 0.8
-- A thin space each side of `code`, so its box (and the rounded outline
-- UI/MentionPills draws) doesn't touch the text
local CODE_PAD = "\u{2009}"

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
			string.format('<mark color="%s" transparency="0">', hex(palette.codeBack or palette.inputFrame)),
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
				local code = string.sub(text, i + 1, close - 1)
				if not builder.options.plain then
					code = CODE_PAD .. code .. CODE_PAD
				end
				push(builder, code, with(style, { code = true }))
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

-- The ``` code blocks among a message's lines, by the line they start on.
-- Like Discord: ``` opens one (a single word after it names the language,
-- other text is the first line of code) and the next line ending in ```
-- closes it (text before the ``` is the last line). ```x``` on one line is
-- a block too. A ``` that's never closed is just text.
type Fence = { close: number, language: string?, code: { string } }

local function findFences(lines: { string }): { [number]: Fence }
	local fences = {}
	local i = 1
	while i <= #lines do
		local rest = string.match(lines[i], "^```(.*)$")
		if rest then
			local inline = string.match(rest, "^(.-)```%s*$")
			if inline and inline ~= "" then
				fences[i] = { close = i, code = { inline } }
				i += 1
				continue
			end
			local close = nil
			for j = i + 1, #lines do
				if string.match(lines[j], "```%s*$") then
					close = j
					break
				end
			end
			if close then
				local code = {}
				local language = string.match(rest, "^([%w_+#%-]+)%s*$")
				if not language and string.match(rest, "%S") then
					table.insert(code, rest)
				end
				for j = i + 1, close - 1 do
					table.insert(code, lines[j])
				end
				local last = string.match(lines[close], "^(.-)```%s*$") or ""
				if last ~= "" then
					table.insert(code, last)
				end
				fences[i] = { close = close, language = language, code = code }
				i = close + 1
				continue
			end
		end
		i += 1
	end
	return fences
end

-- The same, for Util/MarkdownSource (the message box styles what you type)
Markdown.fences = findFences

-- "> text" quotes one line, ">>> text" the rest of the message (Discord needs the space)
local function quoteOf(line: string): string?
	if line == ">" then
		return ""
	end
	return string.match(line, "^> (.*)$")
end

-- One line of text: a header, subtext, a quote, a list item or plain markdown
local function parseLine(builder: Builder, line: string, textSize: number, quoted: boolean)
	if quoted then
		push(builder, "\u{258E} ", { muted = true })
		parseInline(builder, line, {})
		return
	end
	local level, header = string.match(line, "^(#+) (.+)$")
	if level and #level <= 3 then
		parseInline(builder, header, { bold = true, size = math.floor(textSize * HEADER_SCALE[#level] + 0.5) })
		return
	end
	local subtext = string.match(line, "^%-# (.+)$")
	if subtext then
		parseInline(builder, subtext, { muted = true, size = math.floor(textSize * SUBTEXT_SCALE + 0.5) })
		return
	end
	local indent, item = string.match(line, "^(%s*)[%-%*] (.+)$")
	if item then
		-- An indented item is nested: a hollow bullet, like Discord
		push(builder, indent .. (if indent ~= "" then "\u{25E6} " else "\u{2022} "), {})
		parseInline(builder, item, {})
		return
	end
	parseInline(builder, line, {})
end

--[=[
	Parses a message into runs (see the top of this file).
]=]
function Markdown.parse(content: string?, palette: Palette?, options: Options?): Doc
	local opts = options or {}
	local builder: Builder = { runs = {}, palette = palette or Theme.PALETTES.Dark, options = opts }
	local textSize = opts.textSize or 15
	local lines = string.split(content or "", "\n")
	local fences = findFences(lines)
	local started = false
	local function newLine()
		if started then
			push(builder, "\n", {})
		end
		started = true
	end
	local quoteRest = false
	local i = 1
	while i <= #lines do
		local fence = fences[i]
		if fence then
			-- In one label: the fence lines stay as empty lines, the code is monospace
			if fence.close ~= i then
				newLine()
			end
			for _, codeLine in ipairs(fence.code) do
				newLine()
				push(builder, codeLine, { code = true, block = true })
			end
			if fence.close ~= i then
				newLine()
			end
			i = fence.close + 1
			continue
		end
		local line = lines[i]
		newLine()
		local rest = string.match(line, "^>>> (.*)$")
		if rest and not quoteRest then
			quoteRest = true
			line = rest
		end
		local quote = if quoteRest then line else quoteOf(line)
		parseLine(builder, quote or line, textSize, quote ~= nil)
		i += 1
	end
	return finish(builder)
end

--[=[
	Splits a message into its text, ``` code blocks and > quotes, in order.
	Empty lines next to a code block or quote are dropped (Discord leaves no
	gap there either).
]=]
function Markdown.blocks(content: string?): { Block }
	local lines = string.split(content or "", "\n")
	local fences = findFences(lines)
	local blocks: { Block } = {}
	local current: { kind: string, lines: { string } }? = nil
	local function flush()
		local open = current
		if not open then
			return
		end
		current = nil
		local first, last = 1, #open.lines
		if open.kind == "text" then
			while first <= last and not string.match(open.lines[first], "%S") do
				first += 1
			end
			while last >= first and not string.match(open.lines[last], "%S") do
				last -= 1
			end
			if first > last then
				return
			end
		end
		table.insert(blocks, { kind = open.kind :: any, text = table.concat(open.lines, "\n", first, last) })
	end
	local function add(kind: string, line: string)
		if not current or current.kind ~= kind then
			flush()
			current = { kind = kind, lines = {} }
		end
		table.insert((current :: any).lines, line)
	end
	local quoteRest = false
	local i = 1
	while i <= #lines do
		local fence = fences[i]
		if fence then
			flush()
			table.insert(blocks, { kind = "code", text = table.concat(fence.code, "\n"), language = fence.language })
			i = fence.close + 1
			continue
		end
		local line = lines[i]
		local rest = string.match(line, "^>>> (.*)$")
		if rest and not quoteRest then
			quoteRest = true
			line = rest
		end
		local quote = if quoteRest then line else quoteOf(line)
		if quote then
			add("quote", quote)
		else
			add("text", line)
		end
		i += 1
	end
	flush()
	return blocks
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
	return Markdown.parse(content, nil, { revealSpoilers = true, plain = true }).plain
end

return Markdown
