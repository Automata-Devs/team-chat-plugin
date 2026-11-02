--!
-- AdminNetwork (Facade)
-- Public API for the admin subsystem. Delegates to focused sub-modules:
--   Admin/RankManager       – ranks, user identity, permissions
--   Admin/ModerationManager – mutes, bans, kicks, blacklists, whitelists
--   Admin/UserResolver       – username-to-userId resolution
--   Admin/AdminState         – shared state and persistence
--!

local allowedUsers = require(script.Parent.Parent.Config.AllowedUsers)
local Constants = require(script.Parent.Parent.Config.Constants)

local AdminState = require(script.AdminState)
local RankManager = require(script.Ranks)
local ModerationManager = require(script.Moderation)
local UserResolver = require(script.UserResolver)

local AdminNetwork = {}

-- Re-export rank constants
AdminNetwork.RANK_USER = RankManager.RANK_USER
AdminNetwork.RANK_MODERATOR = RankManager.RANK_MODERATOR
AdminNetwork.RANK_ADMIN = RankManager.RANK_ADMIN
AdminNetwork.RANK_OWNER = RankManager.RANK_OWNER

--!
-- Initializes the admin system: restores state, assigns default ranks
-- to allowed users, and grants Owner rank to the current user.
--!
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
end

-- ── Rank & Identity (RankManager) ──

AdminNetwork.getRank = RankManager.getRank
AdminNetwork.getRankName = RankManager.getRankName
AdminNetwork.setRank = RankManager.setRank
AdminNetwork.getMyRank = RankManager.getMyRank
AdminNetwork.hasRank = RankManager.hasRank
AdminNetwork.getUserId = RankManager.getUserId
AdminNetwork.getUsername = RankManager.getUsername
AdminNetwork.getUsernameByUserId = RankManager.getUsernameByUserId

-- ── Moderation (ModerationManager) ──

AdminNetwork.canUserSend = ModerationManager.canUserSend

-- Mute
AdminNetwork.mute = ModerationManager.mute
AdminNetwork.unmute = ModerationManager.unmute
AdminNetwork.isMuted = ModerationManager.isMuted
AdminNetwork.getMutedUsers = ModerationManager.getMutedUsers

-- Ban
AdminNetwork.ban = ModerationManager.ban
AdminNetwork.unban = ModerationManager.unban
AdminNetwork.isBanned = ModerationManager.isBanned
AdminNetwork.getBannedUsers = ModerationManager.getBannedUsers

-- Kick
AdminNetwork.kick = ModerationManager.kick

-- Warnings
AdminNetwork.warn = ModerationManager.warn
AdminNetwork.getWarnings = ModerationManager.getWarnings

-- Slowmode
AdminNetwork.setSlowmode = ModerationManager.setSlowmode
AdminNetwork.getSlowmode = ModerationManager.getSlowmode

-- Purge
AdminNetwork.purge = ModerationManager.purge

-- Blacklist
AdminNetwork.blacklist = ModerationManager.blacklist
AdminNetwork.unblacklist = ModerationManager.unblacklist
AdminNetwork.isBlacklisted = ModerationManager.isBlacklisted
AdminNetwork.getBlacklistedUsers = ModerationManager.getBlacklistedUsers

-- Whitelist
AdminNetwork.whitelist = ModerationManager.whitelist
AdminNetwork.unwhitelist = ModerationManager.unwhitelist
AdminNetwork.isWhitelisted = ModerationManager.isWhitelisted
AdminNetwork.toggleWhitelist = ModerationManager.toggleWhitelist
AdminNetwork.isWhitelistEnabled = ModerationManager.isWhitelistEnabled
AdminNetwork.getWhitelistedUsers = ModerationManager.getWhitelistedUsers

-- ── User Resolution (UserResolver) ──

AdminNetwork.resolveUserId = UserResolver.resolveUserId

-- ── Admin Events ──

local adminEventCallbacks = {}

function AdminNetwork.onAdminEvent(callback: (string, table) -> ())
	table.insert(adminEventCallbacks, callback)
end

function AdminNetwork._fireEvent(eventType: string, data: table)
	for _, cb in ipairs(adminEventCallbacks) do
		task.spawn(cb, eventType, data)
	end
end

return AdminNetwork
