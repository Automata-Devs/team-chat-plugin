--!strict
--[[
	Logger

	Leveled logging for the plugin. Messages below Constants.LOG_LEVEL are
	dropped, so debug output stays out of users' Output window.

	  debug  -> print, only when LOG_LEVEL = "debug"
	  info   -> print
	  warn   -> warn (orange)
	  error  -> red error in Output without stopping the caller

	Usage:
		local log = Logger.scope("Attachments")
		log.warn("Could not upload %s", fileName)   -- [Team Chat/Attachments] Could not upload x.png
]]

local Constants = require(script.Parent.Parent.Config.Constants)

export type Level = "debug" | "info" | "warn" | "error"

export type ScopedLogger = {
	debug: (message: string, ...any) -> (),
	info: (message: string, ...any) -> (),
	warn: (message: string, ...any) -> (),
	error: (message: string, ...any) -> (),
}

local LEVEL_ORDER: { [Level]: number } = { debug = 1, info = 2, warn = 3, error = 4 }

local Logger = {}

local minimum = LEVEL_ORDER[Constants.LOG_LEVEL :: Level] or LEVEL_ORDER.info

local function format(message: string, ...: any): string
	if select("#", ...) == 0 then
		return message
	end
	local ok, formatted = pcall(string.format, message, ...)
	return if ok then formatted else message
end

local function emit(level: Level, scope: string?, message: string, ...: any)
	if LEVEL_ORDER[level] < minimum then
		return
	end
	local prefix = if scope
		then ("[%s/%s] "):format(Constants.LOG_PREFIX, scope)
		else ("[%s] "):format(Constants.LOG_PREFIX)
	local text = prefix .. format(message, ...)
	if level == "warn" then
		warn(text)
	elseif level == "error" then
		task.spawn(error, text, 0)
	else
		print(text)
	end
end

--[=[
	Changes the minimum level at runtime (e.g. from a debug command).
]=]
function Logger.setLevel(level: Level)
	minimum = LEVEL_ORDER[level] or minimum
end

--[=[
	Returns log functions that prefix every message with the scope name.
]=]
function Logger.scope(scope: string): ScopedLogger
	return {
		debug = function(message: string, ...: any)
			emit("debug", scope, message, ...)
		end,
		info = function(message: string, ...: any)
			emit("info", scope, message, ...)
		end,
		warn = function(message: string, ...: any)
			emit("warn", scope, message, ...)
		end,
		error = function(message: string, ...: any)
			emit("error", scope, message, ...)
		end,
	}
end

function Logger.debug(message: string, ...: any)
	emit("debug", nil, message, ...)
end

function Logger.info(message: string, ...: any)
	emit("info", nil, message, ...)
end

function Logger.warn(message: string, ...: any)
	emit("warn", nil, message, ...)
end

function Logger.error(message: string, ...: any)
	emit("error", nil, message, ...)
end

return Logger
