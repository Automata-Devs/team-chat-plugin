--!strict
--[[
	UserStats

	Each person's profile on the database server: their name, when and where
	they last used Team Chat, and how many team chat messages they've sent.
	It follows them across places and computers. Only your own plugin writes
	your profile.
]]

local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Archive = require(script.Parent.Archive)
local Cache = require(script.Parent.Cache)
local Client = require(script.Parent.Client)
local Outbox = require(script.Parent.Outbox)

export type Profile = {
	userId: number,
	username: string?,
	lastSeen: number?,
	lastPlace: { id: number, name: string }?,
	firstSeen: number?,
	stats: { [string]: number }?,
}

local UserStats = {}

local function path(userId: number): string
	return "/profiles/" .. tostring(userId)
end

--[=[
	Uploads my profile and the messages I've sent since the last sync. Queued
	when the server can't be reached. Returns false and a problem if it was refused. Yields.
]=]
function UserStats.sync(): (boolean, string?)
	if Identity.userId <= 0 then
		return false, "signedOut"
	end
	local sent = Archive.sentSinceSync
	local body = {
		set = {
			username = Identity.username,
			lastSeen = os.time(),
			lastPlace = { id = game.PlaceId, name = game.Name },
		},
		increment = { messagesSent = sent },
	}
	local result = Client.request("POST", path(Identity.userId), body)
	if result.problem and not result.retry then
		return false, result.problem
	end
	if result.problem then
		Outbox.push({ method = "POST", path = path(Identity.userId), body = body })
	elseif type(result.data) == "table" then
		Cache.put(path(Identity.userId), result.data)
	end
	Archive.sentSinceSync -= sent
	return true, nil
end

--[=[
	Someone's profile, or nil when they have none. When the server can't be
	reached, the last one seen (and the problem). Yields.
]=]
function UserStats.get(userId: number): (Profile?, string?)
	local result = Client.request("GET", path(userId))
	if result.problem and string.sub(result.problem, 1, 3) == "404" then
		return nil, nil
	end
	if result.problem then
		return Cache.get(path(userId)), result.problem
	end
	Cache.put(path(userId), result.data)
	return result.data, nil
end

return UserStats
