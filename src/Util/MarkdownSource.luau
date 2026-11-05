--!strict
--[[
	MarkdownSource

	Markdown as you type it, styled the way Discord's message box does: the
	markers stay (dimmed) and the text between them is bold, italic,
	underlined, crossed out, a spoiler, code or a link. A ``` block's lines
	are coloured (```lua) and a quote's ">" becomes a bar.

	The result is a Util/Markdown doc (runs of text with their RichText
	tags) whose plain text is exactly what was typed. Only styles that keep
	letters as wide as they are are used (bold is a thin outline, code keeps
	the normal font), so it lies over the message box like the box's own
	text, and UI/TextLayout can measure it for the cursor (UI/ComposerText).

	Usage:
		local doc = MarkdownSource.doc("**hi** `x`", palette)
		label.Text = doc.markup        -- label.ContentText == "**hi** `x`"
]]

local Links = require(script.Parent.Links)
local Markdown = require(script.Parent.Markdown)
local Mentions = require(script.Parent.Mentions)
local SyntaxHighlight = require(script.Parent.SyntaxHighlight)

type Palette = { [string]: Color3 }
type Run = { text: string, open: string, close: string }
type Runs = { Run }

local BOLD_STROKE = 0.45 -- the outline that makes "bold" without widening letters

local MarkdownSource = {}

