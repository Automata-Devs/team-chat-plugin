--!strict
--[[
	Stats

	Numbers about the place's chat for the admin dashboard: messages per day
	and per hour, the most active people, DMs, bot messages, files and
	polls, and per person their message count and last message. Counts only
	(DMs are counted, never read out). Also turns the team chat into a text
	transcript for exporting.

	Usage:
		local stats = Stats.collect(7)       -- the last 7 days
		stats.perDay[7].count                -- today
		stats.users[156].count
		local text = Stats.transcript()
		Stats.saveScript(text)               -- a ModuleScript in ServerStorage.TeamChatExports
]]

local ServerStorage = game:GetService("ServerStorage")

local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local PlaceStorage = require(script.Parent.Parent.Parent.Core.PlaceStorage)
local ChatState = require(script.Parent.ChatState)

export type Day = { label: string, start: number, count: number }
export type Person = { userId: number, name: string, count: number, last: number }

export type Summary = {
	days: number,
	total: number, -- every message, all time
	recent: number, -- in the period
	perDay: { Day }, -- oldest first; the last is today
	byHour: { number }, -- [1] = 00:00-01:00 ... [24] = 23:00-24:00, in the period
	top: { Person }, -- most messages in the period, at most 5
	dmConversations: number,
	dmMessages: number,
	botMessages: number,
	files: number,
	polls: number,
	users: { [number]: Person }, -- everyone who wrote, all time
}

local Stats = {}

Stats.EXPORT_FOLDER = "TeamChatExports"
local DAY = 86400

-- Every message in the place: the team chat, then each DM conversation
local function eachMessage(callback: (message: Instance, dm: boolean) -> ())
	for _, message in ipairs(ChatState.getFolder():GetChildren()) do
		callback(message, false)
	end
	for _, conversation in ipairs(PlaceStorage.getFolder(Constants.DM_FOLDER_NAME):GetChildren()) do
		for _, message in ipairs(conversation:GetChildren()) do
			callback(message, true)
		end
	end
end

local function dayStart(time: number): number
	local date = os.date("*t", time) :: any
	return os.time({ year = date.year, month = date.month, day = date.day, hour = 0, min = 0, sec = 0 })
end

--[=[
	The chat's numbers for the last `days` days (7 by default), up to `now`.
]=]
function Stats.collect(days: number?, now: number?): Summary
	local period = days or 7
	local time = now or os.time()
	local today = dayStart(time)
	local perDay: { Day } = {}
	for i = period - 1, 0, -1 do
		-- (an hour into the day, so daylight saving can't skip one)
		local start = dayStart(today - i * DAY + 3600)
		table.insert(perDay, { label = os.date("%d/%m", start), start = start, count = 0 })
	end
	local since = perDay[1].start
	local byHour = table.create(24, 0)
	local summary: Summary = {
		days = period,
		total = 0,
		recent = 0,
		perDay = perDay,
		byHour = byHour,
		top = {},
		dmConversations = 0,
		dmMessages = 0,
		botMessages = 0,
		files = 0,
		polls = 0,
		users = {},
	}
	local recentBy: { [number]: Person } = {}
	local conversations: { [Instance]: boolean } = {}

	eachMessage(function(message, dm)
		local timestamp = message:GetAttribute("Timestamp")
		if type(timestamp) ~= "number" or message:GetAttribute("VisibleTo") ~= nil then
			return
		end
		local senderId = message:GetAttribute("SenderId") or 0
		local sender = message:GetAttribute("Sender") or "?"
		local isBot = sender == "System" or message:GetAttribute("BotId") ~= nil
		summary.total += 1
		if not isBot and senderId > 0 then
			local person = summary.users[senderId]
			if not person then
				person = { userId = senderId, name = sender, count = 0, last = 0 }
				summary.users[senderId] = person
			end
			person.count += 1
			if timestamp > person.last then
				person.last = timestamp
				person.name = sender
			end
		end
		if timestamp < since or timestamp > time then
			return
		end
		summary.recent += 1
		for _, day in ipairs(perDay) do
			if timestamp >= day.start and timestamp < day.start + DAY then
				day.count += 1
				break
			end
		end
		local hour = (os.date("*t", timestamp) :: any).hour
		byHour[hour + 1] += 1
		if dm then
			summary.dmMessages += 1
			conversations[message.Parent :: Instance] = true
		end
		if isBot then
			summary.botMessages += 1
		elseif senderId > 0 then
			local person = recentBy[senderId]
			if not person then
				person = { userId = senderId, name = sender, count = 0, last = 0 }
				recentBy[senderId] = person
			end
			person.count += 1
			person.last = math.max(person.last, timestamp)
		end
		local kind = message:GetAttribute("MessageType")
		if kind == ChatState.MESSAGE_TYPE_FILE then
			summary.files += 1
		elseif kind == ChatState.MESSAGE_TYPE_POLL then
			summary.polls += 1
		end
	end)

	for _ in pairs(conversations) do
		summary.dmConversations += 1
	end
	local top = {}
	for _, person in pairs(recentBy) do
		table.insert(top, person)
	end
	table.sort(top, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return string.lower(a.name) < string.lower(b.name)
	end)
	for i = 1, math.min(5, #top) do
		table.insert(summary.top, top[i])
	end
	return summary
end

--[=[
	The team chat as text, oldest first: "[05/11/2026 17:20] builderman: hello".
]=]
function Stats.transcript(): string
	local messages = ChatState.getFolder():GetChildren()
	table.sort(messages, function(a, b)
		return (a:GetAttribute("Timestamp") or 0) < (b:GetAttribute("Timestamp") or 0)
	end)
	local lines = {}
	for _, message in ipairs(messages) do
		if message:GetAttribute("VisibleTo") == nil then
			local sender = message:GetAttribute("Sender") or "?"
			if sender == "System" then
				sender = Constants.PLUGIN_TITLE
			end
			local content = message:GetAttribute("Content") or ""
			local kind = message:GetAttribute("MessageType")
			if kind == ChatState.MESSAGE_TYPE_POLL then
				content = "[poll] " .. tostring(message:GetAttribute("Question") or "")
			elseif kind == ChatState.MESSAGE_TYPE_FILE then
				content = "[file " .. tostring(message:GetAttribute("FileName") or "") .. "] " .. content
			elseif message:GetAttribute("ImageUrl") then
				content = "[image] " .. content
			end
			table.insert(
				lines,
				string.format(
					"[%s] %s: %s",
					os.date("%d/%m/%Y %H:%M", message:GetAttribute("Timestamp") or 0),
					sender,
					content
				)
			)
		end
	end
	return table.concat(lines, "\n")
end

--[=[
	Saves text as a ModuleScript in ServerStorage.TeamChatExports (inside a
	comment, so it never runs) and returns it, to open in the script editor.
]=]
function Stats.saveScript(text: string): ModuleScript
	local folder = ServerStorage:FindFirstChild(Stats.EXPORT_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Stats.EXPORT_FOLDER
		folder.Parent = ServerStorage
	end
	local module = Instance.new("ModuleScript")
	module.Name = "Chat " .. os.date("%Y-%m-%d %H-%M")
	-- A long comment can't contain its own closing brackets
	local body = string.gsub(text, "%]%]", "] ]")
	module.Source = "--[[\n" .. body .. "\n]]\n\nreturn nil\n"
	module.Parent = folder
	return module
end

return Stats
