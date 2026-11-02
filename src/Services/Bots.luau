--!strict
--[[
	Bots

	User-made Team Chat bots, Discord-style: slash commands with typed
	options, replies with cards and buttons, ephemeral ("only you can see
	this") and deferred ("thinking…") replies. Two kinds (docs/BOTS.md):

	- Studio bots: a ModuleScript in ServerStorage.TeamChatBots, made with
	  /bot create or the developer portal. It runs only in its owner's Studio
	  (nobody else's code ever runs on your computer). The owner's plugin
	  publishes its manifest and answers requests that other plugins leave in
	  TeamChatData.BotRequests.
	- Web bots: a URL on the owner's own server (any language), like Discord's
	  HTTP interactions. Whoever uses a command, their plugin POSTs the
	  interaction to the URL (with the bot's token) and shows the answer, so
	  web bots work while their owner is offline.

	Every bot's manifest (name, avatar, commands; plain data) is in
	TeamChatData.Bots, one folder per bot. Bot messages are saved chat
	messages with BotId; ephemeral ones carry VisibleTo (only that person's
	chat shows them) or, for web bots, aren't saved at all.

	Usage:
		Bots.init()
		Bots.commands()                     -- every bot command (/help, autocomplete)
		Bots.tryCommand(name, args, ctx)    -- true when a bot offers /name
		Bots.create("Weather")              -- a Studio bot script owned by you
		Bots.createWeb("Weather", url)      -- a web bot owned by you
		Bots.clickButton(info)              -- a button under a bot message was clicked
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local AdminNetwork = require(script.Parent.Admin)
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

Bots.SCRIPTS_FOLDER = "TeamChatBots" -- in ServerStorage: Studio bots' code
Bots.MANIFESTS_FOLDER = "Bots" -- in TeamChatData: what each bot offers
Bots.REQUESTS_FOLDER = "BotRequests" -- in TeamChatData: interactions for Studio bots
Bots.API_KEY_SETTING = "TeamChatBotApiKey_v1" -- plugin setting (this computer only)
Bots.OPEN_CLOUD_URL = "https://apis.roblox.com"
Bots.TOKEN_HEADER = "X-TeamChat-Token"

local HEARTBEAT = 10 -- seconds between "still online" marks
local ONLINE_FOR = 30 -- a Studio bot is online when its mark is this fresh
local REQUEST_TIMEOUT = 60 -- unanswered requests are cleaned up after this
local FOLLOWUP_EVERY = 2 -- seconds between asking a web bot for its deferred answer
local FOLLOWUP_FOR = 60 -- give up on a deferred answer after this
local OPTION_TYPES = { string = true, integer = true, number = true, boolean = true, user = true }
local BUTTON_STYLES = { primary = true, secondary = true, success = true, danger = true, link = true }

export type Option = {
	name: string,
	description: string?,
	type: string,
	required: boolean,
	choices: { { name: string, value: any } }?,
}
export type BotCommand = {
	name: string,
	description: string,
	args: { { name: string, description: string?, optional: boolean? } },
	options: { Option },
	botId: string,
	botName: string,
}
export type Message = {
	content: string?,
	embed: { [string]: any }?,
	components: { any }?,
	ephemeral: boolean?,
}

type Running = { id: string, module: ModuleScript, definition: { [string]: any } }
type BotIdentity = { id: string, name: string, avatar: string?, ownerId: number? }
type Interaction = {
	byId: number?,
	byName: string?,
	command: string?, -- "/name" shown above the answer
	conversation: string?,
	message: Instance?, -- the message whose button was clicked
}

local running: { [string]: Running } = {}
local started = false

-- Hooks into the chat window for messages that are never saved (a web bot's
-- ephemeral answers): set by the controller
Bots.ui = nil :: {
	showLocal: (entry: { [string]: any }) -> Instance?,
	removeLocal: (Instance) -> (),
	say: (text: string) -> (),
}?

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
	if type(json) ~= "string" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok then value else nil
end

-- An avatar only from Roblox's own content, so a manifest can't point anywhere else
local function safeAvatar(avatar: any): string?
	if type(avatar) == "string" and string.match(avatar, "^rbxassetid://%d+$") then
		return avatar
	elseif type(avatar) == "number" then
		return "rbxassetid://" .. tostring(math.floor(avatar))
	end
	return nil
end

local function say(text: string)
	if Bots.ui then
		Bots.ui.say(text)
	end
end

--------------------------------------------------------------------------------
-- Commands and options
--------------------------------------------------------------------------------

-- Options from a command definition: Discord-style `options`, or the older
-- `args` ({ name, description, optional }) as text options
local function optionsOf(command: { [string]: any }): { Option }
	local list = {}
	local source = if type(command.options) == "table" then command.options else command.args
	for _, raw in ipairs(if type(source) == "table" then source else {}) do
		if type(raw) == "table" and type(raw.name) == "string" then
			local optionType = if OPTION_TYPES[raw.type] then raw.type else "string"
			local choices = nil
			if type(raw.choices) == "table" then
				choices = {}
				for _, choice in ipairs(raw.choices) do
					if type(choice) == "table" and choice.name ~= nil then
						table.insert(choices, { name = tostring(choice.name), value = choice.value or choice.name })
					elseif type(choice) == "string" or type(choice) == "number" then
						table.insert(choices, { name = tostring(choice), value = choice })
					end
				end
			end
			table.insert(list, {
				name = cleanName(raw.name),
				description = if type(raw.description) == "string" then raw.description else nil,
				type = optionType,
				required = if raw.required ~= nil then raw.required == true else raw.optional ~= true,
				choices = choices,
			})
		end
	end
	return list
end

local function usageOf(name: string, options: { Option }): string
	local usage = "/" .. name
	for _, option in ipairs(options) do
		usage ..= if option.required then " <" .. option.name .. ">" else " [" .. option.name .. "]"
	end
	return usage
end

--[=[
	Reads what was typed after a command into its options' values (by name).
	Text options take one word, or the rest of the line when they're last.
	Returns the values, or nil and a message saying what's wrong.
]=]
function Bots.parseOptions(name: string, options: { Option }, args: { string }): ({ [string]: any }?, string?)
	local values = {}
	local position = 1
	for index, option in ipairs(options) do
		local raw: string? = args[position]
		if option.type == "string" and index == #options and raw then
			raw = table.concat(args, " ", position)
			position = #args + 1
		else
			position += 1
		end
		if raw == nil or raw == "" then
			if option.required then
				return nil, Language.t("bot.optionMissing", { option = option.name, usage = usageOf(name, options) })
			end
			continue
		end
		local text = raw :: string
		local value: any = text
		if option.choices then
			local found = nil
			for _, choice in ipairs(option.choices) do
				if
					string.lower(choice.name) == string.lower(text)
					or string.lower(tostring(choice.value)) == string.lower(text)
				then
					found = choice
				end
			end
			if not found then
				local names = {}
				for _, choice in ipairs(option.choices) do
					table.insert(names, choice.name)
				end
				return nil,
					Language.t("bot.optionChoice", { option = option.name, choices = table.concat(names, ", ") })
			end
			value = found.value
		elseif option.type == "integer" or option.type == "number" then
			value = tonumber(text)
			if value == nil or (option.type == "integer" and value % 1 ~= 0) then
				return nil, Language.t("bot.optionNumber", { option = option.name })
			end
		elseif option.type == "boolean" then
			local lowered = string.lower(text)
			if lowered == "true" or lowered == "yes" or lowered == "on" or lowered == "1" then
				value = true
			elseif lowered == "false" or lowered == "no" or lowered == "off" or lowered == "0" then
				value = false
			else
				return nil, Language.t("bot.optionBoolean", { option = option.name })
			end
		elseif option.type == "user" then
			local userId = AdminNetwork.resolveUserId((string.gsub(text, "^@", "")))
			if not userId then
				return nil, Language.t("bot.optionUser", { option = option.name, value = text })
			end
			value = { id = userId, name = AdminNetwork.getUsernameByUserId(userId) or (string.gsub(text, "^@", "")) }
		end
		values[option.name] = value
	end
	return values, nil
end

--------------------------------------------------------------------------------
-- Manifests
--------------------------------------------------------------------------------

--[=[
	Whether a bot (by its manifest folder) answers right now: web bots always
	(their server does), Studio bots while their owner is here.
]=]
function Bots.isOnline(manifest: Instance): boolean
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

local function identityOf(manifest: Instance): BotIdentity
	local data = decode(manifest:GetAttribute("Manifest")) or {}
	return {
		id = manifest.Name,
		name = manifest:GetAttribute("Name") or "Bot",
		avatar = safeAvatar(data.avatar),
		ownerId = manifest:GetAttribute("OwnerId"),
	}
end

--[=[
	Every bot in the place: { id, kind, name, ownerId, ownerName, online,
	disabled, avatar, description, commands, url }.
]=]
function Bots.list(): { { [string]: any } }
	local list = {}
	for _, manifest in ipairs(manifests():GetChildren()) do
		local data = decode(manifest:GetAttribute("Manifest")) or {}
		local commands = {}
		for _, command in ipairs(if type(data.commands) == "table" then data.commands else {}) do
			if type(command) == "table" and type(command.name) == "string" then
				table.insert(commands, {
					name = cleanName(command.name),
					description = if type(command.description) == "string" then command.description else "",
					options = optionsOf(command),
				})
			end
		end
		table.insert(list, {
			id = manifest.Name,
			kind = manifest:GetAttribute("Kind") or "studio",
			name = manifest:GetAttribute("Name") or "Bot",
			ownerId = manifest:GetAttribute("OwnerId"),
			ownerName = manifest:GetAttribute("OwnerName") or "?",
			online = Bots.isOnline(manifest),
			disabled = manifest:GetAttribute("Disabled") == true,
			avatar = safeAvatar(data.avatar),
			description = if type(data.description) == "string" then data.description else "",
			commands = commands,
			url = manifest:GetAttribute("Url"),
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
function Bots.mine(): { { [string]: any } }
	local mine = {}
	for _, bot in ipairs(Bots.list()) do
		if bot.ownerId == Identity.userId then
			table.insert(mine, bot)
		end
	end
	return mine
end

--[=[
	Every command the place's (enabled) bots offer.
]=]
function Bots.commands(): { BotCommand }
	local list = {}
	for _, bot in ipairs(Bots.list()) do
		if not bot.disabled then
			for _, command in ipairs(bot.commands) do
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

local function manifestOf(id: string): Instance?
	return manifests():FindFirstChild(id)
end

-- A Studio bot's manifest: only plain data (never functions)
local function publish(bot: Running)
	local definition = bot.definition
	local commands = {}
	for name, command in pairs(definition.commands or {}) do
		if type(command) == "table" and type(command.run) == "function" then
			table.insert(commands, {
				name = cleanName(tostring(name)),
				description = if type(command.description) == "string" then command.description else "",
				options = optionsOf(command),
			})
		end
	end
	table.sort(commands, function(a, b)
		return a.name < b.name
	end)
	local folder = manifestOf(bot.id)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = bot.id
		folder.Parent = manifests()
	end
	folder:SetAttribute("Kind", "studio")
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

--------------------------------------------------------------------------------
-- Bot messages
--------------------------------------------------------------------------------

-- Text, a card, or { content, embed, components, ephemeral }
local function normalize(message: any): Message
	if type(message) == "string" then
		return { content = message }
	elseif type(message) == "table" then
		if
			message.content == nil
			and message.embed == nil
			and message.components == nil
			and (message.title or message.fields or message.description)
		then
			return { embed = message } -- a card on its own
		end
		return {
			content = if message.content ~= nil then tostring(message.content) else nil,
			embed = if type(message.embed) == "table" then message.embed else nil,
			components = if type(message.components) == "table" then message.components else nil,
			ephemeral = message.ephemeral == true,
		}
	end
	return { content = tostring(message) }
end

local function encodeEmbed(embed: { [string]: any }?): string?
	if not embed then
		return nil
	end
	local copy = table.clone(embed)
	if typeof(copy.color) == "Color3" then
		copy.color = copy.color:ToHex()
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, copy)
	return if ok then json else nil
end

--[=[
	Buttons under a message, cleaned up: rows of up to 5 buttons, up to 5
	rows. A button is { label, style, customId, url, disabled }; a flat list
	of buttons is one row.
]=]
function Bots.cleanComponents(components: any): { { { [string]: any } } }?
	if type(components) ~= "table" or #components == 0 then
		return nil
	end
	local rows = if type(components[1]) == "table" and components[1].label ~= nil then { components } else components
	local clean = {}
	for _, row in ipairs(rows) do
		if type(row) == "table" and #clean < 5 then
			local buttons = {}
			for _, button in ipairs(row) do
				if type(button) == "table" and button.label ~= nil and #buttons < 5 then
					local style = if BUTTON_STYLES[button.style] then button.style else "secondary"
					local url = if type(button.url) == "string" and string.match(button.url, "^https://")
						then button.url
						else nil
					if url then
						style = "link"
					end
					table.insert(buttons, {
						label = string.sub(tostring(button.label), 1, 80),
						style = style,
						customId = if button.customId ~= nil
							then string.sub(tostring(button.customId), 1, 100)
							else nil,
						url = url,
						disabled = button.disabled == true,
					})
				end
			end
			if #buttons > 0 then
				table.insert(clean, buttons)
			end
		end
	end
	return if #clean > 0 then clean else nil
end

local function writeMessage(target: Instance, bot: BotIdentity, message: Message, interaction: Interaction?)
	target:SetAttribute("Sender", bot.name)
	target:SetAttribute("SenderId", 0)
	target:SetAttribute("BotId", bot.id)
	target:SetAttribute("BotOwner", bot.ownerId or 0)
	target:SetAttribute("BotAvatar", bot.avatar)
	target:SetAttribute("Content", message.content or "")
	target:SetAttribute("Embed", encodeEmbed(message.embed))
	local components = Bots.cleanComponents(message.components)
	target:SetAttribute("Components", if components then HttpService:JSONEncode(components) else nil)
	target:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_TEXT)
	if interaction and interaction.command then
		target:SetAttribute("SaidBy", interaction.byId)
		target:SetAttribute("SaidByName", interaction.byName)
		target:SetAttribute("Command", interaction.command)
	end
end

--[=[
	Saves a bot message in a conversation (everyone sees it, or only
	`visibleTo`). Returns it.
]=]
function Bots.post(
	bot: BotIdentity,
	message: Message,
	conversation: string?,
	interaction: Interaction?,
	options: { visibleTo: number?, thinking: boolean? }?
): Instance?
	local folder = Conversations.getFolder(conversation or Conversations.MAIN, true)
	if not folder then
		return nil
	end
	local saved = Instance.new("Folder")
	saved.Name = "bot_" .. TimeFormat.generateId()
	writeMessage(saved, bot, message, interaction)
	saved:SetAttribute("Timestamp", os.time())
	if options and options.visibleTo then
		saved:SetAttribute("VisibleTo", options.visibleTo)
	end
	if options and options.thinking then
		saved:SetAttribute("Thinking", true)
	end
	saved.Parent = folder
	ChatState.saveHistory()
	return saved
end

--[=[
	Changes a saved bot message in place (a deferred answer arriving, or a
	button's "update"). The chat re-draws it where it was.
]=]
function Bots.edit(saved: Instance, bot: BotIdentity, message: Message, interaction: Interaction?)
	writeMessage(saved, bot, message, interaction)
	saved:SetAttribute("Thinking", nil)
	saved:SetAttribute("Revision", (saved:GetAttribute("Revision") or 0) + 1)
	ChatState.saveHistory()
end

-- An answer that's never saved (a web bot's ephemeral answer): only in this chat
local function showLocal(bot: BotIdentity, message: Message, interaction: Interaction?, thinking: boolean?): Instance?
	if not Bots.ui then
		return nil
	end
	return Bots.ui.showLocal({
		botId = bot.id,
		botName = bot.name,
		botAvatar = bot.avatar,
		botOwner = bot.ownerId,
		content = message.content or "",
		embed = message.embed,
		components = Bots.cleanComponents(message.components),
		saidBy = interaction and interaction.byId,
		saidByName = interaction and interaction.byName,
		command = interaction and interaction.command,
		timestamp = os.time(),
		ephemeralLocal = true,
		thinking = thinking,
	})
end

--------------------------------------------------------------------------------
-- Studio bots (run in their owner's Studio)
--------------------------------------------------------------------------------

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

local function runningIdentity(bot: Running): BotIdentity
	return {
		id = bot.id,
		name = tostring(bot.definition.name or bot.module.Name),
		avatar = safeAvatar(bot.definition.avatar),
		ownerId = Identity.userId,
	}
end

-- What a Studio bot's functions get (see docs/BOTS.md)
local function makeContext(bot: Running, request: Instance?, conversation: string?)
	local identity = runningIdentity(bot)
	local ctx = {} :: { [string]: any }
	local interaction: Interaction? = nil
	ctx.bot = { id = bot.id, name = identity.name }
	ctx.conversation = conversation or Conversations.MAIN
	ctx.args = {}
	ctx.text = ""
	ctx.options = {}
	if request then
		ctx.user = { id = request:GetAttribute("ById"), name = request:GetAttribute("ByName") }
		ctx.command = request:GetAttribute("Command")
		ctx.customId = request:GetAttribute("CustomId")
		ctx.args = decode(request:GetAttribute("Args")) or {}
		ctx.text = table.concat(ctx.args, " ")
		interaction = {
			byId = ctx.user.id,
			byName = ctx.user.name,
			command = if ctx.command then "/" .. tostring(ctx.command) else nil,
		}
		local messageName = request:GetAttribute("MessageName")
		if messageName then
			local folder = Conversations.getFolder(ctx.conversation, false)
			ctx.message = folder and folder:FindFirstChild(messageName)
		end
	end
	local placeholder: Instance? = nil

	-- Answer: under "<name> used /command". Text, a card, or
	-- { content, embed, components, ephemeral = true }.
	function ctx.reply(message: any)
		local normalized = normalize(message)
		if placeholder and placeholder.Parent then
			Bots.edit(placeholder, identity, normalized, interaction)
			placeholder = nil
			return
		end
		Bots.post(identity, normalized, ctx.conversation, interaction, {
			visibleTo = if normalized.ephemeral and ctx.user then ctx.user.id else nil,
		})
	end
	-- "<bot> is thinking…" until ctx.reply: for answers that take a while
	function ctx.defer(options: { ephemeral: boolean? }?)
		if placeholder then
			return
		end
		placeholder = Bots.post(identity, { content = "" }, ctx.conversation, interaction, {
			visibleTo = if options and options.ephemeral and ctx.user then ctx.user.id else nil,
			thinking = true,
		})
	end
	-- After a button click: change the message the button is on
	function ctx.update(message: any)
		if ctx.message and ctx.message.Parent then
			Bots.edit(ctx.message, identity, normalize(message), nil)
		else
			ctx.reply(message)
		end
	end
	-- A message of the bot's own (not an answer)
	function ctx.send(message: any)
		Bots.post(identity, normalize(message), ctx.conversation, nil)
	end

	-- Web requests (HttpService:RequestAsync). Returns the response, or nil and an error.
	function ctx.http(options: { [string]: any }): ({ [string]: any }?, string?)
		local ok, response = pcall(HttpService.RequestAsync, HttpService, options)
		if not ok then
			return nil, tostring(response)
		end
		return response, nil
	end

	-- Roblox Open Cloud with the API key saved by /bot key. Returns the
	-- decoded JSON, or nil and an error.
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
		if not response.Success then
			return nil, string.format("%d %s", response.StatusCode, response.StatusMessage)
		end
		local data = decode(response.Body)
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

local function call(bot: Running, label: string, fn: (...any) -> (), ...: any): (boolean, any)
	local ok, err = pcall(fn, ...)
	if not ok then
		log.warn(string.format("Bot %s failed in %s: %s", tostring(bot.definition.name), label, tostring(err)))
	end
	return ok, err
end

-- An interaction for one of the bots running here
local function handle(request: Instance)
	local bot = running[request:GetAttribute("BotId") or ""]
	if not bot or request:GetAttribute("Handling") then
		return
	end
	local manifest = manifestOf(bot.id)
	if manifest and manifest:GetAttribute("Disabled") then
		request:Destroy()
		return
	end
	request:SetAttribute("Handling", true)
	local conversation = request:GetAttribute("Conversation")
	local ctx = makeContext(bot, request, conversation)

	if request:GetAttribute("Kind") == "button" then
		local handler = bot.definition.onButton
		if type(handler) == "function" then
			local ok, err = call(bot, "onButton", handler, ctx, ctx.customId)
			if not ok then
				ctx.reply({ content = "\u{26A0} " .. tostring(err), ephemeral = true })
			end
		end
		request:Destroy()
		return
	end

	local name = request:GetAttribute("Command")
	local command = nil
	for commandName, definition in pairs(bot.definition.commands or {}) do
		if cleanName(tostring(commandName)) == name and type(definition) == "table" then
			command = definition
		end
	end
	if command and type(command.run) == "function" then
		local values, problem = Bots.parseOptions(name, optionsOf(command), ctx.args)
		if not values then
			ctx.reply({ content = problem, ephemeral = true })
		else
			ctx.options = values
			local ok, err = call(bot, "/" .. tostring(name), command.run, ctx)
			if not ok then
				ctx.reply({ content = "\u{26A0} " .. tostring(err), ephemeral = true })
			end
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
	(Re)starts every Studio bot you own in this place. Returns their names.
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
	Makes a new Studio bot script owned by you (from the template).
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
	The script of one of your Studio bots (by its id), for opening it.
]=]
function Bots.scriptOf(id: string): ModuleScript?
	local folder = scripts(false)
	for _, module in ipairs(if folder then folder:GetChildren() else {}) do
		if module:IsA("ModuleScript") and module:GetAttribute("BotId") == id then
			return module
		end
	end
	return nil
end

local function canManage(manifest: Instance): boolean
	return manifest:GetAttribute("OwnerId") == Identity.userId or AdminNetwork.getMyRank() >= 2
end

--[=[
	Removes a bot you own (by script name or id; admins may remove any):
	its script and its manifest.
]=]
function Bots.remove(nameOrId: string): boolean
	local folder = scripts(false)
	local module = folder and folder:FindFirstChild(nameOrId)
	local id = if module then module:GetAttribute("BotId") else nameOrId
	local manifest = if type(id) == "string" then manifestOf(id) else nil
	if module then
		if module:GetAttribute("OwnerId") ~= Identity.userId and AdminNetwork.getMyRank() < 2 then
			return false
		end
		module:Destroy()
	elseif not manifest or not canManage(manifest) then
		return false
	end
	if manifest then
		manifest:Destroy()
	end
	Bots.reload()
	return true
end

--[=[
	Turns a bot off (or on again) for this place: owners and admins.
]=]
function Bots.setDisabled(id: string, disabled: boolean): boolean
	local manifest = manifestOf(id)
	if not manifest or not canManage(manifest) then
		return false
	end
	manifest:SetAttribute("Disabled", if disabled then true else nil)
	return true
end

--------------------------------------------------------------------------------
-- Web bots (an HTTP endpoint on the owner's server)
--------------------------------------------------------------------------------

local function newToken(): string
	return (string.gsub(HttpService:GenerateGUID(false) .. HttpService:GenerateGUID(false), "-", ""))
end

-- Web bots need HTTPS; plain HTTP only to this computer, for testing
local function validUrl(url: string): boolean
	return string.match(url, "^https://[%w%.%-]+") ~= nil
		or string.match(url, "^http://localhost[:/]") ~= nil
		or string.match(url, "^http://127%.0%.0%.1[:/]") ~= nil
end

--[=[
	Registers a web bot owned by you. Returns its id, or nil and a problem.
]=]
function Bots.createWeb(name: string, url: string): (string?, string?)
	if Identity.userId <= 0 then
		return nil, "signedOut"
	end
	if not validUrl(url) then
		return nil, "badUrl"
	end
	local id = HttpService:GenerateGUID(false)
	local folder = Instance.new("Folder")
	folder.Name = id
	folder:SetAttribute("Kind", "web")
	folder:SetAttribute("Name", name)
	folder:SetAttribute("Url", url)
	folder:SetAttribute("Token", newToken())
	folder:SetAttribute("OwnerId", Identity.userId)
	folder:SetAttribute("OwnerName", Identity.username)
	folder:SetAttribute("Manifest", HttpService:JSONEncode({ description = "", commands = {} }))
	folder.Parent = manifests()
	return id, nil
end

--[=[
	Changes a web bot's name, URL, description or avatar (yours only).
]=]
function Bots.updateWeb(
	id: string,
	fields: { name: string?, url: string?, description: string?, avatar: any? }
): boolean
	local manifest = manifestOf(id)
	if
		not manifest
		or manifest:GetAttribute("OwnerId") ~= Identity.userId
		or manifest:GetAttribute("Kind") ~= "web"
	then
		return false
	end
	if fields.url and not validUrl(fields.url) then
		return false
	end
	if fields.name and fields.name ~= "" then
		manifest:SetAttribute("Name", fields.name)
	end
	if fields.url then
		manifest:SetAttribute("Url", fields.url)
	end
	local data = decode(manifest:GetAttribute("Manifest")) or {}
	if fields.description ~= nil then
		data.description = fields.description
	end
	if fields.avatar ~= nil then
		data.avatar = safeAvatar(fields.avatar)
	end
	manifest:SetAttribute("Manifest", HttpService:JSONEncode(data))
	return true
end

--[=[
	A new token for one of your web bots (the old one stops working).
]=]
function Bots.regenerateToken(id: string): string?
	local manifest = manifestOf(id)
	if not manifest or manifest:GetAttribute("OwnerId") ~= Identity.userId then
		return nil
	end
	local token = newToken()
	manifest:SetAttribute("Token", token)
	return token
end

--[=[
	A web bot's token (owner only): the bot's server checks it on every request.
]=]
function Bots.tokenOf(id: string): string?
	local manifest = manifestOf(id)
	if manifest and manifest:GetAttribute("OwnerId") == Identity.userId then
		return manifest:GetAttribute("Token")
	end
	return nil
end

-- POSTs an interaction to a web bot. Returns the decoded answer, or nil and a problem.
local function callWeb(manifest: Instance, payload: { [string]: any }): (any, string?)
	local ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = manifest:GetAttribute("Url"),
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
			[Bots.TOKEN_HEADER] = manifest:GetAttribute("Token") or "",
		},
		Body = HttpService:JSONEncode(payload),
	})
	if not ok then
		return nil, tostring(response)
	end
	if not response.Success then
		return nil, string.format("%d %s", response.StatusCode, response.StatusMessage)
	end
	return decode(response.Body), nil
end

--[=[
	Asks a web bot for its name, description, avatar and commands (a "ping")
	and saves them. Returns the number of commands, or nil and a problem.
]=]
function Bots.syncWeb(id: string): (number?, string?)
	local manifest = manifestOf(id)
	if not manifest or manifest:GetAttribute("Kind") ~= "web" then
		return nil, "notFound"
	end
	local answer, problem = callWeb(manifest, { type = "ping", bot = { id = id } })
	if type(answer) ~= "table" or answer.type ~= "pong" then
		return nil, problem or "noPong"
	end
	local commands = {}
	for _, command in ipairs(if type(answer.commands) == "table" then answer.commands else {}) do
		if type(command) == "table" and type(command.name) == "string" then
			table.insert(commands, {
				name = cleanName(command.name),
				description = if type(command.description) == "string" then command.description else "",
				options = optionsOf(command),
			})
		end
	end
	local data = decode(manifest:GetAttribute("Manifest")) or {}
	data.commands = commands
	if type(answer.description) == "string" then
		data.description = answer.description
	end
	if answer.avatar ~= nil then
		data.avatar = safeAvatar(answer.avatar)
	end
	manifest:SetAttribute("Manifest", HttpService:JSONEncode(data))
	if type(answer.name) == "string" and answer.name ~= "" then
		manifest:SetAttribute("Name", answer.name)
	end
	return #commands, nil
end

-- What happens with a web bot's answer, here in the person's own Studio
local function applyWebAnswer(manifest: Instance, answer: any, interaction: Interaction, interactionId: string)
	local bot = identityOf(manifest)
	if type(answer) ~= "table" then
		return
	end
	local kind = answer.type or "message"
	if kind == "none" then
		return
	end
	if kind == "deferred" then
		local ephemeral = answer.ephemeral == true
		local placeholder = if ephemeral
			then showLocal(bot, { content = "" }, interaction, true)
			else Bots.post(bot, { content = "" }, interaction.conversation, interaction, { thinking = true })
		local deadline = os.clock() + FOLLOWUP_FOR
		while os.clock() < deadline do
			task.wait(FOLLOWUP_EVERY)
			local followup = callWeb(manifest, { type = "followup", id = interactionId })
			if type(followup) == "table" and (followup.type == "message" or followup.content or followup.embed) then
				local message = normalize(followup)
				if ephemeral then
					if placeholder and Bots.ui then
						Bots.ui.removeLocal(placeholder)
					end
					showLocal(bot, message, interaction)
				elseif placeholder then
					Bots.edit(placeholder, bot, message, interaction)
				end
				return
			end
		end
		if placeholder and placeholder.Parent then
			if ephemeral and Bots.ui then
				Bots.ui.removeLocal(placeholder)
			else
				placeholder:Destroy()
			end
		end
		say(Language.t("bot.noAnswer", { bot = bot.name }))
		return
	end
	local message = normalize(answer)
	if kind == "update" and interaction.message and interaction.message.Parent then
		if interaction.message:GetAttribute("BotId") then
			Bots.edit(interaction.message, bot, message, nil)
		elseif Bots.ui then
			-- An ephemeral message: show the new one instead
			Bots.ui.removeLocal(interaction.message)
			showLocal(bot, message, interaction)
		end
		return
	end
	if message.ephemeral then
		showLocal(bot, message, interaction)
	else
		Bots.post(bot, message, interaction.conversation, interaction)
	end
end

local function webInteraction(manifest: Instance, payload: { [string]: any }, interaction: Interaction)
	task.spawn(function()
		local id = HttpService:GenerateGUID(false)
		payload.id = id
		payload.bot = { id = manifest.Name }
		payload.user = { id = Identity.userId, name = Identity.username }
		payload.place = { id = game.PlaceId }
		payload.conversation = interaction.conversation
		local answer, problem = callWeb(manifest, payload)
		if answer == nil and problem then
			say(Language.t("bot.webError", { bot = manifest:GetAttribute("Name") or "Bot", error = problem }))
			return
		end
		applyWebAnswer(manifest, answer, interaction, id)
	end)
end

--------------------------------------------------------------------------------
-- Using bots
--------------------------------------------------------------------------------

--[=[
	Runs /name when a bot offers it. Returns true when a bot offers the
	command. `context` is the command context (Controllers/MessageController).
]=]
function Bots.tryCommand(name: string, args: { string }, context): boolean
	local lowered = string.lower(name)
	for _, manifest in ipairs(manifests():GetChildren()) do
		local data = decode(manifest:GetAttribute("Manifest")) or {}
		for _, command in ipairs(if type(data.commands) == "table" then data.commands else {}) do
			if type(command) == "table" and cleanName(tostring(command.name)) == lowered then
				local botName = manifest:GetAttribute("Name") or "Bot"
				if manifest:GetAttribute("Disabled") then
					context.addSystemMessage(Language.t("bot.disabled", { bot = botName }))
					return true
				end
				if not Bots.isOnline(manifest) then
					context.addSystemMessage(Language.t("bot.offline", {
						bot = botName,
						owner = manifest:GetAttribute("OwnerName") or "?",
					}))
					return true
				end
				-- Check the options here, so mistakes are told straight away
				local values, problem = Bots.parseOptions(lowered, optionsOf(command), args)
				if not values then
					context.addSystemMessage(problem)
					return true
				end
				local conversation = Conversations.getActiveId()
				if manifest:GetAttribute("Kind") == "web" then
					webInteraction(manifest, { type = "command", command = lowered, options = values, args = args }, {
						byId = Identity.userId,
						byName = Identity.username,
						command = "/" .. lowered,
						conversation = conversation,
					})
					return true
				end
				local request = Instance.new("Folder")
				request.Name = "request_" .. TimeFormat.generateId()
				request:SetAttribute("Kind", "command")
				request:SetAttribute("BotId", manifest.Name)
				request:SetAttribute("Command", lowered)
				request:SetAttribute("Args", HttpService:JSONEncode(args))
				request:SetAttribute("ById", Identity.userId)
				request:SetAttribute("ByName", Identity.username)
				request:SetAttribute("Conversation", conversation)
				request:SetAttribute("Timestamp", os.time())
				request.Parent = requests()
				return true
			end
		end
	end
	return false
end

--[=[
	A button under a bot message was clicked. info: { botId, customId,
	message (the saved message, or the chat's own ephemeral one),
	conversation }.
]=]
function Bots.clickButton(info: { botId: string, customId: string?, message: Instance?, conversation: string? })
	local manifest = manifestOf(info.botId)
	if not manifest or not info.customId then
		return
	end
	local botName = manifest:GetAttribute("Name") or "Bot"
	if not Bots.isOnline(manifest) then
		say(Language.t("bot.offline", { bot = botName, owner = manifest:GetAttribute("OwnerName") or "?" }))
		return
	end
	local conversation = info.conversation or Conversations.getActiveId()
	if manifest:GetAttribute("Kind") == "web" then
		webInteraction(manifest, {
			type = "button",
			customId = info.customId,
			message = if info.message
				then { id = info.message.Name, content = info.message:GetAttribute("Content") }
				else nil,
		}, {
			byId = Identity.userId,
			byName = Identity.username,
			conversation = conversation,
			message = info.message,
		})
		return
	end
	local request = Instance.new("Folder")
	request.Name = "request_" .. TimeFormat.generateId()
	request:SetAttribute("Kind", "button")
	request:SetAttribute("BotId", manifest.Name)
	request:SetAttribute("CustomId", info.customId)
	request:SetAttribute(
		"MessageName",
		if info.message and info.message:GetAttribute("BotId") then info.message.Name else nil
	)
	request:SetAttribute("ById", Identity.userId)
	request:SetAttribute("ByName", Identity.username)
	request:SetAttribute("Conversation", conversation)
	request:SetAttribute("Timestamp", os.time())
	request.Parent = requests()
end

--[=[
	Starts the Studio bots you own and listens for their interactions and
	the team chat's messages.
]=]
function Bots.init()
	if started then
		return
	end
	started = true
	Bots.reload()

	Lifetime.connect(requests().ChildAdded, function(request)
		task.defer(handle, request)
	end)
	for _, request in ipairs(requests():GetChildren()) do
		task.defer(handle, request)
	end

	-- onMessage: new team chat messages (not bots')
	Conversations.onMessage(function(id, message)
		if id ~= Conversations.MAIN or message:GetAttribute("BotId") or message:GetAttribute("Sender") == "System" then
			return
		end
		if os.time() - (message:GetAttribute("Timestamp") or 0) > 10 then
			return -- loading old messages, not new ones
		end
		for _, bot in pairs(running) do
			local manifest = manifestOf(bot.id)
			if
				type(bot.definition.onMessage) == "function" and not (manifest and manifest:GetAttribute("Disabled"))
			then
				task.spawn(call, bot, "onMessage", bot.definition.onMessage, makeContext(bot, nil, id), {
					text = message:GetAttribute("Content") or "",
					sender = message:GetAttribute("Sender"),
					senderId = message:GetAttribute("SenderId"),
					timestamp = message:GetAttribute("Timestamp"),
				})
			end
		end
	end)

	task.spawn(function()
		while Lifetime.alive do
			for id in pairs(running) do
				local manifest = manifestOf(id)
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
	options = {
		{ name = "name", description = "Who to greet", type = "string", required = false },
	},
	run = function(ctx)
		ctx.reply({
			content = "Hello, " .. (ctx.options.name or ctx.user.name) .. "!",
			components = {
				{ label = "Wave back", style = "primary", customId = "wave" },
			},
		})
	end,
}

-- Buttons under the bot's messages
function bot.onButton(ctx, customId)
	if customId == "wave" then
		ctx.reply({ content = ctx.user.name .. " waved \u{1F44B}", ephemeral = false })
	end
end

-- Optional: runs for every new message in the team chat
-- function bot.onMessage(ctx, message)
-- 	if message.text == "ping" then
-- 		ctx.send("pong")
-- 	end
-- end

return bot
]==]

return Bots
