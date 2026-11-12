--[[
	Registry

	Auto-discovers command modules from src/Commands and its subfolders.
	Each command module returns a table following the template format:
	  { Name, Aliases, Prefixes, Enabled, Rank, RankLock, Loopable, Tags, Description, Contributors, Args, Function }
	Commands with Enabled = false are not registered: they are hidden from /help
	and autocomplete, and typing one reports that it is disabled. A missing
	Enabled field counts as enabled.
]]

local AdminNetwork = require(script.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Core.Language)
local UsageTracker = require(script.Parent.Parent.Services.Usage)
local Bots = require(script.Parent.Parent.Services.Bots)

local CommandHandler = {}

local commands = {} -- [lowercaseName] = commandModule
local commandOrder = {} -- ordered list of canonical names
local disabledCommands = {} -- [lowercaseName or alias] = command module with Enabled = false

-- A command's description in the current language: "command.<name>.description"
-- in Config/Languages, or the module's own English Description.
local function describe(cmdModule): string
	return Language.tOr("command." .. string.lower(cmdModule.Name) .. ".description", cmdModule.Description or "")
end

-- A rank's name in the current language ("rank.<n>").
local function rankName(rank: number): string
	return Language.tOr("rank." .. tostring(rank), AdminNetwork.getRankName(rank))
end

-- A command's arguments as { name, description, optional }. Args entries are
-- tables ({ name = "user", description = "...", optional = true }) or, in the
-- older style, strings: "<name>" is required, "[name]" optional.
local function normalizeArgs(cmdModule)
	local list = {}
	for _, arg in ipairs(cmdModule.Args or {}) do
		if type(arg) == "table" and type(arg.name) == "string" then
			table.insert(list, {
				name = arg.name,
				description = Language.tOr(
					"command." .. string.lower(cmdModule.Name) .. ".arg." .. arg.name,
					arg.description or ""
				),
				optional = arg.optional == true,
			})
		elseif type(arg) == "string" then
			local optional = string.sub(arg, 1, 1) == "["
			table.insert(list, {
				name = (string.gsub(arg, "^[<%[](.-)[>%]]$", "%1")),
				description = "",
				optional = optional,
			})
		end
	end
	return list
end

-- "/ban <user> [reason]"
local function usageOf(cmdModule): string
	local parts = { "/" .. cmdModule.Name }
	for _, arg in ipairs(normalizeArgs(cmdModule)) do
		table.insert(parts, if arg.optional then "[" .. arg.name .. "]" else "<" .. arg.name .. ">")
	end
	return table.concat(parts, " ")
end

-- Registers a single command module into the registry.
local function registerCommand(cmdModule)
	if not cmdModule or not cmdModule.Name or not cmdModule.Function then
		return
	end

	if cmdModule.Enabled == false then
		disabledCommands[cmdModule.Name:lower()] = cmdModule
		for _, alias in ipairs(cmdModule.Aliases or {}) do
			disabledCommands[alias:lower()] = cmdModule
		end
		return
	end

	local name = cmdModule.Name:lower()
	commands[name] = cmdModule
	table.insert(commandOrder, name)

	-- Register aliases
	if cmdModule.Aliases then
		for _, alias in ipairs(cmdModule.Aliases) do
			commands[alias:lower()] = cmdModule
		end
	end
end

-- Recursively scans a folder for ModuleScripts and registers them.
local function scanFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		-- Modules starting with "_" (like _Template) aren't commands.
		if child:IsA("ModuleScript") and string.sub(child.Name, 1, 1) ~= "_" then
			local ok, cmdModule = pcall(function()
				return require(child)
			end)
			if ok and cmdModule and type(cmdModule) == "table" and cmdModule.Name and cmdModule.Function then
				registerCommand(cmdModule)
			end
		elseif child:IsA("Folder") then
			scanFolder(child)
		end
	end
end

