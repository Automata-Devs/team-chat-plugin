--!strict
--[[
	Preferences

	Display preferences chosen in Settings that several UI modules read:
	which name to show, badges, badge tooltips, link previews, the typing
	indicator, spell check, animations and notifications. SettingsDialog loads and saves them; `changed` fires after one
	changes so the chat can re-render.

	Usage:
		if Preferences.values.badgeTooltips then ... end
		Preferences.set("names", "Username")
		Preferences.changed:Connect(function(key) ... end)
]]

local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)
local Signal = require(script.Parent.Parent.Parent.Util.Signal)

export type Names = "Display name" | "Username"

local Preferences = {}

Preferences.NAME_OPTIONS = { "Display name", "Username" }
Preferences.NOTIFICATION_OPTIONS = { "All", "DMs only", "Off" }

-- Defaults until load() reads the saved values
Preferences.values = {
	names = "Display name" :: Names, -- in DMs, the sidebar and message headers
	badges = true, -- bought and custom badges (verified always shows)
	badgeTooltips = true,
	linkPreviews = true,
	typingIndicator = true,
	spellCheck = true, -- red lines under misspelled words in the message box
	animations = true,
	notifications = "All", -- toasts for new messages: "All" | "DMs only" | "Off"
	notificationDuration = 5, -- seconds a toast stays
}

local KEYS = {
	names = Constants.SETTING_KEY_NAMES,
	badges = Constants.SETTING_KEY_SHOW_BADGES,
	badgeTooltips = Constants.SETTING_KEY_BADGE_TOOLTIPS,
	linkPreviews = Constants.SETTING_KEY_LINK_PREVIEWS,
	typingIndicator = Constants.SETTING_KEY_TYPING_INDICATOR,
	spellCheck = Constants.SETTING_KEY_SPELL_CHECK,
	animations = Constants.SETTING_KEY_ANIMATIONS,
	notifications = Constants.SETTING_KEY_NOTIFICATIONS,
	notificationDuration = Constants.SETTING_KEY_NOTIFICATION_DURATION,
}

Preferences.changed = Signal.new()

--[=[
	Loads the saved values (invalid ones keep the default).
]=]
function Preferences.load()
	local values = Preferences.values :: any
	for key, settingKey in pairs(KEYS) do
		local saved = Settings.get(settingKey)
		if key == "names" then
			if table.find(Preferences.NAME_OPTIONS, saved) then
				values.names = saved
			end
		elseif key == "notifications" then
			if table.find(Preferences.NOTIFICATION_OPTIONS, saved) then
				values.notifications = saved
			end
		elseif type(saved) == "boolean" or (type(saved) == "number" and type(values[key]) == "number") then
			values[key] = saved
		end
	end
end

--[=[
	Changes, saves and announces one preference.
]=]
function Preferences.set(key: string, value: any)
	local values = Preferences.values :: any
	if values[key] == value then
		return
	end
	values[key] = value
	if KEYS[key] then
		Settings.set(KEYS[key], value)
	end
	Preferences.changed:Fire(key)
end

--[=[
	The name to show for someone: their display name when that preference is
	on and it's known, otherwise their username.
]=]
function Preferences.nameFor(username: string, displayName: string?): string
	if Preferences.values.names == "Display name" and displayName and displayName ~= "" then
		return displayName
	end
	return username
end

return Preferences
