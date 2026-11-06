--!strict
--[[
	Reactions

	Emoji reactions on messages, like Discord: anyone in a conversation can
	react to a message with an emoji, and click a reaction to add or remove
	their own. Reactions are saved on the message itself (the Reactions
	attribute, JSON), so everyone sees them, they survive history backups,
	and they go when the message is deleted.

	Saved as a list in the order each emoji was first used:
		[{ "e": "👍", "u": [156, 1], "n": ["builderman", "Roblox"] }, ...]

	Usage:
		Reactions.toggle(messageName, "👍") -- in the open conversation (or a timestamp)
		Reactions.read(messageFolder)       -- { { emoji, count, users, names, mine } }
]]

local HttpService = game:GetService("HttpService")

local ChatState = require(script.Parent.ChatState)

export type Reaction = {
	emoji: string,
	count: number,
	users: { number },
	names: { string },
	mine: boolean,
}

type Saved = { e: string, u: { number }, n: { string } }

local Reactions = {}

Reactions.ATTRIBUTE = "Reactions"
Reactions.MAX_KINDS = 20 -- different emoji on one message, like Discord
Reactions.MAX_EMOJI_LENGTH = 32 -- bytes (an emoji with modifiers, never text)

local function decode(message: Instance): { Saved }
	local raw = message:GetAttribute(Reactions.ATTRIBUTE)
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(value) ~= "table" then
		return {}
	end
	local list = {}
	for _, item in ipairs(value) do
		if type(item) == "table" and type(item.e) == "string" and type(item.u) == "table" then
			local users, names = {}, {}
			for index, userId in ipairs(item.u) do
				if type(userId) == "number" then
					table.insert(users, userId)
					local name = if type(item.n) == "table" then item.n[index] else nil
					table.insert(names, if type(name) == "string" then name else "?")
				end
			end
			if #users > 0 then
				table.insert(list, { e = item.e, u = users, n = names })
			end
		end
	end
	return list
end

--[=[
	A message's reactions, in the order each emoji was first used. `mine` is
	true when the current user is one of the people who reacted.
]=]
function Reactions.read(message: Instance): { Reaction }
	local me = ChatState.currentUserId
	local result = {}
	for _, saved in ipairs(decode(message)) do
		table.insert(result, {
			emoji = saved.e,
			count = #saved.u,
			users = saved.u,
			names = saved.n,
			mine = me > 0 and table.find(saved.u, me) ~= nil,
		})
	end
	return result
end

--[=[
	True when `message` has any reactions.
]=]
function Reactions.has(message: Instance): boolean
	return #decode(message) > 0
end

--[=[
	Adds the current user's `emoji` to a message in the open conversation
	(`target`: the message's name, or its timestamp), or removes it when
	they had already reacted with it. Returns true (and
	whether it's now added) when it changed, or false and why not:
	"signedOut", "invalid", "notFound" (deleted, or an answer only one
	person sees) or "full" (Reactions.MAX_KINDS different emoji already).
]=]
function Reactions.toggle(target: string | number, emoji: string): (boolean, string? | boolean?)
	local me = ChatState.currentUserId
	if me <= 0 then
		return false, "signedOut"
	end
	if type(emoji) ~= "string" or emoji == "" or #emoji > Reactions.MAX_EMOJI_LENGTH or emoji:find("[%w%s]") then
		return false, "invalid"
	end
	local message: Instance? = nil
	for _, child in ipairs(ChatState.getActiveFolder():GetChildren()) do
		local matches = if type(target) == "string"
			then child.Name == target
			else child:GetAttribute("Timestamp") == target
		if matches and child:GetAttribute("VisibleTo") == nil then
			message = child
		end
	end
	if not message then
		return false, "notFound"
	end

	local list = decode(message)
	local entry: Saved? = nil
	for _, saved in ipairs(list) do
		if saved.e == emoji then
			entry = saved
		end
	end
	local added: boolean
	if entry then
		local index = table.find(entry.u, me)
		if index then
			table.remove(entry.u, index)
			table.remove(entry.n, index)
			added = false
		else
			table.insert(entry.u, me)
			table.insert(entry.n, ChatState.currentUsername)
			added = true
		end
	else
		if #list >= Reactions.MAX_KINDS then
			return false, "full"
		end
		table.insert(list, { e = emoji, u = { me }, n = { ChatState.currentUsername } })
		added = true
	end

	-- Emoji nobody reacts with any more go
	local kept = {}
	for _, saved in ipairs(list) do
		if #saved.u > 0 then
			table.insert(kept, saved)
		end
	end
	message:SetAttribute(Reactions.ATTRIBUTE, if #kept > 0 then HttpService:JSONEncode(kept) else nil)
	ChatState.saveHistory()
	return true, added
end

return Reactions
