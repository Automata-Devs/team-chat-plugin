--!strict
--[[
	Bots

	User-made Team Chat bots. A bot is a ModuleScript in
	ServerStorage.TeamChatBots (made with /bot create) that returns a table:
	its name, commands and an optional onMessage handler (docs/BOTS.md).

	A bot runs only in its owner's Studio (the ModuleScript's OwnerId):
	nobody else's code ever runs on your computer. The owner's plugin
	publishes the bot's manifest (name, avatar, commands; plain data, never
	code) to TeamChatData.Bots and keeps it marked online. When someone uses
	a bot's command, their plugin leaves a request in TeamChatData.BotRequests;
	the owner's plugin runs it and posts the reply for everyone, under
	"<name> used /command".

	Open Cloud (https://create.roblox.com/docs/cloud) calls use an API key
	stored in the owner's plugin settings, never in the place (where every
	editor could read it).

	Usage:
		Bots.init()
		Bots.commands()                          -- every bot command (for /help and autocomplete)
		Bots.tryCommand(name, args, text, ctx)   -- true when a bot handles /name
		Bots.create("Weather")                   -- a new bot script owned by you
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ChatState = require(script.Parent.Chat.ChatState)
local Conversations = require(script.Parent.Chat.Conversations)
local Identity = require(script.Parent.Parent.Core.Identity)
local Language = require(script.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local Logger = require(script.Parent.Parent.Core.Logger)
local PlaceStorage = require(script.Parent.Parent.Core.PlaceStorage)
local Settings = require(script.Parent.Parent.Core.Settings)
local TimeFormat = require(script.Parent.Parent.Util.TimeFormat)

local log = Logger.scope("Bots")

local Bots = {}

Bots.SCRIPTS_FOLDER = "TeamChatBots" -- in ServerStorage: the bots' code
Bots.MANIFESTS_FOLDER = "Bots" -- in TeamChatData: what each bot offers
Bots.REQUESTS_FOLDER = "BotRequests" -- in TeamChatData: commands waiting for a bot
Bots.API_KEY_SETTING = "TeamChatBotApiKey_v1" -- plugin setting (this computer only)
Bots.OPEN_CLOUD_URL = "https://apis.roblox.com"

local HEARTBEAT = 10 -- seconds between "still online" marks
local ONLINE_FOR = 30 -- a bot is online when its mark is this fresh
local REQUEST_TIMEOUT = 60 -- unanswered requests are cleaned up after this

export type Arg = { name: string, description: string?, optional: boolean? }
export type BotCommand = {
	name: string,
	description: string,
	args: { Arg },
	botId: string,
	botName: string,
}

type Running = {
	id: string,
	module: ModuleScript,
	definition: { [string]: any },
}

local running: { [string]: Running } = {}
local started = false

local function manifests(): Folder
	return PlaceStorage.getFolder(Bots.MANIFESTS_FOLDER)
end

local function requests(): Folder
	return PlaceStorage.getFolder(Bots.REQUESTS_FOLDER)
end

local function scripts(create: boolean?): Folder?
	local folder = ServerStorage:FindFirstChild(Bots.SCRIPTS_FOLDER)
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = Bots.SCRIPTS_FOLDER
		folder.Parent = ServerStorage
	end
	return folder :: Folder?
end

local function cleanName(name: string): string
	return (string.gsub(string.lower(name), "[^%w_]", ""))
end

local function decode(json: string?): any
	if not json then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok then value else nil
end

-- An avatar only from Roblox's own content, so a manifest can't point anywhere else
local function safeAvatar(avatar: any): string?
	if type(avatar) == "string" and string.match(avatar, "^rbxassetid://%d+$") then
		return avatar
	end
	return nil
end

--[=[
	Whether a bot (by its manifest folder) is online: its owner is here and
	their plugin marked it recently.
]=]
function Bots.isOnline(manifest: Instance): boolean
	local lastSeen = manifest:GetAttribute("LastSeen") or 0
	local ownerId = manifest:GetAttribute("OwnerId")
	local ownerHere = type(ownerId) == "number"
		and (Players:GetPlayerByUserId(ownerId) ~= nil or ownerId == Identity.userId)
	return ownerHere and os.time() - lastSeen <= ONLINE_FOR
end

--[=[
	Every bot in the place: { id, name, ownerId, ownerName, online, avatar, commands }.
]=]
function Bots.list(): { { [string]: any } }
	local list = {}
	for _, manifest in ipairs(manifests():GetChildren()) do
		local data = decode(manifest:GetAttribute("Manifest")) or {}
		table.insert(list, {
			id = manifest.Name,
			name = manifest:GetAttribute("Name") or "Bot",
			ownerId = manifest:GetAttribute("OwnerId"),
			ownerName = manifest:GetAttribute("OwnerName") or "?",
			online = Bots.isOnline(manifest),
			avatar = safeAvatar(data.avatar),
			description = if type(data.description) == "string" then data.description else "",
			commands = if type(data.commands) == "table" then data.commands else {},
		})
	end
	table.sort(list, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
	return list
end

--[=[
	Every command the place's bots offer.
]=]
function Bots.commands(): { BotCommand }
	local list = {}
	for _, bot in ipairs(Bots.list()) do
		for _, command in ipairs(bot.commands) do
			if type(command) == "table" and type(command.name) == "string" then
				table.insert(list, {
					name = command.name,
					description = if type(command.description) == "string" then command.description else "",
					args = if type(command.args) == "table" then command.args else {},
					botId = bot.id,
					botName = bot.name,
				})
			end
		end
	end
	return list
end

-- The manifest of a running bot: only plain data (never functions)
local function publish(bot: Running)
	local definition = bot.definition
	local commands = {}
	for name, command in pairs(definition.commands or {}) do
		if type(command) == "table" and type(command.run) == "function" then
			local args = {}
			for _, arg in ipairs(command.args or {}) do
				if type(arg) == "table" and type(arg.name) == "string" then
					table.insert(args, {
						name = arg.name,
						description = if type(arg.description) == "string" then arg.description else nil,
						optional = arg.optional == true,
					})
				end
			end
			table.insert(commands, {
				name = cleanName(tostring(name)),
				description = if type(command.description) == "string" then command.description else "",
				args = args,
			})
		end
	end
	table.sort(commands, function(a, b)
		return a.name < b.name
	end)
	local folder = manifests():FindFirstChild(bot.id)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = bot.id
		folder.Parent = manifests()
	end
	folder:SetAttribute("Name", tostring(definition.name or bot.module.Name))
	folder:SetAttribute("OwnerId", Identity.userId)
	folder:SetAttribute("OwnerName", Identity.username)
	folder:SetAttribute(
		"Manifest",
		HttpService:JSONEncode({
			description = if type(definition.description) == "string" then definition.description else "",
			avatar = safeAvatar(definition.avatar),
			commands = commands,
		})
	)
	folder:SetAttribute("LastSeen", os.time())
end

--[=[
	Posts a message from a bot to a conversation (everyone sees it). With
	`request`, it shows under "<name> used /command".
]=]
function Bots.post(bot: Running, content: string, embed: { [string]: any }?, conversation: string?, request: Instance?)
	local folder = Conversations.getFolder(conversation or Conversations.MAIN, true)
	if not folder then
		return
	end
	local message = Instance.new("Folder")
	message.Name = "bot_" .. TimeFormat.generateId()
	message:SetAttribute("Sender", tostring(bot.definition.name or bot.module.Name))
	message:SetAttribute("SenderId", 0)
	message:SetAttribute("BotId", bot.id)
	message:SetAttribute("BotOwner", Identity.userId)
	message:SetAttribute("BotAvatar", safeAvatar(bot.definition.avatar))
	message:SetAttribute("Timestamp", os.time())
	message:SetAttribute("Content", content)
	message:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_TEXT)
	if request then
		message:SetAttribute("SaidBy", request:GetAttribute("ById"))
		message:SetAttribute("SaidByName", request:GetAttribute("ByName"))
		message:SetAttribute("Command", "/" .. tostring(request:GetAttribute("Command")))
	end
	if embed then
		local copy = table.clone(embed)
		if typeof(copy.color) == "Color3" then
			copy.color = copy.color:ToHex()
		end
		message:SetAttribute("Embed", HttpService:JSONEncode(copy))
	end
	message.Parent = folder
	ChatState.saveHistory()
end

--[=[
	The API key bots use for Open Cloud, from this computer's plugin
	settings (nil when not set).
]=]
function Bots.apiKey(): string?
	local key = Settings.get(Bots.API_KEY_SETTING)
	return if type(key) == "string" and key ~= "" then key else nil
end

function Bots.setApiKey(key: string?)
	Settings.set(Bots.API_KEY_SETTING, key)
end

-- What a bot's functions get: who ran it, what was typed, and ways to answer
local function makeContext(bot: Running, request: Instance?, args: { string }?, conversation: string?)
	local ctx = {}
	ctx.bot = { id = bot.id, name = bot.definition.name }
	ctx.args = args or {}
	ctx.text = table.concat(ctx.args, " ")
	if request then
		ctx.user = { id = request:GetAttribute("ById"), name = request:GetAttribute("ByName") }
		ctx.command = request:GetAttribute("Command")
	end
	ctx.conversation = conversation or Conversations.MAIN

	-- Answer the command (under "<name> used /command"), or post a message
	-- of the bot's own. Text, or a card spec (see Commands/_Template).
	function ctx.reply(message: string | { [string]: any })
		if type(message) == "table" then
			Bots.post(bot, "", message, ctx.conversation, request)
		else
			Bots.post(bot, tostring(message), nil, ctx.conversation, request)
		end
	end
	function ctx.send(message: string | { [string]: any })
		if type(message) == "table" then
			Bots.post(bot, "", message, ctx.conversation, nil)
		else
			Bots.post(bot, tostring(message), nil, ctx.conversation, nil)
		end
	end

	-- Web requests (HttpService:RequestAsync). Returns the response, or nil and an error.
	function ctx.http(options: { [string]: any }): ({ [string]: any }?, string?)
		local ok, response = pcall(HttpService.RequestAsync, HttpService, options)
		if not ok then
			return nil, tostring(response)
		end
		return response, nil
	end

	-- Roblox Open Cloud: ctx.openCloud("GET", "/cloud/v2/users/156") with the
	-- API key saved by /bot key. Returns the decoded JSON, or nil and an error.
	function ctx.openCloud(method: string, path: string, body: any?): (any, string?)
		local key = Bots.apiKey()
		if not key then
			return nil, "No API key: the bot's owner can add one with /bot key <key>"
		end
		local response, err = ctx.http({
			Url = Bots.OPEN_CLOUD_URL .. path,
			Method = method,
			Headers = { ["x-api-key"] = key, ["Content-Type"] = "application/json" },
			Body = if body ~= nil then HttpService:JSONEncode(body) else nil,
		})
		if not response then
			return nil, err
		end
		local data = decode(response.Body)
		if not response.Success then
			return nil, string.format("%d %s", response.StatusCode, response.StatusMessage)
		end
		return if data ~= nil then data else response.Body, nil
	end

	ctx.json = {
		encode = function(value: any): string
			return HttpService:JSONEncode(value)
		end,
		decode = decode,
	}
	return ctx
end

-- Runs a bot function safely; a failure is logged and told to the chat
local function call(bot: Running, label: string, fn: (...any) -> (), ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		log.warn(string.format("Bot %s failed in %s: %s", tostring(bot.definition.name), label, tostring(err)))
	end
	return ok, err
end

local function handle(request: Instance)
	local bot = running[request:GetAttribute("BotId") or ""]
	if not bot or request:GetAttribute("Handling") then
		return
	end
	request:SetAttribute("Handling", true)
	local name = request:GetAttribute("Command")
	local command = nil
	for commandName, definition in pairs(bot.definition.commands or {}) do
		if cleanName(tostring(commandName)) == name and type(definition) == "table" then
			command = definition
		end
	end
	local args = decode(request:GetAttribute("Args")) or {}
	local conversation = request:GetAttribute("Conversation")
	if command and type(command.run) == "function" then
		local ctx = makeContext(bot, request, args, conversation)
		local ok, err = call(bot, "/" .. tostring(name), command.run, ctx)
		if not ok then
			ctx.reply("\u{26A0} " .. tostring(err))
		end
	end
	request:Destroy()
end

-- Loads a bot script (a fresh copy, so edits take effect)
local function load(module: ModuleScript): Running?
	local ok, definition = pcall(require, module:Clone())
	if not ok or type(definition) ~= "table" then
		log.warn("Couldn't load bot " .. module.Name .. ": " .. tostring(definition))
		return nil
	end
	local id = module:GetAttribute("BotId")
	if type(id) ~= "string" then
		id = HttpService:GenerateGUID(false)
		module:SetAttribute("BotId", id)
	end
	return { id = id :: string, module = module, definition = definition }
end

--[=[
	(Re)starts every bot you own in this place. Returns their names.
]=]
function Bots.reload(): { string }
	running = {}
	local names = {}
	local folder = scripts(false)
	if not folder or Identity.userId <= 0 then
		return names
	end
	for _, module in ipairs(folder:GetChildren()) do
		if module:IsA("ModuleScript") and module:GetAttribute("OwnerId") == Identity.userId then
			local bot = load(module)
			if bot then
				running[bot.id] = bot
				publish(bot)
				table.insert(names, tostring(bot.definition.name or module.Name))
				if type(bot.definition.onStart) == "function" then
					task.spawn(call, bot, "onStart", bot.definition.onStart, makeContext(bot))
				end
			end
		end
	end
	return names
end

--[=[
	Makes a new bot script owned by you (from the template) and returns it.
]=]
function Bots.create(name: string): (ModuleScript?, string?)
	if Identity.userId <= 0 then
		return nil, "signedOut"
	end
	local folder = scripts(true) :: Folder
	if folder:FindFirstChild(name) then
		return nil, "exists"
	end
	local source = string.gsub(Bots.TEMPLATE, "{name}", name)
	local module = Instance.new("ModuleScript")
	module.Name = name
	module:SetAttribute("OwnerId", Identity.userId)
	module.Source = source
	module.Parent = folder
	if module.Source ~= source then
		-- Team Create can undo direct Source writes: go through the script editor
		pcall(function()
			game:GetService("ScriptEditorService"):UpdateSourceAsync(module, function()
				return source
			end)
		end)
	end
	Bots.reload()
	return module, nil
end

--[=[
	Removes a bot you own: its script and its manifest.
]=]
function Bots.remove(name: string): boolean
	local folder = scripts(false)
	local module = folder and folder:FindFirstChild(name)
	if not module or module:GetAttribute("OwnerId") ~= Identity.userId then
		return false
	end
	local id = module:GetAttribute("BotId")
	local manifest = id and manifests():FindFirstChild(id)
	if manifest then
		manifest:Destroy()
	end
	module:Destroy()
	Bots.reload()
	return true
end

--[=[
	Runs /name when a bot offers it: leaves a request for the bot's owner,
	or says the bot is offline. Returns true when a bot offers the command.
	`context` is the command context (Controllers/MessageController).
]=]
function Bots.tryCommand(name: string, args: { string }, context): boolean
	local lowered = string.lower(name)
	for _, manifest in ipairs(manifests():GetChildren()) do
		local data = decode(manifest:GetAttribute("Manifest")) or {}
		for _, command in ipairs(if type(data.commands) == "table" then data.commands else {}) do
			if type(command) == "table" and command.name == lowered then
				if not Bots.isOnline(manifest) then
					context.addSystemMessage(Language.t("bot.offline", {
						bot = manifest:GetAttribute("Name") or "Bot",
						owner = manifest:GetAttribute("OwnerName") or "?",
					}))
					return true
				end
				local request = Instance.new("Folder")
				request.Name = "request_" .. TimeFormat.generateId()
				request:SetAttribute("BotId", manifest.Name)
				request:SetAttribute("Command", lowered)
				request:SetAttribute("Args", HttpService:JSONEncode(args))
				request:SetAttribute("ById", Identity.userId)
				request:SetAttribute("ByName", Identity.username)
				request:SetAttribute("Conversation", Conversations.getActiveId())
				request:SetAttribute("Timestamp", os.time())
				request.Parent = requests()
				return true
			end
		end
	end
	return false
end

--[=[
	Starts the bots you own and listens for their commands and messages.
]=]
function Bots.init()
	if started then
		return
	end
	started = true
	Bots.reload()

	-- Commands for your bots (from anyone, including you)
	Lifetime.connect(requests().ChildAdded, function(request)
		task.defer(handle, request)
	end)
	for _, request in ipairs(requests():GetChildren()) do
		task.defer(handle, request)
	end

	-- onMessage: new team chat messages (not the bots' own)
	Conversations.onMessage(function(id, message)
		if id ~= Conversations.MAIN or message:GetAttribute("BotId") or message:GetAttribute("Sender") == "System" then
			return
		end
		if os.time() - (message:GetAttribute("Timestamp") or 0) > 10 then
			return -- loading old messages, not new ones
		end
		for _, bot in pairs(running) do
			if type(bot.definition.onMessage) == "function" then
				local ctx = makeContext(bot, nil, nil, id)
				task.spawn(call, bot, "onMessage", bot.definition.onMessage, ctx, {
					text = message:GetAttribute("Content") or "",
					sender = message:GetAttribute("Sender"),
					senderId = message:GetAttribute("SenderId"),
					timestamp = message:GetAttribute("Timestamp"),
				})
			end
		end
	end)

	-- Stay marked online; clean up requests nobody answered
	task.spawn(function()
		while Lifetime.alive do
			for id in pairs(running) do
				local manifest = manifests():FindFirstChild(id)
				if manifest then
					manifest:SetAttribute("LastSeen", os.time())
				end
			end
			for _, request in ipairs(requests():GetChildren()) do
				if os.time() - (request:GetAttribute("Timestamp") or 0) > REQUEST_TIMEOUT then
					request:Destroy()
				end
			end
			task.wait(HEARTBEAT)
		end
	end)
end

Bots.TEMPLATE = [==[
--[[
	{name}: a Team Chat bot. It runs in your Studio only (you own it); everyone
	in the place can use its commands while you're here.
	How bots work: docs/BOTS.md in the Team Chat repository.
]]

local bot = {
	name = "{name}",
	description = "What this bot does",
	avatar = nil, -- "rbxassetid://<image id>" for a picture
	commands = {},
}

-- /hello [name]
bot.commands.hello = {
	description = "Say hello",
	args = { { name = "name", description = "Who to greet", optional = true } },
	run = function(ctx)
		ctx.reply("Hello, " .. (ctx.args[1] or ctx.user.name) .. "!")
	end,
}

-- Optional: runs for every new message in the team chat
-- function bot.onMessage(ctx, message)
-- 	if message.text == "ping" then
-- 		ctx.send("pong")
-- 	end
-- end

return bot
]==]

return Bots
