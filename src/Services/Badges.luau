--!strict
--[[
	Badges

	Which badges a user has: Verified (Roblox verified accounts, from
	Services/Profiles), custom badges from Config/Badges, and bought badges
	(game passes, checked with MarketplaceService). Each viewer looks these up
	on their own computer, so nobody can give themselves a badge by editing
	the chat data. A user can have any number of badges.

	Buying: plugins can't show Roblox's purchase prompt, so a purchase is
	finished on the game pass's Roblox.com page. watchPurchase() then checks
	ownership every few seconds until the pass shows up (or it gives up).

	Usage:
		Badges.get(userId)                  -- { Badge }, verified first
		Badges.changed:Connect(function(userId) ... end)
		Badges.refresh(userId)              -- look again (after buying one)
		Badges.getStore(userId)             -- yields: the badges for sale
		Badges.purchaseUrl(passId)
		Badges.watchPurchase(userId, badgeId, function(status) ... end)
]]

local MarketplaceService = game:GetService("MarketplaceService")

local BadgeConfig = require(script.Parent.Parent.Config.Badges)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local Logger = require(script.Parent.Parent.Core.Logger)
local Profiles = require(script.Parent.Profiles)
local Signal = require(script.Parent.Parent.Util.Signal)

export type Badge = {
	id: string,
	name: string,
	description: string,
	icon: string?, -- Builder Icons name; nil for the verified badge
	color: Color3?,
	verified: boolean?,
}

export type StoreItem = {
	badge: Badge,
	gamePassId: number,
	forSale: boolean,
	price: number?, -- Robux, when known
	passName: string?, -- the game pass's name on Roblox, when known
	owned: boolean,
}

-- "waiting" while checking, then "owned" (bought) or "timeout"
export type PurchaseStatus = "waiting" | "owned" | "timeout"

local RETRY_AFTER = 120 -- seconds before a failed game pass check is tried again
local PURCHASE_POLL_INTERVAL = 5 -- seconds between ownership checks after Buy
local PURCHASE_POLL_TIMEOUT = 600 -- give up watching after this long

local log = Logger.scope("Badges")

local Badges = {}

Badges.changed = Signal.new()
Badges.VERIFIED = {
	id = "verified",
	name = "Verified",
	description = "Verified Roblox account",
	verified = true,
} :: Badge

type Entry = {
	owned: { [string]: boolean },
	failedAt: number?,
}

local entries: { [number]: Entry } = {}
local priceCache: { [number]: number | false } = {}
local nameCache: { [number]: string? } = {} -- game pass id -> its name on Roblox
local watching: { [string]: boolean } = {}

local function definitionBadge(id: string): Badge?
	local definition = BadgeConfig.DEFINITIONS[id]
	if not definition then
		return nil
	end
	return {
		id = id,
		name = definition.name,
		description = definition.description,
		icon = definition.icon,
		color = definition.color,
	}
end

local function fireChanged(userId: number)
	if Lifetime.alive then
		Badges.changed:Fire(userId)
	end
end

-- A verified flag arriving is a badge change too
Lifetime.add(Profiles.changed:Connect(fireChanged))

local function ownsPass(userId: number, gamePassId: number): boolean?
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)
	end)
	if not ok then
		log.debug("Couldn't check game pass %d for %d: %s", gamePassId, userId, tostring(owns))
		return nil
	end
	return owns
end

-- Checks every game pass badge for a user (in the background)
local function resolve(userId: number, entry: Entry)
	task.spawn(function()
		local changed = false
		for id, definition in pairs(BadgeConfig.DEFINITIONS) do
			local passId = definition.gamePassId
			if passId and passId > 0 then
				local owns = ownsPass(userId, passId)
				if owns == nil then
					entry.failedAt = os.clock()
				elseif owns and not entry.owned[id] then
					entry.owned[id] = true
					changed = true
				end
			end
		end
		if changed then
			fireChanged(userId)
		end
	end)
end

