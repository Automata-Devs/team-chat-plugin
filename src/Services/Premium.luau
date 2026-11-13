--!strict
--[[
	Premium

	Whether someone has Team Chat Premium, and the limits and themes that
	gives them (Config/Premium). Premium is the "premium" badge: bought as a
	game pass, or given in Config/Badges USERS. Badge lookups finish in the
	background, so has() is false until Roblox has answered; Badges.changed
	fires when it does.

	Usage:
		if Premium.has(userId) then ... end
		local max = Premium.messageLength(userId)
]]

local Badges = require(script.Parent.Badges)
local PremiumConfig = require(script.Parent.Parent.Config.Premium)

local Premium = {}

function Premium.has(userId: number?): boolean
	for _, badge in ipairs(Badges.get(userId)) do
		if badge.id == PremiumConfig.BADGE then
			return true
		end
	end
	return false
end

--[=[
	The most characters `userId` can send in one message.
]=]
function Premium.messageLength(userId: number?): number
	return if Premium.has(userId) then PremiumConfig.MESSAGE_LENGTH.premium else PremiumConfig.MESSAGE_LENGTH.free
end

--[=[
	The most answers `userId` can give a poll.
]=]
function Premium.pollOptions(userId: number?): number
	return if Premium.has(userId) then PremiumConfig.POLL_OPTIONS.premium else PremiumConfig.POLL_OPTIONS.free
end

--[=[
	True for a theme only Premium can pick.
]=]
function Premium.isPremiumTheme(name: string): boolean
	return table.find(PremiumConfig.THEMES, name) ~= nil
end

return Premium
