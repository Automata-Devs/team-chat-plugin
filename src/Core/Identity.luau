--!strict
--[[
	Identity

	Who is using the plugin: the Studio user's id and username, looked up once.
	userId is 0 (and the name "Unknown") when Studio isn't signed in.

	Usage:
		Identity.init()            -- once, in App (makes one web call)
		Identity.userId, Identity.username
		Identity.nameOf(156)       -- any user's name (web call, cached)
]]

local Players = game:GetService("Players")
local StudioService = game:GetService("StudioService")

local Logger = require(script.Parent.Logger)

local log = Logger.scope("Identity")

local Identity = {
	userId = 0,
	username = "Unknown",
}

local nameCache: { [number]: string } = {}

--[=[
	Looks up a user's name. Cached; returns nil if it can't be fetched.
]=]
function Identity.nameOf(userId: number): string?
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return nil
end

--[=[
	Resolves the signed-in Studio user. Safe to call more than once.
]=]
function Identity.init()
	if Identity.userId > 0 then
		return
	end
	local ok, userId = pcall(function()
		return StudioService:GetUserId()
	end)
	if not ok or type(userId) ~= "number" or userId <= 0 then
		log.info("Studio isn't signed in: chatting works, but direct messages and ranks need an account")
		return
	end
	Identity.userId = userId
	Identity.username = Identity.nameOf(userId) or "Unknown"
end

return Identity
