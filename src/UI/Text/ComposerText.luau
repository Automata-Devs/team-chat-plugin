--!strict
--[[
	ComposerText

	Markdown styled right in the message box while you type, like Discord:
	**bold**, *italic*, `code`, ```lua blocks, links, quotes and the rest
	(Util/MarkdownSource), markers still there but dimmed.

	A TextBox can't show RichText while you type in it, so its own text is
	made invisible and a label with the styled text lies exactly on top of
	it. The styles never change how wide a letter is, so everything lines
	up; the text cursor and selection (hidden along with the TextBox's
	text) are drawn here, measured with UI/TextLayout.

	Usage:
		local composer = ComposerText.attach(textBox, { getPalette = function() return palette end })
		composer.recolor()
]]

local MarkdownSource = require(script.Parent.Parent.Parent.Util.MarkdownSource)
local TextLayout = require(script.Parent.TextLayout)

local BLINK = 0.53 -- seconds the cursor is on, then off
local CARET_WIDTH = 1
local SELECTION_TRANSPARENCY = 0.55

type Palette = { [string]: Color3 }

export type Options = { getPalette: () -> Palette }

export type Composer = {
	overlay: TextLabel,
	refresh: () -> (),
	recolor: () -> (),
}

local ComposerText = {}

function ComposerText.attach(textBox: TextBox, options: Options): Composer
	local overlay = Instance.new("TextLabel")
	overlay.Name = "MarkdownText"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.RichText = true
	overlay.Text = ""
	overlay.ZIndex = textBox.ZIndex + 2
	overlay.Parent = textBox

	local caret = Instance.new("Frame")
	caret.Name = "Caret"
	caret.BorderSizePixel = 0
	caret.Visible = false
	caret.ZIndex = textBox.ZIndex + 3
	caret.Parent = textBox

	-- Looks and lays out like the box itself
	local function match()
		overlay.FontFace = textBox.FontFace
		overlay.TextSize = textBox.TextSize
		overlay.TextWrapped = textBox.TextWrapped
		overlay.TextXAlignment = textBox.TextXAlignment
		overlay.TextYAlignment = textBox.TextYAlignment
		overlay.LineHeight = textBox.LineHeight
	end
	match()
	for _, property in ipairs({ "FontFace", "TextSize", "TextWrapped", "TextXAlignment", "TextYAlignment" }) do
		textBox:GetPropertyChangedSignal(property):Connect(match)
	end

	local function clearSelection()
		for _, child in ipairs(textBox:GetChildren()) do
			if child.Name == "Selection" then
				child:Destroy()
			end
		end
	end

	-- The cursor and selection, drawn where TextLayout says they are in the
	-- styled text (measured on it, so they match what you see)
	local doc = MarkdownSource.doc("", options.getPalette())
	local version = 0
	local lastMove = os.clock()
	local function placeCursor()
		version += 1
		local mine = version
		lastMove = os.clock()
		local text = textBox.Text
		local cursor = textBox.CursorPosition
		local anchor = textBox.SelectionStart
		-- An empty box shows its placeholder and its own cursor
		if text == "" or not textBox:IsFocused() or cursor < 1 then
			caret.Visible = false
			clearSelection()
			return
		end
		local shown = doc
		task.spawn(function()
			local rect = TextLayout.caret(overlay, shown, cursor)
			local selection = if anchor > 0 and anchor ~= cursor
				then TextLayout.lineRects(overlay, shown, math.min(anchor, cursor), math.max(anchor, cursor) - 1)
				else {}
			if mine ~= version or not textBox.Parent then
				return
			end
			local palette = options.getPalette()
			caret.BackgroundColor3 = palette.textBoxText or palette.messageText
			caret.Position = UDim2.fromOffset(math.floor(rect.x), math.floor(rect.y))
			caret.Size = UDim2.fromOffset(CARET_WIDTH, math.ceil(rect.height))
			caret.Visible = #selection == 0
			clearSelection()
			for _, box in ipairs(selection) do
				local highlight = Instance.new("Frame")
				highlight.Name = "Selection"
				highlight.BorderSizePixel = 0
				highlight.BackgroundColor3 = palette.sendButton
				highlight.BackgroundTransparency = SELECTION_TRANSPARENCY
				highlight.Position = UDim2.fromOffset(math.floor(box.x), math.floor(box.y))
				highlight.Size = UDim2.fromOffset(math.ceil(box.width), math.ceil(box.height))
				highlight.ZIndex = textBox.ZIndex + 1
				highlight.Parent = textBox
			end
		end)
	end

	local function render()
		local text = textBox.Text
		local palette = options.getPalette()
		-- The box's own text hides behind the styled copy (but not its placeholder)
		textBox.TextTransparency = if text == "" then 0 else 1
		overlay.TextColor3 = palette.textBoxText or palette.messageText
		doc = MarkdownSource.doc(text, palette)
		TextLayout.setDoc(overlay, doc)
		overlay.Text = doc.markup
		placeCursor()
	end

	textBox:GetPropertyChangedSignal("Text"):Connect(render)
	textBox:GetPropertyChangedSignal("CursorPosition"):Connect(placeCursor)
	textBox:GetPropertyChangedSignal("SelectionStart"):Connect(placeCursor)
	textBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeCursor)
	textBox.FocusLost:Connect(placeCursor)

	-- Blink while the box has focus (steady for a moment after each move)
	textBox.Focused:Connect(function()
		placeCursor()
		task.spawn(function()
			local on = true
			while textBox.Parent and textBox:IsFocused() do
				task.wait(BLINK)
				on = if os.clock() - lastMove < BLINK then true else not on
				local selecting = textBox.SelectionStart > 0 and textBox.SelectionStart ~= textBox.CursorPosition
				caret.Visible = on and textBox.Text ~= "" and not selecting
			end
			caret.Visible = false
		end)
	end)
	render()

	return {
		overlay = overlay,
		refresh = render,
		recolor = render,
	}
end

return ComposerText
