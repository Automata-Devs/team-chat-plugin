--!strict
--[[
	Studio

	Studio bots: a ModuleScript in ServerStorage.TeamChatBots that runs only
	in its owner's Studio (nobody else's code runs on your computer). The
	owner's plugin publishes its manifest and answers the requests other
	plugins leave in TeamChatData.BotRequests.
]]

local HttpService = game:GetService("HttpService")

local Conversations = require(script.Parent.Parent.Chat.Conversations)
local Database = require(script.Parent.Parent.Database)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local Logger = require(script.Parent.Parent.Parent.Core.Logger)
local Manifests = require(script.Parent.Manifests)
local Messages = require(script.Parent.Messages)
local Options = require(script.Parent.Options)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)

local log = Logger.scope("Bots")

local HEARTBEAT = 10 -- seconds between "still online" marks
local REQUEST_TIMEOUT = 60 -- unanswered requests are cleaned up after this

type BotIdentity = Manifests.BotIdentity
type Interaction = Messages.Interaction
export type Running = { id: string, module: ModuleScript, definition: { [string]: any } }

local Studio = {}

Studio.API_KEY_SETTING = "TeamChatBotApiKey_v1" -- plugin setting (this computer only)
Studio.OPEN_CLOUD_URL = "https://apis.roblox.com"

local running: { [string]: Running } = {}

--[=[
	The API key bots use for Open Cloud, from this computer's plugin
	settings (nil when not set).
]=]
function Studio.apiKey(): string?
	local key = Settings.get(Studio.API_KEY_SETTING)
	return if type(key) == "string" and key ~= "" then key else nil
end

function Studio.setApiKey(key: string?)
	Settings.set(Studio.API_KEY_SETTING, key)
end

-- A Studio bot's manifest: only plain data (never functions)
local function publish(bot: Running)
	local definition = bot.definition
	local commands = {}
	for name, command in pairs(definition.commands or {}) do
		if type(command) == "table" and type(command.run) == "function" then
			table.insert(commands, {
				name = Options.cleanName(tostring(name)),
				description = if type(command.description) == "string" then command.description else "",
				options = Options.of(command),
			})
		end
	end
	table.sort(commands, function(a, b)
		return a.name < b.name
	end)
	local folder = Manifests.get(bot.id)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = bot.id
		folder.Parent = Manifests.folder()
	end
	folder:SetAttribute("Kind", "studio")
	folder:SetAttribute("Name", tostring(definition.name or bot.module.Name))
	folder:SetAttribute("OwnerId", Identity.userId)
	folder:SetAttribute("OwnerName", Identity.username)
	folder:SetAttribute(
		"Manifest",
		HttpService:JSONEncode({
			description = if type(definition.description) == "string" then definition.description else "",
			avatar = Manifests.safeAvatar(definition.avatar),
			commands = commands,
		})
	)
	folder:SetAttribute("LastSeen", os.time())
end

