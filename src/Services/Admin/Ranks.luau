--[[
	Ranks

	Manages admin ranks and user identity for the Team Chat plugin.
	Operates on the shared AdminState module.
]]

local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local AdminState = require(script.Parent.AdminState)

local RankManager = {}

RankManager.RANK_USER = 0
RankManager.RANK_MODERATOR = 1
RankManager.RANK_ADMIN = 2
RankManager.RANK_OWNER = 3

local RANK_NAMES = Constants.RANK_NAMES

--[=[
	Returns the rank of a user by userId.
]=]
function RankManager.getRank(userId: number): number
	return AdminState.userRanks[userId] or RankManager.RANK_USER
end

--[=[
	Returns the rank name for display.
]=]
function RankManager.getRankName(rank: number): string
	return RANK_NAMES[rank] or "User"
end

--[=[
	Sets a user's rank.
]=]
function RankManager.setRank(userId: number, rank: number)
	rank = math.clamp(rank, RankManager.RANK_USER, RankManager.RANK_OWNER)
	if rank == RankManager.RANK_USER then
		AdminState.userRanks[userId] = nil
	else
		AdminState.userRanks[userId] = rank
	end
	AdminState.save()
end

--[=[
	Returns the current user's rank.
]=]
function RankManager.getMyRank(): number
	return RankManager.getRank(AdminState.currentUserId)
end

--[=[
	Checks if the current user has at least the given rank.
]=]
function RankManager.hasRank(minRank: number): boolean
	return RankManager.getMyRank() >= minRank
end

--[=[
	Returns the current user's id.
]=]
function RankManager.getUserId(): number
	return AdminState.currentUserId
end

--[=[
	Returns the current user's username.
]=]
function RankManager.getUsername(): string
	return AdminState.currentUsername
end

--[=[
	Returns the username for a given userId via Roblox API.
]=]
function RankManager.getUsernameByUserId(userId: number): string
	return Identity.nameOf(userId) or "Unknown"
end

--[=[
	Copies the current Studio user (Core/Identity) into AdminState.
	Called during AdminNetwork.init.
]=]
function RankManager.resolveCurrentUser()
	AdminState.currentUserId = Identity.userId
	AdminState.currentUsername = Identity.username
end

return RankManager
