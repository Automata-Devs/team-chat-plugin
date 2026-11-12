--!strict
--[[
	Web

	Web bots: a URL on the owner's own server (any language), like Discord's
	HTTP interactions. Whoever uses a command, their plugin POSTs the
	interaction to the URL (with the bot's token) and shows the answer, so
	web bots work while their owner is offline.
]]

local HttpService = game:GetService("HttpService")

local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Manifests = require(script.Parent.Manifests)
local Messages = require(script.Parent.Messages)
local Options = require(script.Parent.Options)

type Interaction = Messages.Interaction

local Web = {}

Web.TOKEN_HEADER = "X-TeamChat-Token"
Web.FOLLOWUP_EVERY = 2 -- seconds between asking a web bot for its deferred answer
local FOLLOWUP_FOR = 60 -- give up on a deferred answer after this

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
function Web.create(name: string, url: string): (string?, string?)
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
	folder.Parent = Manifests.folder()
	return id, nil
end

--[=[
	Changes a web bot's name, URL, description or avatar (yours only).
]=]
function Web.update(id: string, fields: { name: string?, url: string?, description: string?, avatar: any? }): boolean
	local manifest = Manifests.get(id)
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
	local data = Manifests.decode(manifest:GetAttribute("Manifest")) or {}
	if fields.description ~= nil then
		data.description = fields.description
	end
	if fields.avatar ~= nil then
		data.avatar = Manifests.safeAvatar(fields.avatar)
	end
	manifest:SetAttribute("Manifest", HttpService:JSONEncode(data))
	return true
end

--[=[
	A new token for one of your web bots (the old one stops working).
]=]
function Web.regenerateToken(id: string): string?
	local manifest = Manifests.get(id)
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
function Web.tokenOf(id: string): string?
	local manifest = Manifests.get(id)
	if manifest and manifest:GetAttribute("OwnerId") == Identity.userId then
		return manifest:GetAttribute("Token")
	end
	return nil
end

-- POSTs an interaction to a web bot. Returns the decoded answer, or nil and a problem.
function Web.call(manifest: Instance, payload: { [string]: any }): (any, string?)
	local ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = manifest:GetAttribute("Url"),
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
			[Web.TOKEN_HEADER] = manifest:GetAttribute("Token") or "",
		},
		Body = HttpService:JSONEncode(payload),
	})
	if not ok then
		return nil, tostring(response)
	end
	if not response.Success then
		return nil, string.format("%d %s", response.StatusCode, response.StatusMessage)
	end
	return Manifests.decode(response.Body), nil
end

--[=[
	Asks a web bot for its name, description, avatar and commands (a "ping")
	and saves them. Returns the number of commands, or nil and a problem.
]=]
function Web.sync(id: string): (number?, string?)
	local manifest = Manifests.get(id)
	if not manifest or manifest:GetAttribute("Kind") ~= "web" then
		return nil, "notFound"
	end
	local answer, problem = Web.call(manifest, { type = "ping", bot = { id = id } })
	if type(answer) ~= "table" or answer.type ~= "pong" then
		return nil, problem or "noPong"
	end
	local commands = {}
	for _, command in ipairs(if type(answer.commands) == "table" then answer.commands else {}) do
		if type(command) == "table" and type(command.name) == "string" then
			table.insert(commands, {
				name = Options.cleanName(command.name),
				description = if type(command.description) == "string" then command.description else "",
				options = Options.of(command),
			})
		end
	end
	local data = Manifests.decode(manifest:GetAttribute("Manifest")) or {}
	data.commands = commands
	if type(answer.description) == "string" then
		data.description = answer.description
	end
	if answer.avatar ~= nil then
		data.avatar = Manifests.safeAvatar(answer.avatar)
	end
	manifest:SetAttribute("Manifest", HttpService:JSONEncode(data))
	if type(answer.name) == "string" and answer.name ~= "" then
		manifest:SetAttribute("Name", answer.name)
	end
	return #commands, nil
end

-- What happens with a web bot's answer, here in the person's own Studio
local function applyWebAnswer(manifest: Instance, answer: any, interaction: Interaction, interactionId: string)
	local bot = Manifests.identityOf(manifest)
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
			then Messages.showLocal(bot, { content = "" }, interaction, true)
			else Messages.post(bot, { content = "" }, interaction.conversation, interaction, { thinking = true })
		local deadline = os.clock() + FOLLOWUP_FOR
		while os.clock() < deadline do
			task.wait(Web.FOLLOWUP_EVERY)
			local followup = Web.call(manifest, { type = "followup", id = interactionId })
			if type(followup) == "table" and (followup.type == "message" or followup.content or followup.embed) then
				local message = Messages.normalize(followup)
				if ephemeral then
					if placeholder and Messages.ui then
						Messages.ui.removeLocal(placeholder)
					end
					Messages.showLocal(bot, message, interaction)
				elseif placeholder then
					Messages.edit(placeholder, bot, message, interaction)
				end
				return
			end
		end
		if placeholder and placeholder.Parent then
			if ephemeral and Messages.ui then
				Messages.ui.removeLocal(placeholder)
			else
				placeholder:Destroy()
			end
		end
		Messages.say(Language.t("bot.noAnswer", { bot = bot.name }))
		return
	end
	local message = Messages.normalize(answer)
	if kind == "update" and interaction.message and interaction.message.Parent then
		if interaction.message:GetAttribute("BotId") then
			Messages.edit(interaction.message, bot, message, nil)
		elseif Messages.ui then
			-- An ephemeral message: show the new one instead
			Messages.ui.removeLocal(interaction.message)
			Messages.showLocal(bot, message, interaction)
		end
		return
	end
	if message.ephemeral then
		Messages.showLocal(bot, message, interaction)
	else
		Messages.post(bot, message, interaction.conversation, interaction)
	end
end

function Web.interact(manifest: Instance, payload: { [string]: any }, interaction: Interaction)
	task.spawn(function()
		local id = HttpService:GenerateGUID(false)
		payload.id = id
		payload.test = false -- the portal's test console sends true
		payload.bot = { id = manifest.Name }
		payload.user = { id = Identity.userId, name = Identity.username }
		payload.place = { id = game.PlaceId }
		payload.conversation = interaction.conversation
		local startedAt = os.clock()
		local answer, problem = Web.call(manifest, payload)
		Manifests.record(manifest, {
			t = os.time(),
			kind = payload.type,
			name = payload.command or payload.customId,
			user = Identity.username,
			ok = not (answer == nil and problem),
			error = if answer == nil then problem else nil,
			ms = Manifests.elapsed(startedAt),
		})
		if answer == nil and problem then
			Messages.say(Language.t("bot.webError", { bot = manifest:GetAttribute("Name") or "Bot", error = problem }))
			return
		end
		applyWebAnswer(manifest, answer, interaction, id)
	end)
end

return Web
