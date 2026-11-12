--[[
	Suggestions

	What the dropdown above the message box suggests while you type:
	commands ("/na"), a command's options ("/name "), an option's choices,
	people ("@na"), objects in the place ("#Na"), emoji (":smi") and, for a
	word with a red line under the cursor, spellings and "Add to dictionary".
	Components/Autocomplete draws the dropdown.

	Studio sends plugin widgets no keyboard events, so a suggestion is picked
	by clicking it (hovering highlights it) or with Tab, which is noticed
	from the tab character it types into the box.

	Usage:
		local suggestions = Suggestions.create(ctx, { frame = frame, composer = composer, ... })
		suggestions.setCommandProvider(function() return commands end)
]]

local Players = game:GetService("Players")

local Animation = require(script.Parent.Parent.Common.Animation)
local Author = require(script.Parent.Parent.Messages.Author)
local Autocomplete = require(script.Parent.Parent.Components.Autocomplete)
local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local EmojiData = require(script.Parent.Parent.Parent.Util.EmojiData)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Mentions = require(script.Parent.Parent.Parent.Util.Mentions)
local Preferences = require(script.Parent.Parent.Common.Preferences)
local SpellCheck = require(script.Parent.Parent.Parent.Util.SpellCheck)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

export type Options = {
	frame: Frame, -- from Autocomplete.create
	composer: any,
	-- The sidebar's conversations (DM contacts are offered as @mentions)
	getConversations: () -> { { [string]: any } }?,
}

local Suggestions = {}

-- A "#name" being typed at the end of the text (not a "# " header, not in
-- the middle of a word): where its "#" is and the name so far
local function typingTag(text: string): (number?, string?)
	local hashPos, partial = string.match(text, "()#([%w_%-]*)$")
	if not hashPos then
		return nil, nil
	end
	local before = if hashPos > 1 then string.sub(text, hashPos - 1, hashPos - 1) else ""
	if before ~= "" and string.match(before, "[%w_#%[]") then
		return nil, nil
	end
	return hashPos, partial
end

