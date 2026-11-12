--!strict
--[[
	Portal

	What the developer portal does with your bots: their log and stats,
	editing how they show, running a command or button without posting
	(the test console) and health checks.
]]

local HttpService = game:GetService("HttpService")

local Conversations = require(script.Parent.Parent.Chat.Conversations)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Manifests = require(script.Parent.Manifests)
local Messages = require(script.Parent.Messages)
local Options = require(script.Parent.Options)
local Studio = require(script.Parent.Studio)
local Web = require(script.Parent.Web)

local TEST_WAIT = 30 -- seconds a test waits for a web bot's deferred answer

type LogEntry = Manifests.LogEntry
type Message = Messages.Message
type Running = Studio.Running

local Portal = {}

--[=[
	A bot's recent interactions, newest first: { t, kind, name, user, ok,
	error, ms, test }.
]=]
function Portal.logOf(id: string): { LogEntry }
	local manifest = Manifests.get(id)
	return if manifest then Manifests.decode(manifest:GetAttribute("Log")) or {} else {}
end

--[=[
	How a bot is used: { total, errors, averageMs, commands = { { name, count } } }
	(most used first). Tests and health checks don't count.
]=]
function Portal.statsOf(id: string): {
	total: number,
	errors: number,
	averageMs: number?,
	commands: { { name: string, count: number } },
}
	local manifest = Manifests.get(id)
	local stats = (manifest and Manifests.decode(manifest:GetAttribute("Stats"))) or {}
	local commands = {}
	for name, count in pairs(if type(stats.commands) == "table" then stats.commands else {}) do
		table.insert(commands, { name = tostring(name), count = tonumber(count) or 0 })
	end
	table.sort(commands, function(a, b)
		return if a.count ~= b.count then a.count > b.count else a.name < b.name
	end)
	local timed = tonumber(stats.timed) or 0
	return {
		total = tonumber(stats.total) or 0,
		errors = tonumber(stats.errors) or 0,
		averageMs = if timed > 0 then math.floor((tonumber(stats.ms) or 0) / timed + 0.5) else nil,
		commands = commands,
	}
end

--[=[
	Empties a bot's log and stats (yours only).
]=]
function Portal.clearLog(id: string): boolean
	local manifest = Manifests.get(id)
	if not manifest or manifest:GetAttribute("OwnerId") ~= Identity.userId then
		return false
	end
	manifest:SetAttribute("Log", nil)
	manifest:SetAttribute("Stats", nil)
	return true
end

