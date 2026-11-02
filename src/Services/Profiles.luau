--!strict
--[[
	Profiles

	Public Roblox profile info for user ids: display name and whether the
	account is verified (UserService). Lookups are batched and cached; the
	first get() for a user starts one in the background and returns what's
	known so far, and `changed` fires with the userId when it's done.

	Usage:
		local profile = Profiles.get(userId)  -- { displayName?, verified }
		Profiles.changed:Connect(function(userId) ... end)
]]

local UserService = game:GetService("UserService")

local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local Logger = require(script.Parent.Parent.Core.Logger)
local Signal = require(script.Parent.Parent.Util.Signal)

export type Profile = {
	displayName: string?,
	username: string?,
	verified: boolean,
	loaded: boolean,
}

local BATCH = 100 -- most ids GetUserInfosByUserIdsAsync takes at once
local RETRY_AFTER = 120 -- seconds before a failed lookup is tried again

local log = Logger.scope("Profiles")

local Profiles = {}

Profiles.changed = Signal.new()

local cache: { [number]: Profile & { failedAt: number? } } = {}
local queue: { number } = {}
local flushQueued = false

local function flush()
	flushQueued = false
	while #queue > 0 do
		local batch = {}
		while #queue > 0 and #batch < BATCH do
			table.insert(batch, table.remove(queue, 1))
		end
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(batch)
		end)
		if not ok then
			log.debug("Couldn't look up profiles: %s", tostring(infos))
			for _, userId in ipairs(batch) do
				local entry = cache[userId]
				if entry then
					entry.failedAt = os.clock()
				end
			end
			continue
		end
		for _, info in ipairs(infos) do
			local entry = cache[info.Id]
			if entry then
				entry.displayName = info.DisplayName
				entry.username = info.Username
				entry.verified = info.HasVerifiedBadge == true
				entry.loaded = true
				if Lifetime.alive then
					Profiles.changed:Fire(info.Id)
				end
			end
		end
	end
end

--[=[
	What's known about a user (display name, verified). Starts a lookup the
	first time; `changed` fires when it finishes.
]=]
function Profiles.get(userId: number?): Profile
	if type(userId) ~= "number" or userId <= 0 then
		return { verified = false, loaded = true }
	end
	local entry = cache[userId]
	if not entry or (entry.failedAt and os.clock() - entry.failedAt > RETRY_AFTER) then
		entry = {
			displayName = entry and entry.displayName,
			username = entry and entry.username,
			verified = entry ~= nil and entry.verified,
			loaded = false,
		}
		cache[userId] = entry
		table.insert(queue, userId)
		if not flushQueued then
			flushQueued = true
			task.defer(flush)
		end
	end
	return entry
end

--[=[
	Forgets a user so the next get() looks them up again.
]=]
function Profiles.forget(userId: number)
	cache[userId] = nil
end

return Profiles
