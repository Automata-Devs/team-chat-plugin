--!strict
--[[
	ChatRules

	Place-wide chat rules set in the admin dashboard, kept in the place
	(TeamChatData.ChatRules) so they apply to everyone:
	  - blocked words: a message with one isn't sent (moderators and up are
	    exempt), like Discord's AutoMod;
	  - automatic backups: a chat backup (Services/Chat/VersionHistory)
	    every few hours, made by whichever collaborator's plugin notices
	    first.

	Usage:
		ChatRules.addBlockedWord("spam")
		ChatRules.findBlocked("no spam please")   -- "spam"
		ChatRules.setAutoBackupHours(6)
		ChatRules.start()                         -- once, in Admin.init
]]

local HttpService = game:GetService("HttpService")

local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local PlaceStorage = require(script.Parent.Parent.Parent.Core.PlaceStorage)
local VersionHistory = require(script.Parent.Parent.Chat.VersionHistory)
local AuditLog = require(script.Parent.AuditLog)

local ChatRules = {}

ChatRules.FOLDER = "ChatRules"
ChatRules.MAX_WORD = 40
ChatRules.CHECK_EVERY = 60 -- seconds between "is a backup due?" checks

local started = false

local function folder(): Folder
	return PlaceStorage.getFolder(ChatRules.FOLDER)
end

--[=[
	The blocked words and phrases (lowercase), sorted.
]=]
function ChatRules.getBlockedWords(): { string }
	local ok, words = pcall(HttpService.JSONDecode, HttpService, folder():GetAttribute("BlockedWords") or "[]")
	if not ok or type(words) ~= "table" then
		return {}
	end
	local list = {}
	for _, word in ipairs(words) do
		if type(word) == "string" and word ~= "" then
			table.insert(list, word)
		end
	end
	table.sort(list)
	return list
end

local function save(words: { string })
	table.sort(words)
	folder():SetAttribute("BlockedWords", HttpService:JSONEncode(words))
end

--[=[
	Blocks a word or phrase. Returns false when it's empty, too long or
	already blocked.
]=]
function ChatRules.addBlockedWord(word: string): boolean
	local cleaned = string.lower(string.match(word, "^%s*(.-)%s*$") or "")
	if cleaned == "" or #cleaned > ChatRules.MAX_WORD then
		return false
	end
	local words = ChatRules.getBlockedWords()
	if table.find(words, cleaned) then
		return false
	end
	table.insert(words, cleaned)
	save(words)
	AuditLog.record("blockWord", { detail = cleaned })
	return true
end

function ChatRules.removeBlockedWord(word: string): boolean
	local words = ChatRules.getBlockedWords()
	local index = table.find(words, string.lower(word))
	if not index then
		return false
	end
	table.remove(words, index)
	save(words)
	AuditLog.record("unblockWord", { detail = string.lower(word) })
	return true
end

-- A blocked word as a pattern: the whole word (any case), not part of another
local function patternOf(word: string): string
	local escaped = string.gsub(word, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	return "%f[%w]" .. escaped .. "%f[%W]"
end

--[=[
	The first blocked word in `text` (as a whole word, any case), or nil.
]=]
function ChatRules.findBlocked(text: string): string?
	local lowered = string.lower(text)
	for _, word in ipairs(ChatRules.getBlockedWords()) do
		if string.find(lowered, patternOf(word)) then
			return word
		end
	end
	return nil
end

--[=[
	How often automatic backups are made, in hours (0: never).
]=]
function ChatRules.getAutoBackupHours(): number
	return tonumber(folder():GetAttribute("AutoBackupHours")) or 0
end

function ChatRules.setAutoBackupHours(hours: number)
	folder():SetAttribute("AutoBackupHours", hours)
	AuditLog.record("autoBackups", { detail = if hours > 0 then hours .. "h" else "off" })
end

--[=[
	When the last automatic backup was made (os.time), or nil.
]=]
function ChatRules.lastAutoBackup(): number?
	return folder():GetAttribute("LastAutoBackup")
end

--[=[
	Makes an automatic backup when one is due. Returns true when it made one.
]=]
function ChatRules.backupIfDue(now: number?): boolean
	local hours = ChatRules.getAutoBackupHours()
	if hours <= 0 then
		return false
	end
	local time = now or os.time()
	local last = ChatRules.lastAutoBackup() or 0
	if time - last < hours * 3600 then
		return false
	end
	-- Claim it first, so other collaborators' plugins don't make one too
	folder():SetAttribute("LastAutoBackup", time)
	return VersionHistory.create("Auto backup") ~= nil
end

--[=[
	Checks for due automatic backups every minute while the plugin runs.
]=]
function ChatRules.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while Lifetime.alive do
			task.wait(ChatRules.CHECK_EVERY)
			pcall(ChatRules.backupIfDue)
		end
	end)
end

return ChatRules
