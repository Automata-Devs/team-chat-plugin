--!strict
--[[
	Language

	Translations for the plugin's interface. Every language is one module in
	Config/Languages (en.luau, nl.luau, ...), found automatically: to add a
	language, copy en.luau, translate its strings and give it a new code.
	English is the fallback for any key a language doesn't have.

	The chosen language ("auto" follows Studio's own language) is saved in
	plugin settings. Changing it re-labels everything bound with bind()
	right away, and fires `changed` for text that's built by code.

	Usage:
		Language.init()                                  -- after Settings.init
		Language.t("menu.reply")                         -- "Reply" / "Beantwoorden"
		Language.t("composer.placeholderDm", { name = "builderman" })
		Language.bind(label, "Text", "empty.title")      -- kept up to date
		Language.set("nl")                               -- or "auto"
		Language.changed:Connect(function() ... end)
]]

local LocalizationService = game:GetService("LocalizationService")

local Constants = require(script.Parent.Parent.Config.Constants)
local Settings = require(script.Parent.Settings)
local Signal = require(script.Parent.Parent.Util.Signal)

export type LanguageInfo = {
	code: string, -- "en", "nl", ...
	name: string, -- in the language itself: "Nederlands"
	englishName: string, -- "Dutch"
	strings: { [string]: string },
}

local Language = {}

Language.AUTO = "auto"
Language.FALLBACK = "en"
Language.changed = Signal.new()

local languages: { [string]: LanguageInfo } = {}
local choice = Language.AUTO -- what's saved: "auto" or a code
local current = Language.FALLBACK -- the language in use

-- Every language module in Config/Languages
local function discover()
	local folder = script.Parent.Parent.Config:FindFirstChild("Languages")
	for _, module in ipairs(folder and folder:GetChildren() or {}) do
		if module:IsA("ModuleScript") then
			local ok, info = pcall(require, module)
			if ok and type(info) == "table" and type(info.code) == "string" and type(info.strings) == "table" then
				languages[info.code] = info :: any
			end
		end
	end
end
discover()

-- Studio's language ("nl-nl" -> "nl"), when we have it
local function studioLanguage(): string
	local ok, locale = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	if ok and type(locale) == "string" then
		local lowered = string.lower(locale)
		if languages[lowered] then
			return lowered
		end
		local base = string.match(lowered, "^(%a+)")
		if base and languages[base] then
			return base
		end
	end
	return Language.FALLBACK
end

local function resolve(code: string): string
	if code == Language.AUTO then
		return studioLanguage()
	end
	return if languages[code] then code else Language.FALLBACK
end

--[=[
	The languages there are, sorted by their English name (English first).
]=]
function Language.list(): { LanguageInfo }
	local list = {}
	for _, info in pairs(languages) do
		table.insert(list, info)
	end
	table.sort(list, function(a, b)
		if a.code == Language.FALLBACK then
			return true
		elseif b.code == Language.FALLBACK then
			return false
		end
		return a.englishName < b.englishName
	end)
	return list
end

--[=[
	The saved choice ("auto" or a code) and the language in use.
]=]
function Language.getChoice(): string
	return choice
end
function Language.current(): string
	return current
end

--[=[
	The text for `key` in the current language (English when it's missing
	there, the key itself when English lacks it too), with {name} style
	placeholders filled from `vars`.
]=]
function Language.t(key: string, vars: { [string]: any }?): string
	local info = languages[current]
	local text = info and info.strings[key]
	if text == nil then
		local fallback = languages[Language.FALLBACK]
		text = fallback and fallback.strings[key]
	end
	if text == nil then
		return key
	end
	if vars then
		text = string.gsub(text, "{(%w+)}", function(name)
			local value = vars[name]
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	end
	return text
end

--[=[
	Like t(), but returns `default` when no language (English included) has
	the key: for text that has its own English source, like a command's
	description or a badge's name in Config/Badges.
]=]
function Language.tOr(key: string, default: string, vars: { [string]: any }?): string
	local text = Language.t(key, vars)
	return if text == key then default else text
end

--[=[
	Text that carries its own translations, like a What's New note: a plain
	string, or { en = "...", nl = "...", ... }. Gives the current language's
	text, else English.
]=]
function Language.pick(value: string | { [string]: string }?): string
	if type(value) == "table" then
		return value[Language.current()] or value.en or ""
	end
	return value or ""
end

-- Bound properties, kept up to date when the language changes
local bindings: { [Instance]: { [string]: { key: string, vars: { [string]: any }?, transform: ((string) -> string)? } } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

--[=[
	Sets instance[property] to the text for `key` now and whenever the
	language changes. `transform` adjusts it (e.g. string.upper).
]=]
function Language.bind(
	instance: Instance,
	property: string,
	key: string,
	vars: { [string]: any }?,
	transform: ((string) -> string)?
)
	local perInstance = bindings[instance]
	if not perInstance then
		perInstance = {}
		bindings[instance] = perInstance
	end
	perInstance[property] = { key = key, vars = vars, transform = transform }
	local text = Language.t(key, vars);
	(instance :: any)[property] = if transform then transform(text) else text
end

local function applyBindings()
	for instance, properties in pairs(bindings) do
		for property, binding in pairs(properties) do
			local text = Language.t(binding.key, binding.vars)
			pcall(function()
				(instance :: any)[property] = if binding.transform then binding.transform(text) else text
			end)
		end
	end
end

--[=[
	Switches language ("auto" or a code), saves the choice and re-labels.
]=]
function Language.set(code: string)
	if code ~= Language.AUTO and not languages[code] then
		return
	end
	choice = code
	Settings.set(Constants.SETTING_KEY_LANGUAGE, code)
	local resolved = resolve(code)
	if resolved ~= current then
		current = resolved
		applyBindings()
		Language.changed:Fire(current)
	end
end

--[=[
	Loads the saved choice. Call once after Settings.init.
]=]
function Language.init()
	local saved = Settings.get(Constants.SETTING_KEY_LANGUAGE)
	choice = if type(saved) == "string" and (saved == Language.AUTO or languages[saved]) then saved else Language.AUTO
	current = resolve(choice)
end

return Language