local function commandMatches(cmd, query: string): boolean
	if query == "" or cmd.name:lower():sub(1, #query) == query then
		return true
	end
	for _, alias in ipairs(cmd.aliases or {}) do
		if alias:lower():sub(1, #query) == query then
			return true
		end
	end
	return false
end

function Suggestions.create(ctx, options: Options)
	local frame = options.frame
	local composer = options.composer
	local textBox: TextBox = composer.textBox
	local spelling = composer.spelling
	local objectTags = ctx.services.objectTags

	local items = {}
	local selectedIndex = 1
	local commandProvider = nil
	local mode = nil -- "command" | "emoji" | "args" | "member" | "object" | "choice" | "spelling"
	-- Where the text being completed starts (1-based)
	local emojiMatchStart = nil
	local mentionMatchStart = nil
	local tagMatchStart = nil
	local choiceMatchStart = nil

	local function hide()
		frame.Visible = false
		items = {}
		selectedIndex = 1
	end

	local function updateSelection()
		Autocomplete.setSelected(frame, selectedIndex)
	end

	-- People to @mention whose username or display name starts with `partial`:
	-- everyone in the place and your DM contacts, online first, then @everyone
	local function mentionCandidates(partial: string)
		local query = string.lower(partial)
		local byId = {}
		local function add(userId: number?, username: string?, displayName: string?, online: boolean)
			if type(userId) ~= "number" or userId <= 0 or type(username) ~= "string" or username == "" then
				return
			end
			local known = byId[userId]
			if known then
				known.online = known.online or online
				return
			end
			byId[userId] = { userId = userId, username = username, displayName = displayName, online = online }
		end
		for _, player in ipairs(Players:GetPlayers()) do
			add(player.UserId, player.Name, player.DisplayName, true)
		end
		for _, entry in ipairs(options.getConversations() or {}) do
			if entry.kind == "dm" then
				local profile = if Author.getProfile then Author.getProfile(entry.userId) else nil
				add(entry.userId, entry.name, profile and profile.displayName, entry.online == true)
			end
		end
		local members = {}
		for _, member in pairs(byId) do
			local username = string.lower(member.username)
			local displayName = string.lower(member.displayName or "")
			if
				query == ""
				or string.sub(username, 1, #query) == query
				or string.sub(displayName, 1, #query) == query
			then
				table.insert(members, member)
			end
		end
		table.sort(members, function(a, b)
			if a.online ~= b.online then
				return a.online
			end
			return string.lower(a.displayName or a.username) < string.lower(b.displayName or b.username)
		end)
		while #members > Autocomplete.MAX_ITEMS - 1 do
			table.remove(members)
		end
		if string.sub(Mentions.EVERYONE, 1, #query) == query then
			table.insert(members, { everyone = true, username = Mentions.EVERYONE })
		end
		return members
	end

	local function clearItems()
		for _, child in ipairs(frame:GetChildren()) do
			if child:IsA("TextButton") and child.Name:match("^Item_%d+$") then
				child:Destroy()
			end
		end
	end

	local function applyAutocompleteItem(item)
		if not item then
			return
		end

		if item.type == "spelling" or item.type == "addWord" then
			local word = item.word
			if item.type == "spelling" then
				local text = textBox.Text
				textBox.Text = string.sub(text, 1, word.start - 1)
					.. item.suggestion
					.. string.sub(text, word.finish + 1)
				textBox.CursorPosition = word.start + #item.suggestion
			else
				composer.addToDictionary(word.word)
			end
			hide()
			return
		end

		if item.type == "command" then
			textBox.Text = "/" .. item.name .. " "
		elseif item.type == "emoji" and emojiMatchStart then
			textBox.Text = string.sub(textBox.Text, 1, emojiMatchStart - 1) .. item.emoji .. " "
		elseif item.type == "member" and mentionMatchStart then
			textBox.Text = string.sub(textBox.Text, 1, mentionMatchStart - 1) .. "@" .. item.member.username .. " "
		elseif item.type == "choice" and choiceMatchStart then
			textBox.Text = string.sub(textBox.Text, 1, choiceMatchStart - 1) .. item.choice.name .. " "
		elseif item.type == "object" and tagMatchStart then
			-- Saved as #[full path] (shown as #Name), so it still finds the right one
			textBox.Text = string.sub(textBox.Text, 1, tagMatchStart - 1)
				.. "#["
				.. objectTags.pathOf(item.instance)
				.. "] "
		end
		textBox.CursorPosition = #textBox.Text + 1

		hide()
	end

	local function renderAutocompleteItems()
		Autocomplete.setHint(frame, Autocomplete.defaultHint())

		if #items == 0 then
			frame.Visible = false
			return
		end
		local palette = ctx.palette
		for i, item in ipairs(items) do
			local button
			if item.type == "command" then
				button = Autocomplete.createItem(i, item.cmd, palette, function(rank)
					return Language.tOr(
						"rank." .. tostring(rank),
						Constants.RANK_NAMES[rank] or Constants.RANK_NAMES[0]
					)
				end)
			elseif item.type == "member" then
				button = Autocomplete.createMemberItem(i, item.member, palette)
			elseif item.type == "object" then
				button = Autocomplete.createObjectItem(i, item.instance, palette)
			elseif item.type == "choice" then
				button = Autocomplete.createEmojiItem(i, { emoji = "\u{2022}", name = item.choice.name }, palette)
				local label = button:FindFirstChild("CmdName") :: TextLabel
				label.Text = item.choice.name
				label.FontFace = Theme.FONTS.semibold
			elseif item.type == "spelling" or item.type == "addWord" then
				local adding = item.type == "addWord"
				button =
					Autocomplete.createEmojiItem(i, { emoji = if adding then "+" else "\u{2022}", name = "" }, palette)
				local label = button:FindFirstChild("CmdName") :: TextLabel
				label.Text = if adding then Language.t("spelling.add", { word = item.word.word }) else item.suggestion
				label.FontFace = if adding then Theme.FONTS.body else Theme.FONTS.semibold
			else
				button = Autocomplete.createEmojiItem(i, item, palette)
			end

			button.MouseButton1Click:Connect(function()
				applyAutocompleteItem(item)
			end)
			button.MouseEnter:Connect(function()
				selectedIndex = i
				updateSelection()
			end)
			button.Parent = frame
		end

		Autocomplete.setTitle(frame, Language.t("autocomplete." .. mode))
		frame.Visible = true
		updateSelection()
	end

	-- The command whose options are being typed ("/name args"), and which option
	local function typedCommandArgs(text: string)
		local typedName, rest = text:match("^/(%S+)%s(.*)$")
		if not commandProvider or not typedName then
			return nil, 0
		end
		typedName = typedName:lower()
		for _, cmd in ipairs(commandProvider()) do
			local matches = cmd.name:lower() == typedName
			for _, alias in ipairs(cmd.aliases or {}) do
				matches = matches or alias:lower() == typedName
			end
			if matches then
				if cmd.args and #cmd.args > 0 then
					-- A finished word moves on to the next option
					local words = 0
					for _ in rest:gmatch("%S+") do
						words += 1
					end
					if rest == "" or rest:match("%s$") then
						words += 1
					end
					return cmd, math.clamp(words, 1, #cmd.args)
				end
				return nil, 0
			end
		end
		return nil, 0
	end

	local function updateAutocomplete()
		-- Tab: take the tab character back out and pick the highlighted suggestion
		if string.find(textBox.Text, "\t", 1, true) then
			local selected = frame.Visible and items[selectedIndex or 1]
			textBox.Text = string.gsub(textBox.Text, "\t", "")
			if selected then
				applyAutocompleteItem(selected)
			end
			return
		end

		clearItems()
		items = {}
		selectedIndex = 1
		mode = nil
		emojiMatchStart = nil
		mentionMatchStart = nil
		tagMatchStart = nil
		choiceMatchStart = nil

		local text = textBox.Text
		local argCommand, argIndex = nil, 0

		if commandProvider and text:sub(1, 1) == "/" and not text:find("%s") then
			local query = text:sub(2):lower()
			for _, cmd in ipairs(commandProvider()) do
				if #items >= Autocomplete.MAX_ITEMS then
					break
				end
				if commandMatches(cmd, query) then
					table.insert(items, { type = "command", name = cmd.name, cmd = cmd })
				end
			end
			mode = "command"
		else
			local atPos, partial = Mentions.typing(text)
			if atPos and partial then
				for _, member in ipairs(mentionCandidates(partial)) do
					table.insert(items, { type = "member", member = member })
				end
				mode = "member"
				mentionMatchStart = atPos
			end

			local hashPos, tagPartial = nil, nil
			if not atPos then
				hashPos, tagPartial = typingTag(text)
				if hashPos and tagPartial then
					for _, instance in ipairs(objectTags.search(tagPartial, Autocomplete.MAX_ITEMS)) do
						table.insert(items, { type = "object", instance = instance })
					end
					mode = "object"
					tagMatchStart = hashPos
				end
			end

			local colonPos = if atPos or hashPos then nil else text:match(".*():")
			if colonPos then
				local typed = text:sub(colonPos + 1)
				if typed:match("^[%w_+-]*$") and EmojiData.isValidBoundary(text:sub(1, colonPos - 1)) then
					for _, entry in ipairs(EmojiData.search(typed, nil, Autocomplete.MAX_ITEMS)) do
						table.insert(items, { type = "emoji", name = entry.name, emoji = entry.emoji })
					end
					mode = "emoji"
					emojiMatchStart = colonPos
				end
			end

			if #items == 0 then
				argCommand, argIndex = typedCommandArgs(text)
			end
		end

		-- A bot option with choices: the choices that match what's typed
		local currentArg = argCommand and argCommand.args[argIndex]
		if currentArg and type(currentArg.choices) == "table" and #currentArg.choices > 0 then
			local partial = if string.match(text, "%s$") then "" else (string.match(text, "(%S+)$") or "")
			choiceMatchStart = #text - #partial + 1
			for _, choice in ipairs(currentArg.choices) do
				if string.sub(string.lower(choice.name), 1, #partial) == string.lower(partial) then
					table.insert(items, { type = "choice", choice = choice })
				end
			end
			if #items > 0 then
				mode = "choice"
				argCommand = nil
			end
		end

		if argCommand then
			mode = "args"
			for i, arg in ipairs(argCommand.args) do
				if i > Autocomplete.MAX_ITEMS then
					break
				end
				Autocomplete.createArgItem(i, arg, ctx.palette).Parent = frame
			end
			Autocomplete.setTitle(frame, Language.t("autocomplete.options", { command = argCommand.name }))
			Autocomplete.setHint(
				frame,
				Icons.escape(argCommand.usage or "") .. "  ·  " .. Icons.escape(argCommand.description or "")
			)
			frame.Visible = true
			Autocomplete.setSelected(frame, argIndex)
			return
		end
		renderAutocompleteItems()
	end

	textBox:GetPropertyChangedSignal("Text"):Connect(updateAutocomplete)

	-- Spelling suggestions when the cursor moves onto a word with a red line
	-- (not while typing, and never over other suggestions)
	local lastTextChange = 0
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		lastTextChange = os.clock()
	end)
	local function showSpellingSuggestions()
		if not Preferences.values.spellCheck or os.clock() - lastTextChange < 0.1 then
			return
		end
		if frame.Visible and mode ~= "spelling" then
			return
		end
		local word = spelling.wordAt(textBox.CursorPosition)
		if not word then
			if mode == "spelling" then
				mode = nil
				hide()
			end
			return
		end
		clearItems()
		items = {}
		selectedIndex = 1
		mode = "spelling"
		for _, suggestion in ipairs(SpellCheck.suggest(word.word, Autocomplete.MAX_ITEMS - 1)) do
			table.insert(items, { type = "spelling", word = word, suggestion = suggestion })
		end
		table.insert(items, { type = "addWord", word = word })
		renderAutocompleteItems()
	end
	textBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
		task.defer(showSpellingSuggestions)
	end)

	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			Animation.fadeIn(frame, "quick")
		end
	end)

	local self = {}
	self.hide = hide

	--[=[
		Sets fn() -> { command }, the commands offered while typing "/".
	]=]
	function self.setCommandProvider(fn)
		commandProvider = fn
	end

	function self.isVisible(): boolean
		return frame.Visible
	end

	--[=[
		Keeps the dropdown just above the composer.
	]=]
	function self.place(composerHeight: number)
		frame.Position = UDim2.new(0, 5, 1, -(composerHeight + 8))
	end

	function self.recolor()
		Autocomplete.recolor(frame, ctx.palette)
	end

	return self
end

return Suggestions
