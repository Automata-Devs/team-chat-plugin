--!strict
--[[
	SpellingMarks

	The red wavy line under misspelled words in the message box, like
	Discord and browsers. Util/SpellCheck finds the words, UI/TextLayout
	measures where they are, and each line is a Path2D zigzag. The word
	you're still typing isn't marked until you move on from it.

	Usage:
		local marks = SpellingMarks.attach(textBox, {
			getPalette = function() return palette end,
			isEnabled = function() return Preferences.values.spellCheck end,
		})
		marks.wordAt(textBox.CursorPosition)   -- the misspelled word the cursor is in, if any
		marks.refresh()                        -- after a setting or the dictionary changed
]]

local SpellCheck = require(script.Parent.Parent.Util.SpellCheck)
local TextLayout = require(script.Parent.TextLayout)

local DELAY = 0.25 -- seconds after typing stops before checking
local WAVE_STEP = 2 -- pixels between the zigzag's points
local WAVE_HEIGHT = 2

type Palette = { [string]: Color3 }

export type Options = {
	getPalette: () -> Palette,
	isEnabled: () -> boolean,
}

export type Marks = {
	refresh: () -> (),
	wordAt: (cursor: number) -> SpellCheck.Misspelling?,
	recolor: () -> (),
}

local SpellingMarks = {}

local function clear(textBox: TextBox)
	for _, child in ipairs(textBox:GetChildren()) do
		if child.Name == "SpellMark" then
			child:Destroy()
		end
	end
end

-- A red zigzag under a word (a frame under the text, with a Path2D in it)
local function makeMark(textBox: TextBox, x: number, y: number, width: number, color: Color3)
	local mark = Instance.new("Frame")
	mark.Name = "SpellMark"
	mark.BackgroundTransparency = 1
	mark.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	mark.Size = UDim2.fromOffset(math.ceil(width), WAVE_HEIGHT + 1)
	mark.ZIndex = textBox.ZIndex + 1
	local points = {}
	local steps = math.max(2, math.floor(width / WAVE_STEP))
	for i = 0, steps do
		local px = math.min(i * WAVE_STEP, width)
		local py = if i % 2 == 0 then WAVE_HEIGHT else 0
		table.insert(points, Path2DControlPoint.new(UDim2.fromOffset(px, py)))
	end
	local line = Instance.new("Path2D")
	line.Name = "Wave"
	line.Color3 = color
	line.Thickness = 1
	line.ZIndex = textBox.ZIndex + 1
	line:SetControlPoints(points)
	line.Parent = mark
	mark.Parent = textBox
end

function SpellingMarks.attach(textBox: TextBox, options: Options): Marks
	local misspelled: { SpellCheck.Misspelling } = {}
	local version = 0
	local lastText = textBox.Text

	-- Checks the text now and redraws the marks (measuring yields)
	local function draw()
		version += 1
		local myVersion = version
		local text = textBox.Text
		if not options.isEnabled() or text == "" or not SpellCheck.isReady() then
			misspelled = {}
			clear(textBox)
			return
		end
		-- The word just typed isn't marked while the cursor is still at its end
		local typing = if textBox:IsFocused() and text ~= lastText then textBox.CursorPosition else nil
		lastText = text
		local found = SpellCheck.check(text, typing)
		local all = SpellCheck.check(text)
		task.spawn(function()
			local doc = TextLayout.docOf(textBox)
			local rects = {}
			for _, word in ipairs(found) do
				local rect = TextLayout.rect(textBox, doc, word.start, word.finish, false)
				if rect then
					table.insert(rects, rect)
				end
			end
			if version ~= myVersion or not textBox.Parent then
				return
			end
			misspelled = all
			clear(textBox)
			local color = options.getPalette().danger
			for _, rect in ipairs(rects) do
				makeMark(textBox, rect.x, rect.y + rect.height - WAVE_HEIGHT, rect.width, color)
			end
		end)
	end

	local pending = 0
	local function schedule()
		pending += 1
		local mine = pending
		task.delay(DELAY, function()
			if mine == pending then
				draw()
			end
		end)
	end

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if textBox.Text == "" then
			misspelled = {}
			clear(textBox)
		end
		-- Load the words the first time something is typed
		if options.isEnabled() and not SpellCheck.isReady() then
			task.spawn(SpellCheck.load)
		end
		schedule()
	end)
	-- Moving on from a word (click, arrows, focus lost) marks it if it's wrong
	textBox:GetPropertyChangedSignal("CursorPosition"):Connect(schedule)
	textBox.FocusLost:Connect(schedule)
	textBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule)
	SpellCheck.onReady(schedule)

	return {
		refresh = draw,
		wordAt = function(cursor: number): SpellCheck.Misspelling?
			for _, word in ipairs(misspelled) do
				if cursor >= word.start and cursor <= word.finish + 1 then
					return word
				end
			end
			return nil
		end,
		recolor = function()
			local color = options.getPalette().danger
			for _, child in ipairs(textBox:GetChildren()) do
				local wave = if child.Name == "SpellMark" then child:FindFirstChild("Wave") else nil
				if wave and wave:IsA("Path2D") then
					wave.Color3 = color
				end
			end
		end,
	}
end

return SpellingMarks
