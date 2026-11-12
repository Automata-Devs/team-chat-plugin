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

	For the developer portal: Bots.test (run a command or button without
	posting), Bots.logOf / Bots.statsOf (recent interactions and use per
	command, kept on the manifest), Bots.editBot (name, description, avatar
	and commands set in the portal, over what the script or server says) and
	Bots.checkHealth.
]]

local HttpService = game:GetService("HttpService")

local AdminNetwork = require(script.Parent.Admin)
local Conversations = require(script.Parent.Chat.Conversations)
local Identity = require(script.Parent.Parent.Core.Identity)
local Language = require(script.Parent.Parent.Core.Language)
local Manifests = require(script.Manifests)
local Messages = require(script.Messages)
local Options = require(script.Options)
local Portal = require(script.Portal)
local Studio = require(script.Studio)
local TimeFormat = require(script.Parent.Parent.Util.TimeFormat)
local Web = require(script.Web)

export type Option = Options.Option
export type BotCommand = Manifests.BotCommand
export type Message = Messages.Message
export type TestResult = Portal.TestResult

local Bots = {}

Bots.SCRIPTS_FOLDER = Manifests.SCRIPTS_FOLDER
Bots.MANIFESTS_FOLDER = Manifests.MANIFESTS_FOLDER
Bots.REQUESTS_FOLDER = Manifests.REQUESTS_FOLDER
Bots.API_KEY_SETTING = Studio.API_KEY_SETTING
Bots.OPEN_CLOUD_URL = Studio.OPEN_CLOUD_URL
Bots.TOKEN_HEADER = Web.TOKEN_HEADER
Bots.TEMPLATE = Studio.TEMPLATE

Bots.parseOptions = Options.parse
Bots.isOnline = Manifests.isOnline
Bots.list = Manifests.list
Bots.mine = Manifests.mine
Bots.commands = Manifests.commands
Bots.cleanComponents = Messages.cleanComponents
Bots.post = Messages.post
Bots.edit = Messages.edit
Bots.apiKey = Studio.apiKey
Bots.setApiKey = Studio.setApiKey
Bots.reload = Studio.reload
Bots.create = Studio.create
Bots.scriptOf = Studio.scriptOf
Bots.createWeb = Web.create
Bots.updateWeb = Web.update
Bots.regenerateToken = Web.regenerateToken
Bots.tokenOf = Web.tokenOf
Bots.syncWeb = Web.sync
Bots.logOf = Portal.logOf
Bots.statsOf = Portal.statsOf
Bots.clearLog = Portal.clearLog
Bots.editBot = Portal.editBot
Bots.test = Portal.test
Bots.checkHealth = Portal.checkHealth

local started = false

--[=[
	Sets the chat window hooks for messages that are never saved (a web
	bot's ephemeral answers): { showLocal, removeLocal, say }.
]=]
function Bots.setUi(ui)
	Messages.ui = ui
end

local function canManage(manifest: Instance): boolean
	return manifest:GetAttribute("OwnerId") == Identity.userId or AdminNetwork.getMyRank() >= 2
end

--[=[
	Removes a bot you own (by script name or id; admins may remove any):
	its script and its manifest.
]=]
function Bots.remove(nameOrId: string): boolean
	local folder = Manifests.scripts(false)
	local module = folder and folder:FindFirstChild(nameOrId)
	local id = if module then module:GetAttribute("BotId") else nameOrId
	local manifest = if type(id) == "string" then Manifests.get(id) else nil
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
	Studio.reload()
	return true
end

--[=[
	Turns a bot off (or on again) for this place: owners and admins.
]=]
function Bots.setDisabled(id: string, disabled: boolean): boolean
	local manifest = Manifests.get(id)
	if not manifest or not canManage(manifest) then
		return false
	end
	manifest:SetAttribute("Disabled", if disabled then true else nil)
	return true
end

--[=[
	Runs /name when a bot offers it. Returns true when a bot offers the
	command. `context` is the command context (Controllers/MessageController).
]=]
function Bots.tryCommand(name: string, args: { string }, context): boolean
	local lowered = string.lower(name)
	for _, manifest in ipairs(Manifests.folder():GetChildren()) do
		local data = Manifests.decode(manifest:GetAttribute("Manifest")) or {}
		for _, command in ipairs(if type(data.commands) == "table" then data.commands else {}) do
			if
				type(command) == "table"
				and Options.cleanName(tostring(command.name)) == lowered
				and not Manifests.disabledCommands(manifest)[lowered]
			then
				local botName = Manifests.nameOf(manifest)
				if manifest:GetAttribute("Disabled") then
					context.addSystemMessage(Language.t("bot.disabled", { bot = botName }))
					return true
				end
				if not Manifests.isOnline(manifest) then
					context.addSystemMessage(Language.t("bot.offline", {
						bot = botName,
						owner = manifest:GetAttribute("OwnerName") or "?",
					}))
					return true
				end
				-- Check the options here, so mistakes are told straight away
				local values, problem = Options.parse(lowered, Options.of(command), args)
				if not values then
					context.addSystemMessage(problem)
					return true
				end
				local conversation = Conversations.getActiveId()
				if manifest:GetAttribute("Kind") == "web" then
					Web.interact(manifest, { type = "command", command = lowered, options = values, args = args }, {
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
				request.Parent = Manifests.requests()
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
	local manifest = Manifests.get(info.botId)
	if not manifest or not info.customId then
		return
	end
	local botName = manifest:GetAttribute("Name") or "Bot"
	if not Manifests.isOnline(manifest) then
		Messages.say(Language.t("bot.offline", { bot = botName, owner = manifest:GetAttribute("OwnerName") or "?" }))
		return
	end
	local conversation = info.conversation or Conversations.getActiveId()
	if manifest:GetAttribute("Kind") == "web" then
		Web.interact(manifest, {
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
	request.Parent = Manifests.requests()
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
	Studio.start()
end

return Bots