--[=[
	Initializes the CommandHandler by scanning the Commands folder.
]=]
function CommandHandler.init()
	local commandsFolder = script.Parent
	if commandsFolder then
		scanFolder(commandsFolder)
	end

	-- Register built-in help command
	registerCommand({
		Name = "help",
		Aliases = { "?" },
		Prefixes = { "/" },
		Enabled = true,
		Rank = 0,
		Tags = { "Utility" },
		Description = "Show available commands or details about a specific command",
		Args = { { name = "command", description = "Command to explain", optional = true } },
		Function = function(_speaker, args, ctx)
			if #args > 0 then
				local cmdName = args[1]:lower()
				local cmd = commands[cmdName]
				if not cmd then
					local disabled = disabledCommands[cmdName]
					ctx.addSystemMessage(
						if disabled
							then Language.t("commands.disabled", { name = disabled.Name })
							else Language.t("commands.unknownShort", { name = args[1] })
					)
					return
				end
				local fields = {}
				if cmd.Args and #cmd.Args > 0 then
					table.insert(fields, { name = Language.t("embed.help.usage"), value = usageOf(cmd) })
					for _, arg in ipairs(normalizeArgs(cmd)) do
						table.insert(fields, {
							name = arg.name
								.. (if arg.optional then " (" .. Language.t("embed.help.optional") .. ")" else ""),
							value = if arg.description ~= "" then arg.description else "-",
							inline = true,
						})
					end
				end
				if cmd.Aliases and #cmd.Aliases > 0 then
					table.insert(fields, {
						name = Language.t("embed.help.aliases"),
						value = "/" .. table.concat(cmd.Aliases, ", /"),
						inline = true,
					})
				end
				if cmd.Rank and cmd.Rank > 0 then
					table.insert(
						fields,
						{ name = Language.t("embed.help.rank"), value = rankName(cmd.Rank), inline = true }
					)
				end
				ctx.addEmbed({ title = "/" .. cmd.Name, description = describe(cmd), fields = fields })
				return
			end

			local groups, groupOrder = {}, {}
			for _, name in ipairs(commandOrder) do
				local cmd = commands[name]
				local tag = (cmd.Tags and cmd.Tags[1]) or "Other"
				if not groups[tag] then
					groups[tag] = {}
					table.insert(groupOrder, tag)
				end
				table.insert(groups[tag], "/" .. cmd.Name)
			end
			for _, botCommand in ipairs(Bots.commands()) do
				if not commands[botCommand.name] then
					local tag = "Bots"
					if not groups[tag] then
						groups[tag] = {}
						table.insert(groupOrder, tag)
					end
					table.insert(groups[tag], "/" .. botCommand.name)
				end
			end
			local fields = {}
			for _, tag in ipairs(groupOrder) do
				table.insert(fields, {
					name = Language.tOr("commandGroup." .. string.lower(tag), tag),
					value = table.concat(groups[tag], "  "),
				})
			end
			ctx.addEmbed({
				title = Language.t("commands.available"),
				fields = fields,
				footer = Language.t("commands.moreDetails"),
			})
		end,
	})
