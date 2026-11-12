--!strict
--[[
	Options

	A bot command's options, Discord-style: typed (string, integer, number,
	boolean, user), required or not, with optional choices. Reads them from
	a command definition and parses what was typed after the command.
]]

local AdminNetwork = require(script.Parent.Parent.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

local OPTION_TYPES = { string = true, integer = true, number = true, boolean = true, user = true }

export type Option = {
	name: string,
	description: string?,
	type: string,
	required: boolean,
	choices: { { name: string, value: any } }?,
}

local Options = {}

-- Command and option names: lower case letters, digits and _
function Options.cleanName(name: string): string
	return (string.gsub(string.lower(name), "[^%w_]", ""))
end

-- Options from a command definition: Discord-style `options`, or the older
-- `args` ({ name, description, optional }) as text options
function Options.of(command: { [string]: any }): { Option }
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
				name = Options.cleanName(raw.name),
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
function Options.parse(name: string, options: { Option }, args: { string }): ({ [string]: any }?, string?)
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

return Options
