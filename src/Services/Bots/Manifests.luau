--!strict
--[[
	Manifests

	What each bot offers, as plain data in TeamChatData.Bots (one folder per
	bot): name, avatar, description, commands, owner, and the developer
	portal's settings, log and stats. Also the folders bots use.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Options = require(script.Parent.Options)
local PlaceStorage = require(script.Parent.Parent.Parent.Core.PlaceStorage)

local ONLINE_FOR = 30 -- a Studio bot is online when its mark is this fresh
local LOG_MAX = 40 -- interactions kept per bot for the developer portal

type Option = Options.Option
export type BotCommand = {
	name: string,
	description: string,
	args: { { name: string, description: string?, optional: boolean? } },
	options: { Option },
	botId: string,
	botName: string,
}
export type BotIdentity = { id: string, name: string, avatar: string?, ownerId: number? }

local Manifests = {}

Manifests.SCRIPTS_FOLDER = "TeamChatBots" -- in ServerStorage: Studio bots' code
Manifests.MANIFESTS_FOLDER = "Bots" -- in TeamChatData: what each bot offers
Manifests.REQUESTS_FOLDER = "BotRequests" -- in TeamChatData: interactions for Studio bots

function Manifests.folder(): Folder
	return PlaceStorage.getFolder(Manifests.MANIFESTS_FOLDER)
end

function Manifests.requests(): Folder
	return PlaceStorage.getFolder(Manifests.REQUESTS_FOLDER)
end

function Manifests.scripts(create: boolean?): Folder?
	local folder = ServerStorage:FindFirstChild(Manifests.SCRIPTS_FOLDER)
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = Manifests.SCRIPTS_FOLDER
		folder.Parent = ServerStorage
	end
	return folder :: Folder?
end

function Manifests.decode(json: string?): any
	if type(json) ~= "string" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok then value else nil
end

-- An avatar only from Roblox's own content, so a manifest can't point anywhere else
function Manifests.safeAvatar(avatar: any): string?
	if type(avatar) == "string" and string.match(avatar, "^rbxassetid://%d+$") then
		return avatar
	elseif type(avatar) == "number" then
		return "rbxassetid://" .. tostring(math.floor(avatar))
	end
	return nil
end

--[=[
	Whether a bot (by its manifest folder) answers right now: web bots always
	(their server does), Studio bots while their owner is here.
]=]
function Manifests.isOnline(manifest: Instance): boolean
	if manifest:GetAttribute("Disabled") then
		return false
	end
	if manifest:GetAttribute("Kind") == "web" then
		return true
	end
	local lastSeen = manifest:GetAttribute("LastSeen") or 0
	local ownerId = manifest:GetAttribute("OwnerId")
	local ownerHere = type(ownerId) == "number"
		and (Players:GetPlayerByUserId(ownerId) ~= nil or ownerId == Identity.userId)
	return ownerHere and os.time() - lastSeen <= ONLINE_FOR
end

-- Set in the developer portal: these win over the script's or server's own
function Manifests.nameOf(manifest: Instance): string
	local custom = manifest:GetAttribute("CustomName")
	return if type(custom) == "string" and custom ~= "" then custom else manifest:GetAttribute("Name") or "Bot"
end

local function avatarOf(manifest: Instance, data: { [string]: any }): string?
	return Manifests.safeAvatar(manifest:GetAttribute("CustomAvatar")) or Manifests.safeAvatar(data.avatar)
end

function Manifests.disabledCommands(manifest: Instance): { [string]: boolean }
	local set = {}
	for _, name in ipairs(Manifests.decode(manifest:GetAttribute("DisabledCommands")) or {}) do
		if type(name) == "string" then
			set[name] = true
		end
	end
	return set
end

function Manifests.identityOf(manifest: Instance): BotIdentity
	local data = Manifests.decode(manifest:GetAttribute("Manifest")) or {}
	return {
		id = manifest.Name,
		name = Manifests.nameOf(manifest),
		avatar = avatarOf(manifest, data),
		ownerId = manifest:GetAttribute("OwnerId"),
	}
end

--[=[
	Every bot in the place: { id, kind, name, ownerId, ownerName, online,
	disabled, avatar, description, commands, url }.
]=]
function Manifests.list(): { { [string]: any } }
	local list = {}
	for _, manifest in ipairs(Manifests.folder():GetChildren()) do
		local data = Manifests.decode(manifest:GetAttribute("Manifest")) or {}
		local off = Manifests.disabledCommands(manifest)
		local notes = Manifests.decode(manifest:GetAttribute("CommandNotes")) or {}
		local commands = {}
		for _, command in ipairs(if type(data.commands) == "table" then data.commands else {}) do
			if type(command) == "table" and type(command.name) == "string" then
				local name = Options.cleanName(command.name)
				local note = notes[name]
				table.insert(commands, {
					name = name,
					description = if type(note) == "string" and note ~= ""
						then note
						elseif type(command.description) == "string" then command.description
						else "",
					options = Options.of(command),
					enabled = not off[name],
				})
			end
		end
		local custom = manifest:GetAttribute("CustomDescription")
		table.insert(list, {
			id = manifest.Name,
			kind = manifest:GetAttribute("Kind") or "studio",
			name = Manifests.nameOf(manifest),
			ownerId = manifest:GetAttribute("OwnerId"),
			ownerName = manifest:GetAttribute("OwnerName") or "?",
			online = Manifests.isOnline(manifest),
			disabled = manifest:GetAttribute("Disabled") == true,
			avatar = avatarOf(manifest, data),
			description = if type(custom) == "string" and custom ~= ""
				then custom
				elseif type(data.description) == "string" then data.description
				else "",
			commands = commands,
			url = manifest:GetAttribute("Url"),
			lastSeen = manifest:GetAttribute("LastSeen"),
			health = {
				time = manifest:GetAttribute("HealthTime"),
				ok = manifest:GetAttribute("HealthOk"),
				ms = manifest:GetAttribute("HealthMs"),
				error = manifest:GetAttribute("HealthError"),
			},
		})
	end
	table.sort(list, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
	return list
end

--[=[
	The bots you own (for the developer portal).
]=]
function Manifests.mine(): { { [string]: any } }
	local mine = {}
	for _, bot in ipairs(Manifests.list()) do
		if bot.ownerId == Identity.userId then
			table.insert(mine, bot)
		end
	end
	return mine
end

--[=[
	Every command the place's (enabled) bots offer.
]=]
function Manifests.commands(): { BotCommand }
	local list = {}
	for _, bot in ipairs(Manifests.list()) do
		if not bot.disabled then
			for _, command in ipairs(bot.commands) do
				if not command.enabled then
					continue -- turned off in the developer portal
				end
				local args = {}
				for _, option in ipairs(command.options) do
					table.insert(args, {
						name = option.name,
						description = option.description,
						optional = not option.required,
						choices = option.choices,
						type = option.type,
					})
				end
				table.insert(list, {
					name = command.name,
					description = command.description,
					args = args,
					options = command.options,
					botId = bot.id,
					botName = bot.name,
				})
			end
		end
	end
	return list
end

function Manifests.get(id: string): Instance?
	return Manifests.folder():FindFirstChild(id)
end

-- An interaction for the developer portal's log and stats (kept on the manifest)
export type LogEntry = {
	t: number,
	kind: string, -- "command" | "button" | "ping"
	name: string?, -- the command or button
	user: string?,
	ok: boolean,
	error: string?,
	ms: number?,
	test: boolean?, -- from the portal's test console
}

function Manifests.record(manifest: Instance?, entry: LogEntry)
	if not manifest or not manifest.Parent then
		return
	end
	local entries = Manifests.decode(manifest:GetAttribute("Log")) or {}
	table.insert(entries, 1, entry)
	while #entries > LOG_MAX do
		table.remove(entries)
	end
	manifest:SetAttribute("Log", HttpService:JSONEncode(entries))
	if entry.test or entry.kind == "ping" then
		return -- tests and checks aren't real use
	end
	local stats = Manifests.decode(manifest:GetAttribute("Stats")) or {}
	stats.total = (tonumber(stats.total) or 0) + 1
	stats.errors = (tonumber(stats.errors) or 0) + (if entry.ok then 0 else 1)
	if entry.ms then
		stats.ms = (tonumber(stats.ms) or 0) + entry.ms
		stats.timed = (tonumber(stats.timed) or 0) + 1
	end
	stats.commands = if type(stats.commands) == "table" then stats.commands else {}
	local key = (if entry.kind == "button" then "button:" else "/") .. tostring(entry.name or "?")
	stats.commands[key] = (tonumber(stats.commands[key]) or 0) + 1
	manifest:SetAttribute("Stats", HttpService:JSONEncode(stats))
end

function Manifests.elapsed(since: number): number
	return math.floor((os.clock() - since) * 1000 + 0.5)
end

return Manifests