local function runningIdentity(bot: Running): BotIdentity
	local manifest = Manifests.get(bot.id)
	if manifest then
		return Manifests.identityOf(manifest)
	end
	return {
		id = bot.id,
		name = tostring(bot.definition.name or bot.module.Name),
		avatar = Manifests.safeAvatar(bot.definition.avatar),
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
		ctx.args = Manifests.decode(request:GetAttribute("Args")) or {}
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
		local normalized = Messages.normalize(message)
		if placeholder and placeholder.Parent then
			Messages.edit(placeholder, identity, normalized, interaction)
			placeholder = nil
			return
		end
		Messages.post(identity, normalized, ctx.conversation, interaction, {
			visibleTo = if normalized.ephemeral and ctx.user then ctx.user.id else nil,
		})
	end
	-- "<bot> is thinking…" until ctx.reply: for answers that take a while
	function ctx.defer(options: { ephemeral: boolean? }?)
		if placeholder then
			return
		end
		placeholder = Messages.post(identity, { content = "" }, ctx.conversation, interaction, {
			visibleTo = if options and options.ephemeral and ctx.user then ctx.user.id else nil,
			thinking = true,
		})
	end
	-- After a button click: change the message the button is on
	function ctx.update(message: any)
		if ctx.message and ctx.message.Parent then
			Messages.edit(ctx.message, identity, Messages.normalize(message), nil)
		else
			ctx.reply(message)
		end
	end
	-- A message of the bot's own (not an answer)
	function ctx.send(message: any)
		Messages.post(identity, Messages.normalize(message), ctx.conversation, nil)
	end

	-- Web Manifests.requests (HttpService:RequestAsync). Returns the response, or nil and an error.
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
		local key = Studio.apiKey()
		if not key then
			return nil, "No API key: the bot's owner can add one with /bot key <key>"
		end
		local response, err = ctx.http({
			Url = Studio.OPEN_CLOUD_URL .. path,
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
		local data = Manifests.decode(response.Body)
		return if data ~= nil then data else response.Body, nil
	end

	-- The bot's own collection in the team database (Services/Database, docs/DATABASE.md)
	ctx.db = Database.store("bot:" .. bot.id)

	ctx.json = {
		encode = function(value: any): string
			return HttpService:JSONEncode(value)
		end,
		decode = Manifests.decode,
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
	local manifest = Manifests.get(bot.id)
	if manifest and manifest:GetAttribute("Disabled") then
		request:Destroy()
		return
	end
	request:SetAttribute("Handling", true)
	local conversation = request:GetAttribute("Conversation")
	local ctx = makeContext(bot, request, conversation)
	local startedAt = os.clock()

	if request:GetAttribute("Kind") == "button" then
		local handler = bot.definition.onButton
		if type(handler) == "function" then
			local ok, err = call(bot, "onButton", handler, ctx, ctx.customId)
			if not ok then
				ctx.reply({ content = "\u{26A0} " .. tostring(err), ephemeral = true })
			end
			Manifests.record(manifest, {
				t = os.time(),
				kind = "button",
				name = ctx.customId,
				user = ctx.user and ctx.user.name,
				ok = ok,
				error = if ok then nil else tostring(err),
				ms = Manifests.elapsed(startedAt),
			})
		end
		request:Destroy()
		return
	end

	local name = request:GetAttribute("Command")
	local command = nil
	for commandName, definition in pairs(bot.definition.commands or {}) do
		if Options.cleanName(tostring(commandName)) == name and type(definition) == "table" then
			command = definition
		end
	end
	if command and type(command.run) == "function" then
		local values, problem = Options.parse(name, Options.of(command), ctx.args)
		if not values then
			ctx.reply({ content = problem, ephemeral = true })
		else
			ctx.options = values
			local ok, err = call(bot, "/" .. tostring(name), command.run, ctx)
			if not ok then
				ctx.reply({ content = "\u{26A0} " .. tostring(err), ephemeral = true })
			end
			Manifests.record(manifest, {
				t = os.time(),
				kind = "command",
				name = name,
				user = ctx.user and ctx.user.name,
				ok = ok,
				error = if ok then nil else tostring(err),
				ms = Manifests.elapsed(startedAt),
			})
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
function Studio.reload(): { string }
	running = {}
	local names = {}
	local folder = Manifests.scripts(false)
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
function Studio.create(name: string): (ModuleScript?, string?)
	if Identity.userId <= 0 then
		return nil, "signedOut"
	end
	local folder = Manifests.scripts(true) :: Folder
	if folder:FindFirstChild(name) then
		return nil, "exists"
	end
	local source = string.gsub(Studio.TEMPLATE, "{name}", name)
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
	Studio.reload()
	return module, nil
end

--[=[
	The script of one of your Studio bots (by its id), for opening it.
]=]
function Studio.scriptOf(id: string): ModuleScript?
	local folder = Manifests.scripts(false)
	for _, module in ipairs(if folder then folder:GetChildren() else {}) do
		if module:IsA("ModuleScript") and module:GetAttribute("BotId") == id then
			return module
		end
	end
	return nil
end

Studio.makeContext = makeContext
Studio.call = call

--[=[
	The Studio bots running here, by id.
]=]
function Studio.bots(): { [string]: Running }
	return running
end

--[=[
	Starts the bots you own and listens for their interactions and the
	team chat's messages.
]=]
function Studio.start()
	Studio.reload()

	Lifetime.connect(Manifests.requests().ChildAdded, function(request)
		task.defer(handle, request)
	end)
	for _, request in ipairs(Manifests.requests():GetChildren()) do
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
			local manifest = Manifests.get(bot.id)
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
				local manifest = Manifests.get(id)
				if manifest then
					manifest:SetAttribute("LastSeen", os.time())
				end
			end
			for _, request in ipairs(Manifests.requests():GetChildren()) do
				if os.time() - (request:GetAttribute("Timestamp") or 0) > REQUEST_TIMEOUT then
					request:Destroy()
				end
			end
			task.wait(HEARTBEAT)
		end
	end)
end

Studio.TEMPLATE = [==[
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

return Studio