--[=[
	The badges a user has, in display order: verified, then custom and bought
	badges (Config/Badges ORDER). Starts the lookups on first use.
]=]
function Badges.get(userId: number?): { Badge }
	if type(userId) ~= "number" or userId <= 0 then
		return {}
	end
	local entry = entries[userId]
	if not entry or (entry.failedAt and os.clock() - entry.failedAt > RETRY_AFTER) then
		entry = { owned = if entry then entry.owned else {} }
		entries[userId] = entry
		resolve(userId, entry)
	end

	local list: { Badge } = {}
	if Profiles.get(userId).verified then
		table.insert(list, Badges.VERIFIED)
	end
	local given = {}
	for _, id in ipairs(BadgeConfig.USERS[userId] or {}) do
		given[id] = true
	end
	for _, id in ipairs(BadgeConfig.ORDER) do
		if given[id] or entry.owned[id] then
			local badge = definitionBadge(id)
			if badge then
				table.insert(list, badge)
			end
		end
	end
	return list
end

--[=[
	Forgets what's known about a user and looks again (e.g. after buying a
	badge). `changed` fires when the new results are in.
]=]
function Badges.refresh(userId: number)
	entries[userId] = nil
	Profiles.forget(userId)
	Badges.get(userId)
	fireChanged(userId)
end

--[=[
	The badges for sale, with prices and whether `userId` owns them. Yields
	(web requests); call it from a separate thread.
]=]
function Badges.getStore(userId: number): { StoreItem }
	local items: { StoreItem } = {}
	for _, id in ipairs(BadgeConfig.ORDER) do
		local definition = BadgeConfig.DEFINITIONS[id]
		if definition and definition.gamePassId ~= nil then
			local passId = definition.gamePassId :: number
			local forSale = passId > 0
			local price: number? = nil
			local passName: string? = nil
			local owned = false
			if forSale then
				if priceCache[passId] == nil then
					local ok, info = pcall(function()
						return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
					end)
					priceCache[passId] = if ok and type(info.PriceInRobux) == "number" then info.PriceInRobux else false
					nameCache[passId] = if ok and type(info.Name) == "string" then info.Name else nil
				end
				local cached = priceCache[passId]
				price = if cached then cached else nil
				passName = nameCache[passId]
				owned = userId > 0 and ownsPass(userId, passId) == true
			end
			table.insert(items, {
				badge = definitionBadge(id) :: Badge,
				gamePassId = passId,
				forSale = forSale,
				price = price,
				passName = passName,
				owned = owned,
			})
		end
	end
	return items
end

--[=[
	The Roblox page where a game pass is bought, with its name in the address
	like Roblox's own links (https://www.roblox.com/game-pass/<id>/<Name-Like-This>).
]=]
function Badges.purchaseUrl(gamePassId: number, passName: string?): string
	local url = "https://www.roblox.com/game-pass/" .. tostring(gamePassId)
	local slug = if passName then string.gsub(string.gsub(passName, "[^%w]+", "-"), "^%-*(.-)%-*$", "%1") else ""
	return if slug ~= "" then url .. "/" .. slug else url
end

--[=[
	After the buyer opened the game pass page: checks ownership every few
	seconds and calls onStatus("owned") once it's bought (the badge then
	shows everywhere), or onStatus("timeout") after 10 minutes. Watching the
	same badge twice does nothing.
]=]
function Badges.watchPurchase(userId: number, badgeId: string, onStatus: (PurchaseStatus) -> ())
	local definition = BadgeConfig.DEFINITIONS[badgeId]
	local passId = definition and definition.gamePassId
	local key = tostring(userId) .. ":" .. badgeId
	if not passId or passId <= 0 or userId <= 0 or watching[key] then
		return
	end
	watching[key] = true
	onStatus("waiting")
	task.spawn(function()
		local deadline = os.clock() + PURCHASE_POLL_TIMEOUT
		while Lifetime.alive and os.clock() < deadline do
			task.wait(PURCHASE_POLL_INTERVAL)
			if ownsPass(userId, passId) then
				watching[key] = nil
				local entry = entries[userId]
				if entry then
					entry.owned[badgeId] = true
				end
				fireChanged(userId)
				onStatus("owned")
				return
			end
		end
		watching[key] = nil
		if Lifetime.alive then
			onStatus("timeout")
		end
	end)
end

return Badges
