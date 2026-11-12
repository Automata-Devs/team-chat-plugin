--[[
	Admin

	The admin system's public API, over these internal sub-modules:
	  Ranks        ranks, the signed-in user, permissions
	  Moderation   mutes, bans, kicks, blacklists, whitelists
	  UserResolver usernames to user ids
	  AdminState   shared state and persistence
	  AuditLog     every moderation action, kept in the place
	  ChatRules    blocked words and automatic backups
	Every moderation action through this facade is written to the audit log
	and announced to onAdminEvent listeners (the admin dashboard).
]]

local Players = game:GetService("Players")

local allowedUsers = require(script.Parent.Parent.Config.AllowedUsers)
local Constants = require(script.Parent.Parent.Config.Constants)

local AdminState = require(script.AdminState)
local RankManager = require(script.Ranks)
local ModerationManager = require(script.Moderation)
local UserResolver = require(script.UserResolver)
local AuditLog = require(script.AuditLog)
local ChatRules = require(script.ChatRules)

local AdminNetwork = {}

-- Re-export rank constants
AdminNetwork.RANK_USER = RankManager.RANK_USER
AdminNetwork.RANK_MODERATOR = RankManager.RANK_MODERATOR
AdminNetwork.RANK_ADMIN = RankManager.RANK_ADMIN
AdminNetwork.RANK_OWNER = RankManager.RANK_OWNER

