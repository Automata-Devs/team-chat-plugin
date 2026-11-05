--!strict
--[[
	MessageText

	Shows a message's text with markdown (Util/Markdown) and makes it
	clickable: links open in the browser, a ||spoiler|| reveals itself, and a
	#[object] tag calls MessageText.onTag (the chat window moves the camera
	to it). The doc is registered with UI/TextLayout, so clicks and the
	@mention highlights (UI/MentionPills) measure the formatted text.

	Plain messages are one label. A message with ``` code blocks or > quotes
	is drawn in parts inside the label, like Discord: text parts as labels,
	code blocks as bordered boxes (```lua is coloured, Util/SyntaxHighlight)
	and quotes with a bar on their left.

	Usage:
		MessageText.set(label, content, palette, { edited = true })
		MessageText.attachClicks(label, function(url) ... end) -- url couldn't open
]]

local Browser = require(script.Parent.Parent.Core.Browser)
local Markdown = require(script.Parent.Parent.Util.Markdown)
local RichText = require(script.Parent.Parent.Util.RichText)
local SyntaxHighlight = require(script.Parent.Parent.Util.SyntaxHighlight)
local Theme = require(script.Parent.Parent.Config.Theme)
local TextLayout = require(script.Parent.TextLayout)
local MentionPills = require(script.Parent.MentionPills)

local BLOCK_GAP = 4 -- between the parts of a message
local CODE_PADDING = 8 -- inside a code block (10 left and right)
local CODE_RADIUS = 4
local QUOTE_BAR = 4 -- the bar's width; the text starts 12px after its left edge
local QUOTE_INDENT = 12

local MessageText = {}

-- Called with an object path when a #tag is clicked (set by the chat window)
MessageText.onTag = nil :: ((path: string) -> ())?

type State = {
	content: string,
	palette: any,
	edited: boolean,
	revealed: boolean,
	docs: { Markdown.Doc }, -- every text part's doc (one when the message is one label)
}

local states: { [TextLabel]: State } = setmetatable({}, { __mode = "k" }) :: any
local sizeWatched: { [TextLabel]: boolean } = setmetatable({}, { __mode = "k" }) :: any
-- attachClicks' callback per message label (its parts get clicks too)
local clickHandlers: { [TextLabel]: (string) -> () } = setmetatable({}, { __mode = "k" }) :: any
-- Labels that already listen for clicks (a message label, or one of its parts)
local clickable: { [TextLabel]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local render: (label: TextLabel) -> ()

local function editedTag(palette): (string, string)
	return string.format('<font size="10" color="%s">', RichText.toHex(palette.timestamp)), "</font>"
end

-- Clicks on one label of a message: links, spoilers and #tags
local function connectClicks(target: TextLabel, message: TextLabel)
	if clickable[target] then
		return
	end
	clickable[target] = true
	target.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local x = input.Position.X - target.AbsolutePosition.X
		local y = input.Position.Y - target.AbsolutePosition.Y
		task.spawn(function()
			local run = TextLayout.hitTest(target, x, y)
			if not run then
				return
			end
			local style = run.style
			if style.spoiler then
				local state = states[message]
				if state and not state.revealed then
					state.revealed = true
					render(message)
				end
			elseif style.url then
				local onOpenFail = clickHandlers[message]
				if not Browser.open(style.url) and onOpenFail then
					onOpenFail(style.url)
				end
			elseif style.tag and MessageText.onTag then
				MessageText.onTag(style.tag)
			end
		end)
	end)
end

-- A label for a text part, styled like the message label
local function partLabel(message: TextLabel, name: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.FontFace = message.FontFace
	label.TextSize = message.TextSize
	label.TextColor3 = message.TextColor3
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = true
	label.LayoutOrder = order
	label.ZIndex = message.ZIndex
	return label
end

-- Markdown into a part's label, with its doc registered, clicks and mention pills
local function fillText(label: TextLabel, message: TextLabel, text: string, state: State, withEdited: boolean)
	local doc = Markdown.parse(text, state.palette, { textSize = message.TextSize, revealSpoilers = state.revealed })
	if withEdited then
		local open, close = editedTag(state.palette)
		Markdown.append(doc, if text == "" then "(edited)" else " (edited)", open, close)
	end
	table.insert(state.docs, doc)
	TextLayout.setDoc(label, doc)
	label.Text = doc.markup
	MentionPills.attach(label, state.palette)
	if clickHandlers[message] then
		connectClicks(label, message)
	end
end

local function codeBlock(message: TextLabel, block: Markdown.Block, palette, order: number): Frame
	local box = Instance.new("Frame")
	box.Name = "CodeBlock"
	box.BackgroundColor3 = palette.codeBack or palette.inputFrame
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.LayoutOrder = order
	box.ZIndex = message.ZIndex
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CODE_RADIUS)
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Color = palette.codeBorder or palette.divider
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, CODE_PADDING)
	padding.PaddingBottom = UDim.new(0, CODE_PADDING)
	padding.PaddingLeft = UDim.new(0, CODE_PADDING + 2)
	padding.PaddingRight = UDim.new(0, CODE_PADDING + 2)
	padding.Parent = box

	local code = string.gsub(block.text, "\t", "    ")
	local label = Instance.new("TextLabel")
	label.Name = "Code"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.FontFace = Theme.FONTS.mono
	label.TextSize = math.max(message.TextSize - 1, 10)
	label.TextColor3 = palette.codeText or palette.messageText
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = true
	label.Text = if SyntaxHighlight.isSupported(block.language)
		then SyntaxHighlight.highlight(code, palette)
		else RichText.escape(code)
	label.ZIndex = message.ZIndex
	label.Parent = box
	box:SetAttribute("Language", block.language)
	return box
