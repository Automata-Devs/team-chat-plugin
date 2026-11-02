--!
-- CommandHandler
-- Auto-discovers command modules from src/Commands and its subfolders.
-- Each command module returns a table following the template format:
--   { Name, Aliases, Prefixes, Enabled, Rank, RankLock, Loopable, Tags, Description, Contributors, Args, Function }
-- Commands with Enabled = false are not registered: they are hidden from /help
-- and autocomplete, and typing one reports that it is disabled. A missing
-- Enabled field counts as enabled.
--!

local AdminNetwork = require(script.Parent.Parent.Networking.AdminNetwork)
local UsageTracker = require(script.Parent.Parent.Utils.UsageTracker)

local CommandHandler = {}

local commands = {} -- [lowercaseName] = commandModule
local commandOrder = {} -- ordered list of canonical names
local disabledCommands = {} -- [lowercaseName or alias] = command module with Enabled = false

--!
-- Registers a single command module into the registry.
--!
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

--!
-- Recursively scans a folder for ModuleScripts and registers them.
--!
local function scanFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		-- The starter template has a placeholder Function, but isn't an actual command.
		if child:IsA("ModuleScript") and child.Name:lower() ~= "template" then
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

--!
-- Initializes the CommandHandler by scanning the Commands folder.
--!
function CommandHandler.init()
	local commandsFolder = script.Parent
	if commandsFolder then
		scanFolder(commandsFolder)
	end

	-- Register built-in help command
	registerCommand({
		Name = "help",
		Aliases = {"?"},
		Prefixes = {"/"},
		Enabled = true,
		Rank = 0,
		Description = "Show available commands or details about a specific command",
		Args = {"[command]"},
		Function = function(speaker, args, ctx)
			if #args > 0 then
				local cmdName = args[1]:lower()
				local cmd = commands[cmdName]
				if not cmd then
					local disabled = disabledCommands[cmdName]
					ctx.addSystemMessage(if disabled then "/" .. disabled.Name .. " is currently disabled" else "Unknown command: /" .. args[1])
					return
				end
				ctx.addSystemMessage("/" .. cmd.Name .. " - " .. (cmd.Description or ""))
				if cmd.Args and #cmd.Args > 0 then
					ctx.addSystemMessage("Usage: /" .. cmd.Name .. " " .. table.concat(cmd.Args, " "))
				end
				if cmd.Aliases and #cmd.Aliases > 0 then
					ctx.addSystemMessage("Aliases: " .. table.concat(cmd.Aliases, ", "))
				end
				return
			end

			ctx.addSystemMessage("Available commands:")
			for _, name in ipairs(commandOrder) do
				local cmd = commands[name]
				local rankTag = ""
				if cmd.Rank and cmd.Rank > 0 then
					rankTag = " [" .. AdminNetwork.getRankName(cmd.Rank) .. "]"
				end
				ctx.addSystemMessage("  /" .. cmd.Name .. rankTag .. " - " .. (cmd.Description or ""))
			end
			ctx.addSystemMessage("Type /help <command> for more details.")
		end,
	})
end
--!
-- Parses a raw text string and, if it starts with "/", runs the matching command
-- after checking rank permissions via AdminNetwork.
-- @param text The raw message text
-- @param context Table of context functions
-- @return boolean true if a command was executed, false if not a command
--!
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
	if not cmd then
		if context and context.addSystemMessage then
			local disabled = disabledCommands[cmdName]
			if disabled then
				context.addSystemMessage("/" .. disabled.Name .. " is currently disabled")
			else
				context.addSystemMessage("Unknown command: /" .. rawCmd .. " - type /help for a list of commands")
			end
		end
		return true
	end

	-- Rank check
	local myRank = AdminNetwork.getMyRank()
	local requiredRank = cmd.Rank or 0
	if myRank < requiredRank then
		if context and context.addSystemMessage then
			context.addSystemMessage("You don't have permission to use /" .. cmd.Name .. " (requires " .. AdminNetwork.getRankName(requiredRank) .. ")")
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

	local ok, err = pcall(cmd.Function, speaker, args, context)
	if not ok then
		if context and context.addSystemMessage then
			context.addSystemMessage("Error running /" .. cmd.Name .. ": " .. tostring(err))
		end
	end
	return true
end

--!
-- Returns a list of all registered command names.
--!
function CommandHandler.getCommandNames()
	local names = {}
	for _, name in ipairs(commandOrder) do
		table.insert(names, name)
	end
	return names
end

--!
-- Returns a list of all registered commands with metadata for autocomplete,
-- sorted by how often the local user has used them (most used first).
-- Commands with the same usage count are sorted alphabetically.
-- Returns array of { name, description, rank, aliases, uses }
--!
function CommandHandler.getCommandList()
	local list = {}
	local seen = {}
	for _, name in ipairs(commandOrder) do
		if not seen[name] then
			seen[name] = true
			local cmd = commands[name]
			table.insert(list, {
				name = cmd.Name,
				description = cmd.Description or "",
				rank = cmd.Rank or 0,
				aliases = cmd.Aliases or {},
				uses = UsageTracker.getCount("command", cmd.Name:lower()),
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