--[=[
	Initializes the admin system: restores state, assigns default ranks
	to allowed users, and grants Owner rank to the current user.
]=]
function AdminNetwork.init()
	RankManager.resolveCurrentUser()
	AdminState.restore()

	-- Users listed in Config/AllowedUsers ({ [userId] = "RankName" }) get at
	-- least that rank (Admin when the name isn't a known rank).
	for userId, rankName in pairs(allowedUsers.USER_IDS or {}) do
		local rank = RankManager.RANK_ADMIN
		for value, name in pairs(Constants.RANK_NAMES) do
			if name == rankName or value == rankName then
				rank = value
			end
		end
		if type(userId) == "number" and (AdminState.userRanks[userId] or 0) < rank then
			AdminState.userRanks[userId] = rank
		end
	end

	-- The current user gets Owner rank if not already set
	if
		AdminState.currentUserId > 0
		and (
			AdminState.userRanks[AdminState.currentUserId] == nil
			or AdminState.userRanks[AdminState.currentUserId] < RankManager.RANK_OWNER
		)
	then
		AdminState.userRanks[AdminState.currentUserId] = RankManager.RANK_OWNER
	end

	AdminState.save()
	ChatRules.start()
end

AdminNetwork.AuditLog = AuditLog
AdminNetwork.ChatRules = ChatRules

-- Admin Events
local adminEventCallbacks: { (string, { [string]: any }) -> () } = {}

--[=[
	Calls `callback(action, info)` after every moderation action. Returns a
	function that stops listening.
]=]
function AdminNetwork.onAdminEvent(callback: (string, { [string]: any }) -> ()): () -> ()
	table.insert(adminEventCallbacks, callback)
	return function()
		local index = table.find(adminEventCallbacks, callback)
		if index then
			table.remove(adminEventCallbacks, index)
		end
	end
end

function AdminNetwork._fireEvent(eventType: string, data: { [string]: any })
	for _, callback in ipairs(adminEventCallbacks) do
		task.spawn(callback, eventType, data)
	end
end

-- A name for a user without waiting on the web: someone here, or from the lists
local function knownName(userId: number): string?
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.Name
	end
	for _, list in ipairs({
		AdminState.mutedUsers,
		AdminState.bannedUsers,
		AdminState.blacklistedUsers,
		AdminState.whitelistedUsers,
	}) do
		local entry = list[userId]
		if entry and entry.username and entry.username ~= "Unknown" then
			return entry.username
		end
	end
	return nil
end

-- Wraps a moderation function: `describe` says what it does (asked before it
-- runs, while names are still in the lists), then it's logged and announced
local function logged(action: string, fn: (...any) -> ...any, describe: (...any) -> AuditLog.Info): (...any) -> ...any
	return function(...: any)
		local info = describe(...)
		local results = table.pack(fn(...))
		AuditLog.record(action, info)
		AdminNetwork._fireEvent(action, info :: any)
		return table.unpack(results, 1, results.n)
	end
end

local function forUser(userId: number, username: string?, reason: string?): AuditLog.Info
	return {
		targetId = userId,
		targetName = if username and username ~= "Unknown" then username else knownName(userId),
		reason = reason,
	}
end

-- Rank & Identity
AdminNetwork.getRank = RankManager.getRank
AdminNetwork.getRankName = RankManager.getRankName
AdminNetwork.setRank = logged("setRank", RankManager.setRank, function(userId: number, rank: number)
	local info = forUser(userId)
	info.detail = RankManager.getRankName(rank)
	return info
end)
AdminNetwork.getMyRank = RankManager.getMyRank
AdminNetwork.hasRank = RankManager.hasRank
AdminNetwork.getUserId = RankManager.getUserId
AdminNetwork.getUsername = RankManager.getUsername
AdminNetwork.getUsernameByUserId = RankManager.getUsernameByUserId

--[=[
	Everyone with a rank above User: { { userId, rank } }, highest rank first.
]=]
function AdminNetwork.getRankedUsers(): { { userId: number, rank: number } }
	local list = {}
	for userId, rank in pairs(AdminState.userRanks) do
		if rank > 0 then
			table.insert(list, { userId = userId, rank = rank })
		end
	end
	table.sort(list, function(a, b)
		return if a.rank ~= b.rank then a.rank > b.rank else a.userId < b.userId
	end)
	return list
end

-- Moderation
AdminNetwork.canUserSend = ModerationManager.canUserSend

-- Mute
AdminNetwork.mute = logged(
	"mute",
	ModerationManager.mute,
	function(userId: number, username: string?, reason: string?, expiry: number?)
		local info = forUser(userId, username, reason)
		info.detail = if expiry then os.date("until %d/%m %H:%M", expiry) else nil
		return info
	end
)
AdminNetwork.unmute = logged("unmute", ModerationManager.unmute, function(userId: number)
	return forUser(userId)
end)
AdminNetwork.isMuted = ModerationManager.isMuted
AdminNetwork.getMutedUsers = ModerationManager.getMutedUsers

-- Ban
AdminNetwork.ban = logged("ban", ModerationManager.ban, forUser)
AdminNetwork.unban = logged("unban", ModerationManager.unban, function(userId: number)
	return forUser(userId)
end)
AdminNetwork.isBanned = ModerationManager.isBanned
AdminNetwork.getBannedUsers = ModerationManager.getBannedUsers

-- Kick
AdminNetwork.kick = logged("kick", ModerationManager.kick, forUser)

-- Warnings
AdminNetwork.warn = logged(
	"warn",
	ModerationManager.warn,
	function(userId: number, _moderatorId: number, reason: string, _moderatorName: string?)
		return forUser(userId, nil, reason)
	end
)
AdminNetwork.getWarnings = ModerationManager.getWarnings

-- Slowmode
AdminNetwork.setSlowmode = logged("slowmode", ModerationManager.setSlowmode, function(seconds: number)
	return { detail = if seconds > 0 then seconds .. "s" else "off" }
end)
AdminNetwork.getSlowmode = ModerationManager.getSlowmode

-- Purge
AdminNetwork.purge = logged("purge", ModerationManager.purge, function(amount: number, userId: number?)
	local info: AuditLog.Info = if userId then forUser(userId) else {}
	info.detail = tostring(amount)
	return info
end)

-- Blacklist
AdminNetwork.blacklist = logged("blacklist", ModerationManager.blacklist, forUser)
AdminNetwork.unblacklist = logged("unblacklist", ModerationManager.unblacklist, function(userId: number)
	return forUser(userId)
end)
AdminNetwork.isBlacklisted = ModerationManager.isBlacklisted
AdminNetwork.getBlacklistedUsers = ModerationManager.getBlacklistedUsers

-- Whitelist
AdminNetwork.whitelist = logged("whitelist", ModerationManager.whitelist, function(userId: number, username: string?)
	return forUser(userId, username)
end)
AdminNetwork.unwhitelist = logged("unwhitelist", ModerationManager.unwhitelist, function(userId: number)
	return forUser(userId)
end)
AdminNetwork.isWhitelisted = ModerationManager.isWhitelisted
AdminNetwork.toggleWhitelist = logged("whitelistMode", ModerationManager.toggleWhitelist, function()
	return { detail = if ModerationManager.isWhitelistEnabled() then "off" else "on" }
end)
AdminNetwork.isWhitelistEnabled = ModerationManager.isWhitelistEnabled
AdminNetwork.getWhitelistedUsers = ModerationManager.getWhitelistedUsers

-- User Resolution
AdminNetwork.resolveUserId = UserResolver.resolveUserId

return AdminNetwork
