--!strict
--[[
	AdminState

	In-memory admin data (ranks, mutes, bans, black/whitelists, warnings,
	slowmode) shared by Ranks and Moderation, saved per user in plugin settings.

	Usage:
		AdminState.restore()             -- once, in Admin.init
		AdminState.userRanks[userId] = 2
		AdminState.save()
]]

local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)

local AdminState = {}

-- Shared state tables, all keyed by userId (number)
AdminState.userRanks = {} :: { [number]: number }
AdminState.mutedUsers = {} :: { [number]: any } -- { userId, username, reason, expiry? }
AdminState.bannedUsers = {} :: { [number]: any } -- { userId, username, reason }
AdminState.blacklistedUsers = {} :: { [number]: any } -- { userId, username, reason }
AdminState.whitelistEnabled = false
AdminState.whitelistedUsers = {} :: { [number]: any } -- { userId, username }
AdminState.warnedUsers = {} :: { [number]: { any } } -- list of { userId, reason, moderatorId, moderatorName, timestamp }
AdminState.slowmodeSeconds = 0 -- 0 = disabled

-- Current user (copied from Core/Identity by Ranks.resolveCurrentUser)
AdminState.currentUserId = 0
AdminState.currentUsername = "Unknown"

-- JSON turns numeric keys into strings; turn them back so lookups by userId work.
local function byUserId(saved: any): { [number]: any }
	local result = {}
	if type(saved) == "table" then
		for key, value in pairs(saved) do
			local userId = tonumber(key)
			if userId then
				result[userId] = value
			end
		end
	end
	return result
end

--[=[
	Saves all admin state to plugin settings.
]=]
function AdminState.save()
	Settings.setJson(Constants.SETTING_KEY_ADMIN, {
		userRanks = AdminState.userRanks,
		mutedUsers = AdminState.mutedUsers,
		bannedUsers = AdminState.bannedUsers,
		blacklistedUsers = AdminState.blacklistedUsers,
		whitelistEnabled = AdminState.whitelistEnabled,
		whitelistedUsers = AdminState.whitelistedUsers,
		warnedUsers = AdminState.warnedUsers,
		slowmodeSeconds = AdminState.slowmodeSeconds,
	})
end

--[=[
	Restores admin state from plugin settings (keeps the defaults when nothing
	is saved).
]=]
function AdminState.restore()
	local state = Settings.getJson(Constants.SETTING_KEY_ADMIN)
	if type(state) ~= "table" then
		return
	end
	AdminState.userRanks = byUserId(state.userRanks)
	AdminState.mutedUsers = byUserId(state.mutedUsers)
	AdminState.bannedUsers = byUserId(state.bannedUsers)
	AdminState.blacklistedUsers = byUserId(state.blacklistedUsers)
	AdminState.whitelistEnabled = state.whitelistEnabled == true
	AdminState.whitelistedUsers = byUserId(state.whitelistedUsers)
	AdminState.warnedUsers = byUserId(state.warnedUsers)
	AdminState.slowmodeSeconds = tonumber(state.slowmodeSeconds) or 0
end

return AdminState
