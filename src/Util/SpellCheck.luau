--!strict
--[[
	SpellCheck

	English spell checking for the message box: which words are misspelled,
	and what they might have meant. The word list is Config/Dictionary
	(cspell's en_US, built by tools/make_dictionary.py), loaded the first
	time it's needed, a module per frame so Studio doesn't hitch.

	Not checked: code (`x`, ``` blocks), links, @mentions, #tags, :emoji:,
	/commands, identifiers (camelCase, snake_case, script.Parent, words with
	digits), ALL CAPS, single letters, and words next to non-English
	letters. Names of people here and words you add are fine too.

	Usage:
		SpellCheck.load()                              -- yields until the words are in
		SpellCheck.check("I recieve teh mail")         -- { { start = 3, finish = 9, word = "recieve" }, ... }
		SpellCheck.suggest("recieve")                  -- { "receive", ... }
		SpellCheck.addWords({ "Rojo", "builderman" })  -- known from now on
]]

local Links = require(script.Parent.Links)
local Mentions = require(script.Parent.Mentions)

export type Misspelling = { start: number, finish: number, word: string }

local SpellCheck = {}

local MAX_WORD = 24
local SUGGEST_BUDGET = 0.04 -- seconds for distance-2 suggestions
local LETTERS = "abcdefghijklmnopqrstuvwxyz"

-- Chat, Roblox and Studio words the dictionary doesn't know
local EXTRA = {
	"roblox",
	"robux",
	"luau",
	"lua",
	"rojo",
	"devforum",
	"plugin",
	"plugins",
	"workspace",
	"modulescript",
	"localscript",
	"serverscript",
	"remoteevent",
	"remotefunction",
	"bindable",
	"datastore",
	"datastores",
	"tween",
	"tweens",
	"tweened",
	"tweening",
	"raycast",
	"raycasts",
	"raycasting",
	"hitbox",
	"hitboxes",
	"npc",
	"npcs",
	"ui",
	"ux",
	"gui",
	"guis",
	"api",
	"apis",
	"url",
	"urls",
	"json",
	"png",
	"jpg",
	"gif",
	"gifs",
	"emoji",
	"emojis",
	"repo",
	"repos",
	"github",
	"discord",
	"youtube",
	"playtest",
	"playtesting",
	"ok",
	"okay",
	"lol",
	"lmao",
	"brb",
	"btw",
	"idk",
	"imo",
	"tbh",
	"omg",
	"pls",
	"plz",
	"thx",
	"ty",
	"np",
	"gg",
	"afk",
	"dm",
	"dms",
	"wip",
	"yeah",
	"yep",
	"nope",
	"hmm",
	"haha",
	"hahaha",
	"bruh",
	"uh",
	"um",
	"noob",
	"noobs",
	"lobby",
	"respawn",
	"respawning",
	"teleport",
	"teleporting",
	"dev",
	"devs",
}

local words: { [string]: boolean }? = nil -- the dictionary, once loaded
local extra: { [string]: boolean } = {} -- lowercase: EXTRA, names, added words
local loading = false
local readyCallbacks: { () -> () } = {}

for _, word in ipairs(EXTRA) do
	extra[word] = true
end

--[=[
	Whether the dictionary is loaded (until then every word counts as right).
]=]
function SpellCheck.isReady(): boolean
	return words ~= nil
end

--[=[
	Calls `callback` once the dictionary is loaded (now, if it is).
]=]
function SpellCheck.onReady(callback: () -> ())
	if words then
		callback()
	else
		table.insert(readyCallbacks, callback)
	end
end

--[=[
	Loads the dictionary (once). Yields a frame between its modules; other
	callers wait for the first one to finish.
]=]
function SpellCheck.load()
	if words then
		return
	end
	if loading then
		while not words do
			task.wait()
		end
		return
	end
	loading = true
	local folder = script.Parent.Parent.Config.Dictionary
	local modules = folder:GetChildren()
	table.sort(modules, function(a, b)
		return (tonumber(string.match(a.Name, "%d+")) or 0) < (tonumber(string.match(b.Name, "%d+")) or 0)
	end)
	local set: { [string]: boolean } = {}
	for _, module in ipairs(modules) do
		if module:IsA("ModuleScript") then
			-- Front-coded: a digit (letters shared with the word before) and the rest
			local previous = ""
			for line in string.gmatch((require :: any)(module), "[^\n]+") do
				local word = string.sub(previous, 1, string.byte(line, 1) - 48) .. string.sub(line, 2)
				set[word] = true
				previous = word
			end
			task.wait()
		end
	end
	words = set
	loading = false
	local callbacks = readyCallbacks
	readyCallbacks = {}
	for _, callback in ipairs(callbacks) do
		task.spawn(callback)
	end
end

--[=[
	Words that count as spelled right from now on (names, words added to
	the dictionary). Case doesn't matter.
]=]
function SpellCheck.addWords(list: { string })
	for _, word in ipairs(list) do
		if type(word) == "string" and word ~= "" then
			extra[string.lower(word)] = true
		end
	end
end

local function capitalize(word: string): string
	return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
end

-- How the dictionary spells a (lowercase) word: as is, or as a name
local function spellingOf(lower: string): string?
	local dictionary = words
	if not dictionary then
		return nil
	end
	if dictionary[lower] or extra[lower] then
		return lower
	end
	local name = capitalize(lower)
	if dictionary[name] then
		return name
	end
	return nil
end

--[=[
	Whether a word is spelled right (any case: "Hello", "hello", "amsterdam").
	Possessives count as their word ("dog's", "dogs'").
]=]
function SpellCheck.isCorrect(word: string): boolean
	local dictionary = words
	if not dictionary then
		return true
	end
	local lower = string.lower(word)
	if dictionary[word] or spellingOf(lower) then
		return true
	end
	local base = string.match(lower, "^(.+)'s$") or string.match(lower, "^(.+s)'$")
	return base ~= nil and spellingOf(base) ~= nil
end

-- Byte ranges that aren't prose: code, links, mentions, tags, emoji, a /command
local function skippedRanges(text: string): { { number } }
	local ranges = {}
	local function add(from: number, to: number)
		table.insert(ranges, { from, to })
	end
	-- ``` blocks (to the closing fence, or the end while one is being typed), then `code`
	local position = 1
	while true do
		local open = string.find(text, "```", position, true)
		if not open then
			break
		end
		local close = string.find(text, "```", open + 3, true)
		local finish = if close then close + 2 else #text
		add(open, finish)
		position = finish + 1
	end
	for from, to in string.gmatch(text, "()`[^`\n]*`?()") do
		add(from, to - 1)
	end
	for _, link in ipairs(Links.find(text)) do
		add(link.start, link.finish)
	end
	for _, mention in ipairs(Mentions.find(text)) do
		add(mention.start, mention.finish)
	end
	for from, to in string.gmatch(text, "()#%[[^%]\n]*%]?()") do
		add(from, to - 1)
	end
	for from, to in string.gmatch(text, "():[%w_+%-]+:()") do
		add(from, to - 1)
	end
	local command = string.match(text, "^/%S+()")
	if command then
		add(1, command - 1)
	end
	return ranges
end

local function inside(ranges: { { number } }, from: number, to: number): boolean
	for _, range in ipairs(ranges) do
		if from <= range[2] and to >= range[1] then
			return true
		end
	end
	return false
end

-- Part of an identifier or a non-English word: digits, _, non-ASCII, a.b, paths
local function joined(text: string, before: number, after: number): boolean
	local prev = string.sub(text, before, before)
	local nextChar = string.sub(text, after, after)
	if string.match(prev, "[%d_]") or string.match(nextChar, "[%d_]") then
		return true
	end
	if (string.byte(prev) or 0) >= 128 or (string.byte(nextChar) or 0) >= 128 then
		return true
	end
	if prev == "." and string.match(string.sub(text, before - 1, before - 1), "%w") then
		return true
	end
	if nextChar == "." and string.match(string.sub(text, after + 1, after + 1), "%a") then
		return true
	end
	return prev == "/" or prev == "\\" or nextChar == "/" or nextChar == "\\"
end

--[=[
	The misspelled words in `text`, in order. With `cursor` (a TextBox's
	CursorPosition), the word right before the cursor is skipped: it's still
	being typed. Nothing is found until the dictionary is loaded.
]=]
function SpellCheck.check(text: string, cursor: number?): { Misspelling }
	local found: { Misspelling } = {}
	if not words or text == "" then
		return found
	end
	local ranges = skippedRanges(text)
	for start, word in string.gmatch(text, "()(%a[%a']*)") do
		-- Quotes after a word aren't part of it
		local trimmed = string.match(word, "^(.-)'*$") or word
		local finish = start + #trimmed - 1
		if
			#trimmed >= 2
			and #trimmed <= MAX_WORD
			and not string.find(trimmed, "%u", 2) -- camelCase, ALL CAPS
			and not (cursor and cursor == finish + 1)
			and not inside(ranges, start, finish)
			and not joined(text, start - 1, start + #word)
			and not SpellCheck.isCorrect(trimmed)
		then
			table.insert(found, { start = start, finish = finish, word = trimmed })
		end
	end
	return found
end

-- Letters next to each other on a QWERTY keyboard (a slip of the finger)
local NEIGHBOURS: { [string]: string } = {}
for _, row in ipairs({ "qwertyuiop", "asdfghjkl", "zxcvbnm" }) do
	for i = 1, #row do
		local letter = string.sub(row, i, i)
		NEIGHBOURS[letter] = string.sub(row, math.max(1, i - 1), i - 1) .. string.sub(row, i + 1, i + 1)
	end
end

-- Every word one edit away, with how likely that typo is (lower: likelier):
-- swapped letters 0, a neighbouring key or a doubled letter 0.6, anything
-- else (a letter missing, extra or wrong) 1. `costs` keeps the lowest.
local function edits(word: string, base: number, costs: { [string]: number })
	local function add(candidate: string, cost: number)
		local old = costs[candidate]
		if not old or base + cost < old then
			costs[candidate] = base + cost
		end
	end
	local length = #word
	for i = 1, length do
		add(string.sub(word, 1, i - 1) .. string.sub(word, i + 1), 1)
	end
	for i = 1, length - 1 do
		add(
			string.sub(word, 1, i - 1)
				.. string.sub(word, i + 1, i + 1)
				.. string.sub(word, i, i)
				.. string.sub(word, i + 2),
			0
		)
	end
	for i = 1, length + 1 do
		local before, rest = string.sub(word, 1, i - 1), string.sub(word, i)
		local current = string.sub(word, i, i)
		local previous = string.sub(word, i - 1, i - 1)
		for c = 1, #LETTERS do
			local letter = string.sub(LETTERS, c, c)
			if i <= length and letter ~= current then
				local near = string.find(NEIGHBOURS[current] or "", letter, 1, true) ~= nil
				add(before .. letter .. string.sub(rest, 2), if near then 0.6 else 1)
			end
			add(before .. letter .. rest, if letter == previous or letter == current then 0.6 else 1)
		end
	end
end

--[=[
	Up to `max` (5) words the misspelled `word` might be, likeliest first,
	in its capitalisation.
]=]
function SpellCheck.suggest(word: string, max: number?): { string }
	local limit = max or 5
	local lower = string.lower(word)
	local costs: { [string]: number } = {}
	edits(lower, 0, costs)
	-- Two edits away too, while there's time (when one edit found too few)
	local scored: { { word: string, score: number } } = {}
	local function collect()
		table.clear(scored)
		for candidate, cost in pairs(costs) do
			local spelled = if candidate ~= lower then spellingOf(candidate) else nil
			if spelled then
				-- Names and chat slang are less likely than plain words; so is a
				-- different first letter
				local score = cost
				if spelled ~= candidate then
					score += 0.5
				elseif not (words :: any)[candidate] then
					score += 0.3
				end
				if string.sub(candidate, 1, 1) ~= string.sub(lower, 1, 1) then
					score += 0.5
				end
				table.insert(scored, { word = spelled, score = score })
			end
		end
	end
	collect()
	if #scored < limit then
		local deadline = os.clock() + SUGGEST_BUDGET
		local once = {}
		for candidate in pairs(costs) do
			table.insert(once, candidate)
		end
		for _, candidate in ipairs(once) do
			if os.clock() > deadline then
				break
			end
			edits(candidate, costs[candidate] + 1, costs)
		end
		collect()
	end
	table.sort(scored, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end
		return a.word < b.word
	end)
	local suggestions = {}
	local capital = string.match(word, "^%u") ~= nil
	for _, item in ipairs(scored) do
		if #suggestions >= limit then
			break
		end
		table.insert(suggestions, if capital then capitalize(item.word) else item.word)
	end
	return suggestions
end

return SpellCheck
