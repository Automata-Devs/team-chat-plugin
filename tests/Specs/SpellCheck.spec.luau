--[[
	Spell check: which words are misspelled (and which aren't checked), the
	suggestions, the red lines in the message box, and fixing a word or
	adding it to the dictionary from the suggestions.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local ok, err = pcall(function()
		local ui, gui = app.ui, app.gui
		local SpellCheck = require(app.copy.Util.SpellCheck) :: any
		SpellCheck.load()
		t.check("the dictionary loads", SpellCheck.isReady())

		local function words(text: string, cursor: number?): string
			local found = {}
			for _, word in ipairs(SpellCheck.check(text, cursor)) do
				table.insert(found, word.word)
			end
			return table.concat(found, ",")
		end

		-- What's wrong, and what isn't
		t.equal("misspelled words are found", words("I recieve teh mail"), "recieve,teh")
		t.equal("…with where they are", SpellCheck.check("I recieve")[1].start, 3)
		t.equal("right words aren't", words("Hello there, the weather's fine in Amsterdam today"), "")
		t.equal("possessives count as their word", words("the dog's bone and the cats' toys"), "")
		t.equal(
			"code, links, mentions, tags and emoji aren't checked",
			words("`wrng` ```\nfoobaz\n``` https://exmaple.com @bilderman #[Workspace.Partt] :smilee:"),
			""
		)
		t.equal("identifiers aren't checked", words("script.Parent getChildren my_varr thing2go HTTPSERVICE"), "")
		t.equal("a /command isn't checked", words("/kik someone"), "")
		t.equal("the word being typed isn't marked yet", words("hello wrold", 12), "")
		t.equal("…until you move on", words("hello wrold", 6), "wrold")
		t.equal("chat words are fine", words("lol ok brb roblox luau"), "")

		-- Suggestions
		local suggestions = SpellCheck.suggest("recieve")
		t.equal("the likeliest suggestion comes first", suggestions[1], "receive")
		t.equal("swapped letters are a likely typo", SpellCheck.suggest("teh")[1], "the")
		t.equal("capitals are kept", SpellCheck.suggest("Wierd")[1], "Weird")
		t.check("at most 5", #SpellCheck.suggest("tset") <= 5)

		SpellCheck.addWords({ "Blorbo" })
		t.equal("added words count as right", words("blorbo"), "")

		-- The red lines in the message box
		local box = ui.textBox :: TextBox
		box.Text = "this is wierd text"
		local marks = 0
		for _ = 1, 30 do
			task.wait(0.1)
			marks = 0
			for _, child in ipairs(box:GetChildren()) do
				if child.Name == "SpellMark" and child:FindFirstChildOfClass("Path2D") then
					marks += 1
				end
			end
			if marks > 0 then
				break
			end
		end
		t.equal("a misspelled word gets a red line", marks, 1)

		-- Putting the cursor in it lists suggestions
		local autocomplete = gui:FindFirstChild("Autocomplete", true) :: Frame
		task.wait(0.2)
		box.CursorPosition = 11 -- in "wierd"
		Harness.settle(3)
		local labels = {}
		for _, item in ipairs(autocomplete:GetChildren()) do
			local label = item:FindFirstChild("CmdName", true)
			if item.Name:match("^Item_") and label then
				table.insert(labels, (label :: TextLabel).Text)
			end
		end
		t.check("the cursor in a red word shows suggestions", autocomplete.Visible and labels[1] == "weird")
		t.check("…and Add to dictionary", string.find(labels[#labels] or "", "to dictionary", 1, true) ~= nil)

		-- Tab picks the first suggestion
		box.Text = "this is wi\terd text" -- Tab pressed with the cursor in "wierd"
		Harness.settle(3)
		t.equal("picking a suggestion fixes the word", box.Text, "this is weird text")

		-- Add to dictionary: remembered in the plugin settings
		box.Text = "a zorbleflax here"
		task.wait(0.6)
		box.CursorPosition = 5
		Harness.settle(3)
		local count = 0
		for _, item in ipairs(autocomplete:GetChildren()) do
			if item.Name:match("^Item_") then
				count += 1
			end
		end
		-- The last item is Add to dictionary (picked as a click would)
		for _, item in ipairs(autocomplete:GetChildren()) do
			if item.Name == "Item_" .. count then
				local label = item:FindFirstChild("CmdName", true) :: TextLabel
				t.check(
					"unknown words can be added",
					label ~= nil and string.find(label.Text, "zorbleflax", 1, true) ~= nil
				)
			end
		end
		app.hooks.pickAutocomplete(count)
		Harness.settle(3)
		t.equal("adding keeps the text", box.Text, "a zorbleflax here")
		t.check("…the word is fine now", SpellCheck.isCorrect("zorbleflax"))
		local saved = app.settings.TeamChatDictionary_v1
		t.check(
			"…and saved in the plugin settings",
			type(saved) == "string" and string.find(saved, "zorbleflax", 1, true) ~= nil
		)
		box.Text = ""
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
