--!strict
--[[
	Mentions

	@mentions in message text: "@username" (a Roblox username: 3-20 letters,
	digits or underscores) or "@everyone". A mention starts the text or
	follows something that isn't part of a name, so "mail@site.com" isn't one.

	Usage:
		Mentions.find("hi @builderman")          -- { { start = 4, finish = 14, name = "builderman" } }
		Mentions.mentions(text, "builderman")    -- true: it mentions them (or @everyone)
		Mentions.typing("hello @bu")             -- 7, "bu": an @mention being typed at the end
]]

export type Mention = { start: number, finish: number, name: string }

local Mentions = {}

Mentions.EVERYONE = "everyone"

local function isNameChar(char: string): boolean
	return string.match(char, "^[%w_]$") ~= nil
end

local function isMention(name: string): boolean
	return string.lower(name) == Mentions.EVERYONE or (#name >= 3 and #name <= 20)
end

--[=[
	Every @mention in `text`, in order.
]=]
function Mentions.find(text: string): { Mention }
	local found = {}
	local position = 1
	while true do
		local start, finish, name = string.find(text, "@([%w_]+)", position)
		if not start then
			break
		end
		local before = if start > 1 then string.sub(text, start - 1, start - 1) else ""
		if (before == "" or not isNameChar(before)) and isMention(name) then
			table.insert(found, { start = start, finish = finish, name = name })
		end
		position = finish + 1
	end
	return found
end

--[=[
	Whether `text` mentions `username` (any case) or @everyone.
]=]
function Mentions.mentions(text: string?, username: string?): boolean
	if not text or text == "" then
		return false
	end
	local lowered = if username then string.lower(username) else nil
	for _, mention in ipairs(Mentions.find(text)) do
		local name = string.lower(mention.name)
		if name == Mentions.EVERYONE or name == lowered then
			return true
		end
	end
	return false
end

--[=[
	An @mention being typed at the end of `text`: where its "@" is and what
	follows it so far (possibly ""). nil when the text doesn't end in one.
]=]
function Mentions.typing(text: string): (number?, string?)
	local at, partial = string.match(text, "()@([%w_]*)$")
	if not at then
		return nil, nil
	end
	local before = if at > 1 then string.sub(text, at - 1, at - 1) else ""
	if before ~= "" and isNameChar(before) then
		return nil, nil
	end
	return at, partial
end

return Mentions