end
--[=[
	Parses a raw text string and, if it starts with "/", runs the matching command
	after checking rank permissions via AdminNetwork.
	text: The raw message text
	context: Table of context functions
	Returns boolean true if a command was executed, false if not a command
]=]
function CommandHandler.tryParse(text, context)
	if text == "" or #text < 2 then
		return false
	end

	local prefix = text:sub(1, 1)
	if prefix ~= "/" then
		return false
	end

	-- Split into command name and args
	local parts = {}
	for word in text:gmatch("%S+") do
		table.insert(parts, word)
	end
	if #parts == 0 then
		return false
	end

	local rawCmd = parts[1]:sub(2) -- remove prefix
	local cmdName = rawCmd:lower()
	local args = {}
	for i = 2, #parts do
		table.insert(args, parts[i])
	end

	local cmd = commands[cmdName]
	if not cmd and context and context.addSystemMessage and Bots.tryCommand(cmdName, args, context) then
		return true -- a user-made bot offers it (Services/Bots)
	end
	if not cmd then
		if context and context.addSystemMessage then
			local disabled = disabledCommands[cmdName]
			if disabled then
				context.addSystemMessage(Language.t("commands.disabled", { name = disabled.Name }))
			else
				context.addSystemMessage(Language.t("commands.unknown", { name = rawCmd }))
			end
		end
		return true
	end

	-- Rank check
	local myRank = AdminNetwork.getMyRank()
	local requiredRank = cmd.Rank or 0
	if myRank < requiredRank then
		if context and context.addSystemMessage then
			context.addSystemMessage(
				Language.t("commands.noPermission", { name = cmd.Name, rank = rankName(requiredRank) })
			)
		end
		return true
	end

	-- Build speaker info
	local speaker = {
		userId = AdminNetwork.getUserId(),
		username = AdminNetwork.getUsername(),
		name = AdminNetwork.getUsername(),
		rank = myRank,
	}

	-- Count this as a use so the autocomplete menu can list it higher next time.
	-- (Recorded by canonical name, so aliases count towards the same command.)
	UsageTracker.record("command", cmd.Name:lower())

	if context then
		context.command = "/" .. cmd.Name -- shown as "<you> used /name" on public replies
	end
	local ok, err = pcall(cmd.Function, speaker, args, context)
	if not ok then
		if context and context.addSystemMessage then
			context.addSystemMessage(Language.t("commands.error", { name = cmd.Name, error = tostring(err) }))
		end
	end
	return true
end

--[=[
	Returns a list of all registered command names.
]=]
function CommandHandler.getCommandNames()
	local names = {}
	for _, name in ipairs(commandOrder) do
		table.insert(names, name)
	end
	return names
end

--[=[
	Returns a list of all registered commands with metadata for autocomplete,
	sorted by how often the local user has used them (most used first).
	Commands with the same usage count are sorted alphabetically.
	Returns array of { name, description, rank, aliases, uses, args, usage }
	(args: { name, description, optional }, see normalizeArgs)
]=]
function CommandHandler.getCommandList()
	local list = {}
	local seen = {}
	for _, name in ipairs(commandOrder) do
		if not seen[name] then
			seen[name] = true
			local cmd = commands[name]
			table.insert(list, {
				name = cmd.Name,
				description = describe(cmd),
				rank = cmd.Rank or 0,
				aliases = cmd.Aliases or {},
				uses = UsageTracker.getCount("command", cmd.Name:lower()),
				args = normalizeArgs(cmd),
				usage = usageOf(cmd),
			})
		end
	end

	-- Commands from user-made bots (built-in names win)
	for _, botCommand in ipairs(Bots.commands()) do
		if not seen[botCommand.name] and not commands[botCommand.name] then
			seen[botCommand.name] = true
			local usage = "/" .. botCommand.name
			for _, arg in ipairs(botCommand.args) do
				usage ..= if arg.optional then " [" .. arg.name .. "]" else " <" .. arg.name .. ">"
			end
			table.insert(list, {
				name = botCommand.name,
				description = botCommand.description .. "  \u{00B7}  " .. botCommand.botName,
				rank = 0,
				aliases = {},
				uses = UsageTracker.getCount("command", botCommand.name),
				args = (function()
					-- Say what kind of value each option takes ("number", "user", ...)
					local args = {}
					for _, arg in ipairs(botCommand.args) do
						local copy = table.clone(arg)
						if arg.type and arg.type ~= "string" then
							copy.description = (arg.description or "") .. "  \u{00B7}  " .. arg.type
						end
						table.insert(args, copy)
					end
					return args
				end)(),
				usage = usage,
			})
		end
	end

	table.sort(list, function(a, b)
		if a.uses ~= b.uses then
			return a.uses > b.uses
		end
		return a.name:lower() < b.name:lower()
	end)

	return list
end

return CommandHandler
