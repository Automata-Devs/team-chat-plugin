--!strict
--[[
	Pins

	Pinned messages, like Discord: anyone in a conversation can pin a
	message so it's easy to find again (the pin button at the top of the
	chat lists them). A pin is saved on the message itself (Pinned,
	PinnedAt, PinnedBy, PinnedByName), so everyone sees it, it survives
	history backups, and it goes when the message is deleted.

	Usage:
		Pins.set(timestamp, true)            -- pin a message in the open conversation
		Pins.list(folder)                    -- the pinned messages, newest pin first
		Pins.isPinned(messageFolder)
]]

local ChatState = require(script.Parent.ChatState)
local MessageStore = require(script.Parent.MessageStore)

local Pins = {}

Pins.MAX = 50 -- per conversation, like Discord

function Pins.isPinned(message: Instance): boolean
	return message:GetAttribute("Pinned") == true
end

--[=[
	The pinned messages in a conversation folder (readEntry entries with
	pinnedAt, pinnedBy and pinnedByName), the newest pin first.
]=]
function Pins.list(folder: Instance?): { { [string]: any } }
	local pinned = {}
	for _, child in ipairs((folder or ChatState.getActiveFolder()):GetChildren()) do
		if Pins.isPinned(child) and child:GetAttribute("VisibleTo") == nil then
			local entry = MessageStore.readEntry(child)
			entry.pinnedAt = child:GetAttribute("PinnedAt") or 0
			entry.pinnedBy = child:GetAttribute("PinnedBy")
			entry.pinnedByName = child:GetAttribute("PinnedByName")
			table.insert(pinned, entry)
		end
	end
	table.sort(pinned, function(a, b)
		if a.pinnedAt ~= b.pinnedAt then
			return a.pinnedAt > b.pinnedAt
		end
		return a.timestamp > b.timestamp
	end)
	return pinned
end

--[=[
	Pins or unpins a message in the open conversation. Returns true when it
	changed, or false and why not: "signedOut", "notFound" (deleted, or an
	answer only one person sees) or "full" (Pins.MAX pinned already).
]=]
function Pins.set(timestamp: number, pinned: boolean): (boolean, string?)
	if ChatState.currentUserId <= 0 then
		return false, "signedOut"
	end
	local folder = ChatState.getActiveFolder()
	local target: Instance? = nil
	local count = 0
	for _, child in ipairs(folder:GetChildren()) do
		if Pins.isPinned(child) then
			count += 1
		end
		if child:GetAttribute("Timestamp") == timestamp and child:GetAttribute("VisibleTo") == nil then
			target = child
		end
	end
	if not target then
		return false, "notFound"
	end
	if Pins.isPinned(target) == pinned then
		return true
	end
	if pinned and count >= Pins.MAX then
		return false, "full"
	end
	if pinned then
		target:SetAttribute("PinnedAt", os.time())
		target:SetAttribute("PinnedBy", ChatState.currentUserId)
		target:SetAttribute("PinnedByName", ChatState.currentUsername)
		target:SetAttribute("Pinned", true)
	else
		target:SetAttribute("Pinned", nil)
		target:SetAttribute("PinnedAt", nil)
		target:SetAttribute("PinnedBy", nil)
		target:SetAttribute("PinnedByName", nil)
	end
	ChatState.saveHistory()
	return true
end

return Pins
