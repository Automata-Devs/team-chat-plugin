--!strict
--[[
	MessageText

	Shows a message's text with markdown (Util/Markdown) and makes it
	clickable: links open in the browser, a ||spoiler|| reveals itself, and a
	#[object] tag calls MessageText.onTag (the chat window moves the camera
	to it). The doc is registered with UI/TextLayout, so clicks and the
	@mention highlights (UI/MentionPills) measure the formatted text.

	Usage:
		MessageText.set(label, content, palette, { edited = true })
		MessageText.attachClicks(label, function(url) ... end) -- url couldn't open
]]

local Browser = require(script.Parent.Parent.Core.Browser)
local Markdown = require(script.Parent.Parent.Util.Markdown)
local RichText = require(script.Parent.Parent.Util.RichText)
local TextLayout = require(script.Parent.TextLayout)
local MentionPills = require(script.Parent.MentionPills)

local MessageText = {}

-- Called with an object path when a #tag is clicked (set by the chat window)
MessageText.onTag = nil :: ((path: string) -> ())?

type State = { content: string, palette: any, edited: boolean, revealed: boolean }

local states: { [TextLabel]: State } = setmetatable({}, { __mode = "k" }) :: any
local sizeWatched: { [TextLabel]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function render(label: TextLabel)
	local state = states[label]
	if not state then
		return
	end
	local doc = Markdown.parse(state.content, state.palette, {
		textSize = label.TextSize,
		revealSpoilers = state.revealed,
	})
	if state.edited then
		Markdown.append(
			doc,
			" (edited)",
			string.format('<font size="10" color="%s">', RichText.toHex(state.palette.timestamp)),
			"</font>"
		)
	end
	TextLayout.setDoc(label, doc)
	label.RichText = true
	label.Text = doc.markup
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
]=]
function MessageText.urls(label: TextLabel): { string }
	local doc = TextLayout.docOf(label)
	return Markdown.urls(doc)
end

--[=[
	Clicks on the label: links open (`onOpenFail(url)` when the browser
	couldn't), spoilers reveal, #tags call MessageText.onTag.
]=]
function MessageText.attachClicks(label: TextLabel, onOpenFail: ((string) -> ())?)
	label.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local x = input.Position.X - label.AbsolutePosition.X
		local y = input.Position.Y - label.AbsolutePosition.Y
		task.spawn(function()
			local run = TextLayout.hitTest(label, x, y)
			if not run then
				return
			end
			local style = run.style
			if style.spoiler then
				local state = states[label]
				if state and not state.revealed then
					state.revealed = true
					render(label)
				end
			elseif style.url then
				if not Browser.open(style.url) and onOpenFail then
					onOpenFail(style.url)
				end
			elseif style.tag and MessageText.onTag then
				MessageText.onTag(style.tag)
			end
		end)
	end)
end

return MessageText
