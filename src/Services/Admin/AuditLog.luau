--!strict
--[[
	AuditLog

	Every moderation action, kept in the place (TeamChatData.AdminLog) so
	every moderator sees the same history in the admin dashboard: who did
	what to whom, when, and why. The newest 500 are kept.

	Each entry is a folder with attributes, so two moderators acting at the
	same moment don't overwrite each other.

	Usage:
		AuditLog.record("mute", { targetId = 156, targetName = "builderman", reason = "spam" })
		AuditLog.list({ query = "builder", action = "mute", limit = 50 })
		local stop = AuditLog.onChanged(function() ... end)
]]

local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local PlaceStorage = require(script.Parent.Parent.Parent.Core.PlaceStorage)
local TimeFormat = require(script.Parent.Parent.Parent.Util.TimeFormat)

export type Entry = {
	id: string,
	time: number,
	order: number, -- for sorting: milliseconds, then the order recorded
	action: string,
	actorId: number,
	actorName: string,
	targetId: number?,
	targetName: string?,
	reason: string?,
	detail: string?,
}

export type Info = { targetId: number?, targetName: string?, reason: string?, detail: string? }

export type Filter = { query: string?, action: string?, actorId: number?, targetId: number?, limit: number? }

local AuditLog = {}

AuditLog.FOLDER = "AdminLog"
AuditLog.MAX = 500

local function folder(): Folder
	return PlaceStorage.getFolder(AuditLog.FOLDER)
end

-- Sorting key: actions in the same second keep the order they happened in
local recorded = 0
local function orderOf(child: Instance): number
	return child:GetAttribute("Order") or (child:GetAttribute("Time") or 0) * 1e6
end

local function read(child: Instance): Entry
	return {
		id = child.Name,
		time = child:GetAttribute("Time") or 0,
		order = orderOf(child),
		action = child:GetAttribute("Action") or "?",
		actorId = child:GetAttribute("ActorId") or 0,
		actorName = child:GetAttribute("ActorName") or "?",
		targetId = child:GetAttribute("TargetId"),
		targetName = child:GetAttribute("TargetName"),
		reason = child:GetAttribute("Reason"),
		detail = child:GetAttribute("Detail"),
	}
end

--[=[
	Records an action by the current user.
]=]
function AuditLog.record(action: string, info: Info?)
	local entry = Instance.new("Folder")
	entry.Name = "log_" .. TimeFormat.generateId()
	recorded += 1
	entry:SetAttribute("Time", os.time())
	entry:SetAttribute("Order", DateTime.now().UnixTimestampMillis * 1000 + recorded % 1000)
	entry:SetAttribute("Action", action)
	entry:SetAttribute("ActorId", Identity.userId)
	entry:SetAttribute("ActorName", Identity.username)
	if info then
		entry:SetAttribute("TargetId", info.targetId)
		entry:SetAttribute("TargetName", info.targetName)
		entry:SetAttribute("Reason", if info.reason ~= "" then info.reason else nil)
		entry:SetAttribute("Detail", info.detail)
	end
	local log = folder()
	entry.Parent = log
	-- Keep the newest MAX
	local children = log:GetChildren()
	if #children > AuditLog.MAX then
		table.sort(children, function(a, b)
			return orderOf(a) < orderOf(b)
		end)
		for i = 1, #children - AuditLog.MAX do
			children[i]:Destroy()
		end
	end
end

--[=[
	Entries, newest first. Filter by text (`query`: names, reason, details),
	`action`, `actorId` or `targetId`; at most `limit` (all by default).
]=]
function AuditLog.list(filter: Filter?): { Entry }
	local options: Filter = filter or {}
	local query = string.lower(options.query or "")
	local entries = {}
	for _, child in ipairs(folder():GetChildren()) do
		local entry = read(child)
		local text = string.lower(table.concat({
			entry.actorName,
			entry.targetName or "",
			entry.reason or "",
			entry.detail or "",
			entry.action,
		}, " "))
		if
			(options.action == nil or entry.action == options.action)
			and (options.actorId == nil or entry.actorId == options.actorId)
			and (options.targetId == nil or entry.targetId == options.targetId)
			and (query == "" or string.find(text, query, 1, true) ~= nil)
		then
			table.insert(entries, entry)
		end
	end
	table.sort(entries, function(a, b)
		if a.order ~= b.order then
			return a.order > b.order
		end
		return a.id > b.id
	end)
	if options.limit and #entries > options.limit then
		local cut = {}
		table.move(entries, 1, options.limit, 1, cut)
		return cut
	end
	return entries
end

--[=[
	The kinds of action in the log (for filtering), sorted.
]=]
function AuditLog.actions(): { string }
	local seen, list = {}, {}
	for _, child in ipairs(folder():GetChildren()) do
		local action = child:GetAttribute("Action")
		if type(action) == "string" and not seen[action] then
			seen[action] = true
			table.insert(list, action)
		end
	end
	table.sort(list)
	return list
end

--[=[
	Calls `callback` when an entry is added or removed (here or by another
	moderator). Returns a function that stops listening.
]=]
function AuditLog.onChanged(callback: () -> ()): () -> ()
	local log = folder()
	local added = log.ChildAdded:Connect(callback)
	local removed = log.ChildRemoved:Connect(callback)
	return function()
		added:Disconnect()
		removed:Disconnect()
	end
end

return AuditLog
