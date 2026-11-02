--[[
	Markdown: Discord-style formatting in messages, turned into RichText
	runs that the chat can still measure (links, @mentions, #tags).
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local Markdown = require(app.copy.Util.Markdown) :: any
		local Theme = require(app.copy.Config.Theme) :: any
		local palette = Theme.PALETTES.Dark

		local function render(text: string): string
			return Markdown.parse(text, palette, { textSize = 15 }).markup
		end
		local function has(haystack: string, needle: string): boolean
			return string.find(haystack, needle, 1, true) ~= nil
		end

		-- Inline styles
		t.check("**bold**", has(render("a **b** c"), "<b>b</b>"))
		t.check("*italic* and _italic_", has(render("*i*"), "<i>i</i>") and has(render("_i_"), "<i>i</i>"))
		t.check("__underline__", has(render("__u__"), "<u>u</u>"))
		t.check("~~strikethrough~~", has(render("~~s~~"), "<s>s</s>"))
		t.check("***bold italic***", has(render("***x***"), "<b><i>x</i></b>"))
		t.check("`code` is monospace", has(render("`x = 1`"), "BuilderMono") and has(render("`x = 1`"), "x = 1"))
		t.check("markdown inside `code` stays as typed", has(render("`**no**`"), "**no**"))
		t.equal("snake_case stays as it is", Markdown.strip("my_var_name"), "my_var_name")
		t.equal("a \\* shows a star", Markdown.strip("\\*not italic\\*"), "*not italic*")
		t.equal("the shrug survives", Markdown.strip("¯\\_(ツ)_/¯"), "¯_(ツ)_/¯")
		t.equal("a lone * stays", Markdown.strip("2 * 3 = 6"), "2 * 3 = 6")

		-- Lines
		local header = Markdown.parse("# Big", palette, { textSize = 15 })
		t.check("# makes a big bold header", has(header.markup, 'size="24"') and has(header.markup, "<b>Big</b>"))
		t.equal("## and ### are smaller", select(3, string.find(render("### h"), 'size="(%d+)"')), "17")
		t.check("-# makes small muted subtext", has(render("-# small"), 'size="12"'))
		t.equal("> quotes get a bar", Markdown.strip("> said"), "\u{258E} said")
		t.equal("- lists get bullets", Markdown.strip("- one\n- two"), "\u{2022} one\n\u{2022} two")
		local block = Markdown.parse("```\nlocal x = **1**\n```", palette, {})
		t.equal("``` code blocks keep their text", block.plain, "\nlocal x = **1**\n")

		-- Links, masked links, mentions, tags and spoilers
		local masked = Markdown.parse("see [the docs](https://create.roblox.com) now", palette, {})
		t.equal("[text](url) shows the text", masked.plain, "see the docs now")
		t.equal("…and links to the url", Markdown.urls(masked)[1], "https://create.roblox.com")
		local mixed = Markdown.parse("**hey** @builderman look at #[Workspace.Map.Door]", palette, {})
		local mention, tag
		for _, run in ipairs(mixed.runs) do
			mention = mention or run.style.mention
			tag = tag or run.style.tag
		end
		t.equal("@mentions are runs", mention, "builderman")
		t.equal("#[object] tags are runs", tag, "Workspace.Map.Door")
		t.check("…shown as #Name", has(mixed.plain, "#Door") and not has(mixed.plain, "Workspace"))
		local hidden = Markdown.parse("the end: ||they win||", palette, {})
		local shown = Markdown.parse("the end: ||they win||", palette, { revealSpoilers = true })
		t.check("||spoilers|| are hidden", has(hidden.markup, 'transparency="1"'))
		t.check("…until revealed", not has(shown.markup, 'transparency="1"'))

		-- Slices keep their tags, so parts can be measured
		local doc = Markdown.parse("**bold** plain", palette, {})
		t.equal("a slice keeps the style", Markdown.slice(doc, 1, 2), "<b>bo</b>")
		t.equal("plain text is what the label shows", doc.plain, "bold plain")

		-- In a message: formatted, with the mention pill after the bold word
		local ui, gui = app.ui, app.gui
		local stamp = os.time() + 900
		ui.addMessage("builderman", stamp, "**Look** @builderman", nil, nil, 156)
		Harness.settle()
		local row
		for _, child in ipairs(gui:FindFirstChild("MessageList", true):GetChildren()) do
			if child:GetAttribute("Timestamp") == stamp then
				row = child
			end
		end
		local label = row and row:FindFirstChild("TextContent") :: TextLabel
		t.check("messages show markdown", label ~= nil and has(label.Text, "<b>Look</b>"))
		t.equal("…and show the text without the markers", label and label.ContentText, "Look @builderman")
		local pill
		for _ = 1, 40 do
			pill = label and label:FindFirstChild("MentionPill")
			if pill then
				break
			end
			task.wait(0.1)
		end
		local params = Instance.new("GetTextBoundsParams")
		params.Text = "<b>Look</b> "
		params.RichText = true
		params.Font = label.FontFace
		params.Size = label.TextSize
		params.Width = 1000
		local boldWidth = game:GetService("TextService"):GetTextBoundsAsync(params).X
		t.check(
			("the mention pill starts after the bold word (x %d, bold %d)"):format(
				pill and pill.Position.X.Offset or -1,
				boldWidth
			),
			pill ~= nil and math.abs(pill.Position.X.Offset + 2 - boldWidth) <= 2
		)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