--[=[
	Changes how one of your bots shows, over what its script or server says:
	{ name, description, avatar } ("" goes back to the bot's own),
	Manifests.disabledCommands (names nobody can use) and commandNotes (a description
	per command). Returns false for someone else's bot.
]=]
function Portal.editBot(
	id: string,
	fields: {
		name: string?,
		description: string?,
		avatar: string?,
		disabledCommands: { string }?,
		commandNotes: { [string]: string }?,
	}
): boolean
	local manifest = Manifests.get(id)
	if not manifest or manifest:GetAttribute("OwnerId") ~= Identity.userId then
		return false
	end
	local function set(attribute: string, value: string?)
		if value ~= nil then
			local trimmed = string.match(value, "^%s*(.-)%s*$") or ""
			manifest:SetAttribute(attribute, if trimmed ~= "" then trimmed else nil)
		end
	end
	set("CustomName", fields.name)
	set("CustomDescription", fields.description)
	if fields.avatar ~= nil then
		local avatar = string.match(fields.avatar, "^%s*(.-)%s*$") or ""
		-- A bare number is an image asset id
		if string.match(avatar, "^%d+$") then
			avatar = "rbxassetid://" .. avatar
		end
		manifest:SetAttribute("CustomAvatar", if avatar ~= "" then Manifests.safeAvatar(avatar) else nil)
	end
	if fields.disabledCommands then
		manifest:SetAttribute(
			"DisabledCommands",
			if #fields.disabledCommands > 0 then HttpService:JSONEncode(fields.disabledCommands) else nil
		)
	end
	if fields.commandNotes then
		local notes = {}
		local any = false
		for name, note in pairs(fields.commandNotes) do
			if type(note) == "string" and note ~= "" then
				notes[name] = note
				any = true
			end
		end
		manifest:SetAttribute("CommandNotes", if any then HttpService:JSONEncode(notes) else nil)
	end
	return true
end

export type TestResult = {
	ok: boolean,
	messages: { Message & { update: boolean? } }, -- what the bot answered (not posted)
	error: string?,
	ms: number,
}

-- A Studio bot's command or button, run here with its answers collected
local function testStudio(bot: Running, input: { command: string?, args: { string }?, button: string? }): TestResult
	local sink = {}
	local ctx = Studio.makeContext(bot, nil, Conversations.getActiveId())
	ctx.user = { id = Identity.userId, name = Identity.username }
	ctx.test = true
	ctx.reply = function(message: any)
		table.insert(sink, Messages.normalize(message))
	end
	ctx.send = ctx.reply
	ctx.defer = function() end
	ctx.update = function(message: any)
		local normalized: any = Messages.normalize(message)
		normalized.update = true
		table.insert(sink, normalized)
	end
	local startedAt = os.clock()
	if input.button then
		local handler = bot.definition.onButton
		if type(handler) ~= "function" then
			return { ok = false, messages = {}, error = "noButtons", ms = 0 }
		end
		ctx.customId = input.button
		local ok, err = pcall(handler, ctx, input.button)
		return { ok = ok, messages = sink, error = if ok then nil else tostring(err), ms = Manifests.elapsed(startedAt) }
	end
	local name = Options.cleanName(input.command or "")
	local command = nil
	for commandName, definition in pairs(bot.definition.commands or {}) do
		if Options.cleanName(tostring(commandName)) == name and type(definition) == "table" then
			command = definition
		end
	end
	if not command or type(command.run) ~= "function" then
		return { ok = false, messages = {}, error = "noCommand", ms = 0 }
	end
	ctx.command = name
	ctx.args = input.args or {}
	ctx.text = table.concat(ctx.args, " ")
	local values, problem = Options.parse(name, Options.of(command), ctx.args)
	if not values then
		return { ok = false, messages = {}, error = problem, ms = 0 }
	end
	ctx.options = values
	local ok, err = pcall(command.run, ctx)
	return { ok = ok, messages = sink, error = if ok then nil else tostring(err), ms = Manifests.elapsed(startedAt) }
end

-- A web bot's command or button, sent with test = true; the answer isn't posted
local function testWeb(manifest: Instance, input: { command: string?, args: { string }?, button: string? }): TestResult
	local id = HttpService:GenerateGUID(false)
	local payload: { [string]: any } = {
		type = if input.button then "button" else "command",
		id = id,
		test = true,
		bot = { id = manifest.Name },
		user = { id = Identity.userId, name = Identity.username },
		place = { id = game.PlaceId },
		conversation = Conversations.getActiveId(),
	}
	if input.button then
		payload.customId = input.button
	else
		local name = Options.cleanName(input.command or "")
		local options = {}
		local data = Manifests.decode(manifest:GetAttribute("Manifest")) or {}
		for _, command in ipairs(if type(data.commands) == "table" then data.commands else {}) do
			if type(command) == "table" and Options.cleanName(tostring(command.name)) == name then
				options = Options.of(command)
			end
		end
		local values, problem = Options.parse(name, options, input.args or {})
		if not values then
			return { ok = false, messages = {}, error = problem, ms = 0 }
		end
		payload.command = name
		payload.options = values
		payload.args = input.args or {}
	end
	local startedAt = os.clock()
	local answer, problem = Web.call(manifest, payload)
	if answer == nil and problem then
		return { ok = false, messages = {}, error = problem, ms = Manifests.elapsed(startedAt) }
	end
	if type(answer) == "table" and answer.type == "deferred" then
		local deadline = os.clock() + TEST_WAIT
		answer = nil
		while os.clock() < deadline do
			task.wait(Web.FOLLOWUP_EVERY)
			local followup = Web.call(manifest, { type = "followup", id = id, test = true })
			if type(followup) == "table" and (followup.type == "message" or followup.content or followup.embed) then
				answer = followup
				break
			end
		end
		if not answer then
			return { ok = false, messages = {}, error = "noAnswer", ms = Manifests.elapsed(startedAt) }
		end
	end
	local messages = {}
	if type(answer) == "table" and answer.type ~= "none" then
		local message: any = Messages.normalize(answer)
		message.update = answer.type == "update"
		table.insert(messages, message)
	end
	return { ok = true, messages = messages, ms = Manifests.elapsed(startedAt) }
end

--[=[
	Runs one of your bots' commands ({ command, args }) or a button click
	({ button = customId }) without posting anything: the answers come back
	for the portal's test console. A Studio bot has to be Studio.bots() here.
	Yields (a web bot is called).
]=]
function Portal.test(id: string, input: { command: string?, args: { string }?, button: string? }): TestResult
	local manifest = Manifests.get(id)
	if not manifest then
		return { ok = false, messages = {}, error = "notFound", ms = 0 }
	end
	local result
	if manifest:GetAttribute("Kind") == "web" then
		result = testWeb(manifest, input)
	else
		local bot = Studio.bots()[id]
		if not bot then
			return { ok = false, messages = {}, error = "notRunning", ms = 0 }
		end
		result = testStudio(bot, input)
	end
	Manifests.record(manifest, {
		t = os.time(),
		kind = if input.button then "button" else "command",
		name = input.button or input.command,
		user = Identity.username,
		ok = result.ok,
		error = result.error,
		ms = result.ms,
		test = true,
	})
	return result
end

--[=[
	Checks a bot: a web bot is pinged (timed), a Studio bot is online when
	its owner's plugin marked it lately. Saves and returns { ok, ms, error }.
	Yields for web bots.
]=]
function Portal.checkHealth(id: string): { ok: boolean, ms: number?, error: string? }
	local manifest = Manifests.get(id)
	if not manifest then
		return { ok = false, error = "notFound" }
	end
	local result: { ok: boolean, ms: number?, error: string? }
	if manifest:GetAttribute("Kind") == "web" then
		local startedAt = os.clock()
		local answer, problem = Web.call(manifest, { type = "ping", bot = { id = id } })
		local ok = type(answer) == "table" and answer.type == "pong"
		result = { ok = ok, ms = Manifests.elapsed(startedAt), error = if ok then nil else problem or "noPong" }
	else
		local online = Manifests.isOnline(manifest)
		result = { ok = online, error = if online then nil else "offline" }
	end
	manifest:SetAttribute("HealthTime", os.time())
	manifest:SetAttribute("HealthOk", result.ok)
	manifest:SetAttribute("HealthMs", result.ms)
	manifest:SetAttribute("HealthError", result.error)
	Manifests.record(manifest, { t = os.time(), kind = "ping", ok = result.ok, error = result.error, ms = result.ms })
	return result
end

return Portal
