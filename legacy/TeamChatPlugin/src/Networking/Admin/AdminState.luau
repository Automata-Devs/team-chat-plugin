--!
-- AdminState
-- Shared state module for the admin subsystem.
-- Holds all in-memory caches (ranks, mutes, bans, blacklists, whitelists)
-- and provides persistence via plugin settings.
--!

local HttpService = game:GetService("HttpService")

local PluginConfig = require(script.Parent.Parent.Parent.Config.PluginConfig)

local AdminState = {}

-- Persistence keys
local SETTING_KEY = PluginConfig.SETTING_KEY_ADMIN

-- Shared state tables
AdminState.userRanks = {}        -- [userId] = rank number
AdminState.mutedUsers = {}       -- [userId] = true
AdminState.bannedUsers = {}      -- [userId] = { userId=, username=, reason= }
AdminState.blacklistedUsers = {} -- [userId] = { userId=, username=, reason= }
AdminState.whitelistEnabled = false
AdminState.whitelistedUsers = {} -- [userId] = { userId=, username= }
AdminState.warnedUsers = {}      -- [userId] = { { userId=, reason=, moderatorId=, moderatorName=, timestamp= } }
AdminState.slowmodeSeconds = 0   -- 0 = disabled

-- Plugin reference (set during init)
AdminState.pluginRef = nil
AdminState.currentUserId = 0
AdminState.currentUsername = "Unknown"

--!
-- Saves all admin state to plugin settings for persistence.
--!
function AdminState.save()
	if not AdminState.pluginRef then return end

	local state = {
		userRanks = AdminState.userRanks,
		mutedUsers = AdminState.mutedUsers,
		bannedUsers = AdminState.bannedUsers,
		blacklistedUsers = AdminState.blacklistedUsers,
		whitelistEnabled = AdminState.whitelistEnabled,
		whitelistedUsers = AdminState.whitelistedUsers,
		warnedUsers = AdminState.warnedUsers,
		slowmodeSeconds = AdminState.slowmodeSeconds,
	}

	local ok, json = pcall(function()
		return HttpService:JSONEncode(state)
	end)
	if ok and json then
		pcall(function()
			AdminState.pluginRef:SetSetting(SETTING_KEY, json)
		end)
	end
end

--!
-- Restores admin state from plugin settings.
--!
function AdminState.restore()
	if not AdminState.pluginRef then return end

	local ok, json = pcall(function()
		return AdminState.pluginRef:GetSetting(SETTING_KEY)
	end)
	if not ok or not json or json == "" then return end

	local okDecode, state = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not okDecode or not state then return end

	AdminState.userRanks = state.userRanks or {}
	AdminState.mutedUsers = state.mutedUsers or {}
	AdminState.bannedUsers = state.bannedUsers or {}
	AdminState.blacklistedUsers = state.blacklistedUsers or {}
	AdminState.whitelistEnabled = state.whitelistEnabled or false
	AdminState.whitelistedUsers = state.whitelistedUsers or {}
	AdminState.warnedUsers = state.warnedUsers or {}
	AdminState.slowmodeSeconds = state.slowmodeSeconds or 0
end

return AdminState