local function escape(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function hex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

local function isWordChar(char: string): boolean
	return char ~= "" and string.match(char, "^[%w]$") ~= nil
end

local PAIRS = { ["**"] = "bold", ["__"] = "underline", ["~~"] = "strike", ["||"] = "spoiler" }

-- Runs: text with the tags around it (innermost last)
local function leaf(text: string, open: string?, close: string?): Runs
	if text == "" then
		return {}
	end
	return { { text = text, open = open or "", close = close or "" } }
end

local function wrapped(runs: Runs, open: string, close: string): Runs
	for _, run in ipairs(runs) do
		run.open = open .. run.open
		run.close = run.close .. close
	end
	return runs
end

local function join(...: Runs): Runs
	local all = {}
	for _, runs in ipairs({ ... }) do
		table.move(runs, 1, #runs, #all + 1, all)
	end
	return all
end

function MarkdownSource.doc(text: string, palette: Palette): Markdown.Doc
	local textColor = palette.textBoxText or palette.messageText
	local dimOpen = '<font color="' .. hex(palette.timestamp) .. '">'

	local function colored(color: Color3 | string, runs: Runs): Runs
		local value = if type(color) == "string" then color else hex(color)
		return wrapped(runs, '<font color="' .. value .. '">', "</font>")
	end
	-- Markdown markers: there, but quiet
	local function dim(marker: string): Runs
		return leaf(marker, dimOpen, "</font>")
	end
	local function styled(kind: string, runs: Runs): Runs
		if kind == "bold" then
			return wrapped(
				runs,
				string.format('<stroke color="%s" thickness="%s">', hex(textColor), tostring(BOLD_STROKE)),
				"</stroke>"
			)
		elseif kind == "underline" then
			return wrapped(runs, "<u>", "</u>")
		elseif kind == "strike" then
			return wrapped(runs, "<s>", "</s>")
		elseif kind == "spoiler" then
			return wrapped(
				runs,
				string.format('<mark color="%s" transparency="0.6">', hex(palette.timestamp)),
				"</mark>"
			)
		end
		return wrapped(runs, "<i>", "</i>")
	end
	local function code(inner: string): Runs
		return wrapped(
			colored(palette.codeText or textColor, leaf(inner)),
			string.format('<mark color="%s" transparency="0">', hex(palette.scrollBack)),
			"</mark>"
		)
	end

	-- Plain text: links blue, @mentions and #[tags] in the mention colour
	local function plain(segment: string): Runs
		local found = {}
		for _, link in ipairs(Links.find(segment)) do
			table.insert(found, { start = link.start, finish = link.finish, color = palette.sendButton })
		end
		for _, mention in ipairs(Mentions.find(segment)) do
			table.insert(found, { start = mention.start, finish = mention.finish, color = palette.mentionText })
		end
		local position = 1
		while true do
			local start, finish = string.find(segment, "#%[[^%]\n]+%]", position)
			if not start then
				break
			end
			table.insert(found, { start = start, finish = finish, color = palette.mentionText })
			position = finish + 1
		end
		table.sort(found, function(a, b)
			return a.start < b.start
		end)
		local runs = {}
		position = 1
		for _, item in ipairs(found) do
			if item.start >= position then
				runs = join(
					runs,
					leaf(string.sub(segment, position, item.start - 1)),
					colored(item.color, leaf(string.sub(segment, item.start, item.finish)))
				)
				position = item.finish + 1
			end
		end
		return join(runs, leaf(string.sub(segment, position)))
	end

	-- Inline markdown (the same rules as Util/Markdown), markers kept
	local function inline(segment: string): Runs
		local runs = {}
		local buffer = {}
		local function flush()
			if #buffer > 0 then
				runs = join(runs, plain(table.concat(buffer)))
				buffer = {}
			end
		end
		local i = 1
		local length = #segment
		while i <= length do
			local char = string.sub(segment, i, i)
			local two = string.sub(segment, i, i + 1)
			if char == "\\" and i < length and string.match(string.sub(segment, i + 1, i + 1), "%p") then
				flush()
				runs = join(runs, dim("\\"), leaf(string.sub(segment, i + 1, i + 1)))
				i += 2
				continue
			end
			if char == "`" then
				local close = string.find(segment, "`", i + 1, true)
				if close and close > i + 1 then
					flush()
					runs = join(runs, dim("`"), code(string.sub(segment, i + 1, close - 1)), dim("`"))
					i = close + 1
					continue
				end
			end
			if char == "[" then
				local label, url = string.match(segment, "^%[([^%]\n]+)%]%((https?://[^%s%)]+)%)", i)
				if label and url then
					flush()
					runs =
						join(runs, dim("["), inline(label), dim("]("), colored(palette.sendButton, leaf(url)), dim(")"))
					i += #label + #url + 4
					continue
				end
			end
			local pairName = PAIRS[two]
			if pairName then
				local close = string.find(segment, two, i + 2, true)
				while close and string.sub(segment, close + 2, close + 2) == char do
					close += 1
				end
				if close and close > i + 2 then
					flush()
					runs =
						join(runs, dim(two), styled(pairName, inline(string.sub(segment, i + 2, close - 1))), dim(two))
					i = close + 2
					continue
				end
			end
			if char == "*" or char == "_" then
				local close = string.find(segment, char, i + 1, true)
				local before = if i > 1 then string.sub(segment, i - 1, i - 1) else ""
				local opens = string.sub(segment, i + 1, i + 1) ~= " "
				if char == "_" then
					opens = opens and not isWordChar(before)
					if close and isWordChar(string.sub(segment, close + 1, close + 1)) then
						close = nil
					end
				end
				if opens and close and close > i + 1 and string.sub(segment, close - 1, close - 1) ~= " " then
					flush()
					runs = join(
						runs,
						dim(char),
						styled("italic", inline(string.sub(segment, i + 1, close - 1))),
						dim(char)
					)
					i = close + 1
					continue
				end
			end
			table.insert(buffer, char)
			i += 1
		end
		flush()
		return runs
	end

	-- A quote's ">" as a bar: its space filled, the character hidden
	local function bar(marker: string): Runs
		return leaf(
			marker,
			string.format(
				'<mark color="%s" transparency="0"><font transparency="1">',
				hex(palette.quoteBar or palette.timestamp)
			),
			"</font></mark>"
		)
	end

	local function muted(runs: Runs): Runs
		return colored(palette.timestamp, runs)
	end

	local function line(source: string, quoted: boolean): Runs
		if quoted then
			return muted(inline(source))
		end
		if source == ">" then
			return bar(">")
		end
		local quote = string.match(source, "^> (.*)$")
		if quote then
			return join(bar(">"), leaf(" "), muted(inline(quote)))
		end
		local rest = string.match(source, "^>>> (.*)$")
		if rest then
			return join(bar(">>>"), leaf(" "), muted(inline(rest)))
		end
		local level, header = string.match(source, "^(#+ )(.+)$")
		if level and #level <= 4 then
			return join(dim(level), styled("bold", inline(header)))
		end
		local subtext = string.match(source, "^%-# (.+)$")
		if subtext then
			return join(dim("-# "), muted(inline(subtext)))
		end
		local indent, marker, item = string.match(source, "^(%s*)([%-%*] )(.+)$")
		if item then
			return join(leaf(indent), dim(marker), inline(item))
		end
		return inline(source)
	end

	local lines = string.split(text, "\n")
	local fences = Markdown.fences(lines)
	local runs: Runs = {}
	local quoteRest = false
	local i = 1
	local function newLine()
		if i > 1 then
			runs = join(runs, leaf("\n"))
		end
	end
	while i <= #lines do
		local fence = fences[i]
		if fence then
			local highlight = SyntaxHighlight.isSupported(fence.language)
			local function codeLine(source: string): Runs
				if not highlight then
					return colored(palette.codeText or textColor, leaf(source))
				end
				local spans = {}
				for _, span in ipairs(SyntaxHighlight.spans(source, palette)) do
					spans = join(spans, if span.color then colored(span.color, leaf(span.text)) else leaf(span.text))
				end
				return spans
			end
			newLine()
			if fence.close == i then
				-- ```x``` on one line
				local inner, trailing = string.match(lines[i], "^```(.-)```(%s*)$")
				runs = join(runs, dim("```"), codeLine(inner or ""), dim("```" .. (trailing or "")))
				i += 1
				continue
			end
			-- The opening fence: a language name, or the first code line after it
			local rest = string.sub(lines[i], 4)
			if fence.language or not string.match(rest, "%S") then
				runs = join(runs, dim(lines[i]))
			else
				runs = join(runs, dim("```"), codeLine(rest))
			end
			for j = i + 1, fence.close - 1 do
				runs = join(runs, leaf("\n"), codeLine(lines[j]))
			end
			local last = lines[fence.close]
			local before = string.match(last, "^(.-)```%s*$") or ""
			runs = join(runs, leaf("\n"), codeLine(before), dim(string.sub(last, #before + 1)))
			i = fence.close + 1
			continue
		end
		newLine()
		local source = lines[i]
		local quoted = quoteRest
		if not quoteRest and string.match(source, "^>>> ") then
			quoteRest = true
		end
		runs = join(runs, line(source, quoted))
		i += 1
	end

	-- Where each run sits in the plain text, and the whole thing as RichText
	local plainParts, markup = {}, {}
	local position = 1
	local docRuns = {}
	for _, run in ipairs(runs) do
		table.insert(plainParts, run.text)
		table.insert(markup, run.open .. escape(run.text) .. run.close)
		table.insert(docRuns, {
			text = run.text,
			open = run.open,
			close = run.close,
			style = {},
			start = position,
			finish = position + #run.text - 1,
		})
		position += #run.text
	end
	return { runs = docRuns, plain = table.concat(plainParts), markup = table.concat(markup) }
end

--[=[
	Just the RichText (see MarkdownSource.doc).
]=]
function MarkdownSource.render(text: string, palette: Palette): string
	return MarkdownSource.doc(text, palette).markup
end

return MarkdownSource