end

local function quoteBlock(message: TextLabel, block: Markdown.Block, state: State, order: number, last: boolean): Frame
	local palette = state.palette
	local quote = Instance.new("Frame")
	quote.Name = "Quote"
	quote.BackgroundTransparency = 1
	quote.Size = UDim2.new(1, 0, 0, 0)
	quote.AutomaticSize = Enum.AutomaticSize.Y
	quote.LayoutOrder = order
	quote.ZIndex = message.ZIndex

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = palette.quoteBar or palette.timestamp
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromOffset(QUOTE_BAR, 0)
	bar.ZIndex = message.ZIndex
	bar.Parent = quote
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, QUOTE_BAR // 2)
	corner.Parent = bar

	local text = partLabel(message, "Text", 1)
	text.Position = UDim2.fromOffset(QUOTE_INDENT, 0)
	text.Size = UDim2.new(1, -QUOTE_INDENT, 0, 0)
	text.Parent = quote
	fillText(text, message, block.text, state, last)
	-- The bar is as tall as the text (a scale height wouldn't size the quote)
	local function fit()
		bar.Size = UDim2.fromOffset(QUOTE_BAR, text.AbsoluteSize.Y)
	end
	text:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	return quote
end

local function clearParts(label: TextLabel)
	for _, child in ipairs(label:GetChildren()) do
		if child:GetAttribute("MessagePart") then
			child:Destroy()
		end
	end
end

render = function(label: TextLabel)
	local state = states[label]
	if not state then
		return
	end
	state.docs = {}
	clearParts(label)
	local blocks = Markdown.blocks(state.content)
	local onlyText = #blocks == 0 or (#blocks == 1 and blocks[1].kind == "text")
	label.RichText = true

	if onlyText then
		-- One label: the whole message (blank lines around it kept as typed)
		local doc = Markdown.parse(state.content, state.palette, {
			textSize = label.TextSize,
			revealSpoilers = state.revealed,
		})
		if state.edited then
			local open, close = editedTag(state.palette)
			Markdown.append(doc, " (edited)", open, close)
		end
		table.insert(state.docs, doc)
		TextLayout.setDoc(label, doc)
		label.Text = doc.markup
		MentionPills.render(label)
		return
	end

	-- In parts: the label itself shows nothing and lays its parts out
	TextLayout.setDoc(label, Markdown.plainDoc(""))
	label.Text = ""
	local layout = Instance.new("UIListLayout")
	layout.Name = "PartsLayout"
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, BLOCK_GAP)
	layout:SetAttribute("MessagePart", true)
	layout.Parent = label
	for index, block in ipairs(blocks) do
		local last = index == #blocks
		local part: GuiObject
		if block.kind == "code" then
			part = codeBlock(label, block, state.palette, index)
		elseif block.kind == "quote" then
			part = quoteBlock(label, block, state, index, last and state.edited)
		else
			local text = partLabel(label, "Text", index)
			fillText(text, label, block.text, state, last and state.edited)
			part = text
		end
		part:SetAttribute("MessagePart", true)
		part.Parent = label
	end
	-- "(edited)" after a code block goes on its own line
	if state.edited and blocks[#blocks].kind == "code" then
		local note = partLabel(label, "Edited", #blocks + 1)
		note:SetAttribute("MessagePart", true)
		fillText(note, label, "", state, true)
		note.Parent = label
	end
	MentionPills.render(label)
end

--[=[
	Shows `content` (markdown) in a message label.
]=]
function MessageText.set(label: TextLabel, content: string?, palette, options: { edited: boolean? }?)
	local previous = states[label]
	states[label] = {
		content = content or "",
		palette = palette,
		edited = options ~= nil and options.edited == true,
		-- A revealed spoiler stays revealed after a theme change
		revealed = previous ~= nil and previous.revealed and previous.content == (content or ""),
		docs = {},
	}
	if not sizeWatched[label] then
		sizeWatched[label] = true
		-- Headers are sized from the text size: re-render when it changes
		label:GetPropertyChangedSignal("TextSize"):Connect(function()
			render(label)
		end)
	end
	render(label)
end

--[=[
	The links in a label's message (typed and masked), for link previews.
	Links inside code blocks don't count.
]=]
function MessageText.urls(label: TextLabel): { string }
	local state = states[label]
	if not state then
		return Markdown.urls((TextLayout.docOf(label)))
	end
	local urls, seen = {}, {}
	for _, doc in ipairs(state.docs) do
		for _, url in ipairs(Markdown.urls(doc)) do
			if not seen[url] then
				seen[url] = true
				table.insert(urls, url)
			end
		end
	end
	return urls
end

--[=[
	Clicks on the label: links open (`onOpenFail(url)` when the browser
	couldn't), spoilers reveal, #tags call MessageText.onTag. A message drawn
	in parts gets clicks on each text part.
]=]
function MessageText.attachClicks(label: TextLabel, onOpenFail: ((string) -> ())?)
	clickHandlers[label] = onOpenFail or function() end
	connectClicks(label, label)
	for _, part in ipairs(label:GetDescendants()) do
		if part:IsA("TextLabel") and part.Name ~= "Code" and part:FindFirstAncestorWhichIsA("TextLabel") == label then
			connectClicks(part, label)
		end
	end
end

return MessageText
