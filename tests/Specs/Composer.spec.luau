--[[
	The message box shows markdown as you type, like Discord: the markers
	stay (dimmed) and the text is styled, laid out exactly like the box's
	own (invisible) text so the cursor and selection line up.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui = app.ui
		local MarkdownSource = require(app.copy.Util.MarkdownSource) :: any
		local Theme = require(app.copy.Config.Theme) :: any
		local palette = Theme.PALETTES.Dark
		local TextService = game:GetService("TextService")

		local function has(haystack: string, needle: string): boolean
			return string.find(haystack, needle, 1, true) ~= nil
		end
		local probe = Instance.new("TextLabel")
		probe.RichText = true
		local function shown(markup: string): string
			probe.Text = markup
			return probe.ContentText
		end
		local function width(text: string, rich: boolean): number
			local params = Instance.new("GetTextBoundsParams")
			params.Text = text
			params.RichText = rich
			params.Font = ui.textBox.FontFace
			params.Size = ui.textBox.TextSize
			params.Width = 400
			return TextService:GetTextBoundsAsync(params).X
		end

		-- What you typed, exactly, styled
		local samples = {
			"**bold** *italic* __under__ ~~gone~~ ||secret|| `code` @builderman",
			"# Header\n-# small\n- item\n  - nested\n> quote\n>>> rest\nof it",
			"[link](https://create.roblox.com) and https://roblox.com & <b>not a tag</b>",
			"```lua\nlocal x = 1 -- one\n```\n```plain```",
			"unclosed ``` and **half",
			"\\*escaped\\* snake_case_name #[Workspace.Part]",
		}
		for index, sample in ipairs(samples) do
			local markup = MarkdownSource.render(sample, palette)
			t.equal(("sample %d shows exactly what was typed"):format(index), shown(markup), sample)
			-- (each styled run rounds its width a little; the cursor is measured
			-- on the styled text, so it never drifts from what you see)
			t.check(
				("…and is just as wide (%d)"):format(index),
				math.abs(width(markup, true) - width(sample, false)) <= 2
			)
		end
		local markup = MarkdownSource.render("**b** *i* `c` > q", palette)
		t.check("bold is an outline, not wider letters", has(markup, "<stroke") and not has(markup, "<b>"))
		t.check("italic is italic", has(markup, "<i>i</i>"))
		t.check("code has a box", has(markup, "<mark"))
		t.check(
			"markers are dimmed",
			has(markup, '<font color="#' .. string.upper(palette.timestamp:ToHex()) .. '">**</font>')
		)
		local quote = MarkdownSource.render("> said", palette)
		t.check("a quote's > is a bar", has(quote, '<font transparency="1">&gt;</font></mark>'))
		t.check("```lua is coloured", has(MarkdownSource.render("```lua\nlocal x\n```", palette), "#FF7B72"))

		-- In the message box
		local box = ui.textBox :: TextBox
		local overlay = box:FindFirstChild("MarkdownText") :: TextLabel
		t.check("the box has the styled text on top", overlay ~= nil)
		box.Text = "**hello** world"
		Harness.settle()
		t.equal("…showing what's typed", overlay.ContentText, "**hello** world")
		t.equal("…while the box's own text is hidden", box.TextTransparency, 1)
		box.Text = ""
		Harness.settle()
		t.check("an empty box shows its placeholder", box.TextTransparency == 0 and overlay.Text == "")

		-- The cursor and selection are drawn
		box.Text = "**hello** world"
		box:CaptureFocus()
		Harness.settle()
		if box:IsFocused() then
			box.CursorPosition = 8 -- after "hello"
			task.wait(0.3)
			local caret = box:FindFirstChild("Caret") :: Frame
			local expected = math.floor(width("**hello", false))
			t.check(
				("the cursor is drawn after the word (x %s, expected %d)"):format(
					tostring(caret and caret.Position.X.Offset),
					expected
				),
				caret ~= nil and caret.Visible and math.abs(caret.Position.X.Offset - expected) <= 2
			)
			box.SelectionStart = 3
			task.wait(0.3)
			local selections = 0
			for _, child in ipairs(box:GetChildren()) do
				if child.Name == "Selection" then
					selections += 1
				end
			end
			t.equal("a selection is highlighted", selections, 1)
			t.check("…and the cursor hides while selecting", not caret.Visible)
			box:ReleaseFocus()
			Harness.settle()
		else
			t.check("(the box can't take focus here; the cursor isn't checked)", true)
		end
		box.Text = ""
		probe:Destroy()
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
