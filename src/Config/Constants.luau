--!strict
--[[
	Constants

	Plugin-wide configuration: metadata, logging, plugin setting keys,
	DataModel folder names and rank names. Change values here, not in the
	modules that use them.

	Usage:
		local Constants = require(Config.Constants)
		Settings.get(Constants.SETTING_KEY_THEME)
]]

-- The version is the `Version` attribute on the plugin's entry script
-- (src/init.meta.json), wherever the plugin lives (installed or in a place).
local pluginScript = script.Parent.Parent -- Config > TeamChatPlugin
local version = pluginScript:GetAttribute("Version")

local Constants = {
	-- Metadata
	DEVELOPMENT_MODE = false,
	PLUGIN_VERSION = if type(version) == "string" then version else "Unknown",
	PLUGIN_AUTHOR = "D3veloperHac",
	PLUGIN_TITLE = "Team Chat",

	-- Logging: "debug" | "info" | "warn" | "error" (see Core/Logger)
	LOG_LEVEL = "info",
	LOG_PREFIX = "Team Chat",

	-- Hovering this long shows a tooltip (seconds)
	TOOLTIP_DELAY = 0.3,

	-- Plugin setting keys (plugin:GetSetting/SetSetting via Core/Settings).
	-- Keys marked "per place" go through Settings.placeKey, which appends the PlaceId.
	SETTING_KEY_HISTORY = "TeamChatHistory_v2", -- per place: local backup of the team chat
	SETTING_KEY_ADMIN = "TeamChatAdmin_v1", -- ranks, mutes, bans, lists
	SETTING_KEY_VERSIONS = "TeamChatVersions_v2", -- per place: chat snapshot index
	SETTING_KEY_VERSION_CONTENT_PREFIX = "TeamChatVersion_", -- + snapshot id: snapshot contents
	SETTING_KEY_LAST_READ = "TeamChatLastRead_v1", -- per place: last read message per conversation
	SETTING_KEY_READ_SINCE = "TeamChatReadSince_v1", -- per place: first time the plugin ran there
	SETTING_KEY_CLOSED_DMS = "TeamChatClosedDms_v1", -- per place: DMs closed in the sidebar
	-- Pre-0.4 keys shared by every place; imported once into the first place opened
	SETTING_KEY_HISTORY_LEGACY = "TeamChatHistory_v1.1",
	SETTING_KEY_VERSIONS_LEGACY = "TeamChatVersions_v1",
	SETTING_KEY_LEGACY_MIGRATED = "TeamChatLegacyMigrated_v2", -- place key that received the legacy data
	SETTING_KEY_USAGE = "TeamChatUsage_v1", -- command / emoji usage counts (autocomplete order)
	SETTING_KEY_THEME = "TeamChatTheme_v1", -- "Auto" | "Light" | "Dark"
	SETTING_KEY_CLOCK = "TeamChatClock_v1", -- "24h" | "12h"
	SETTING_KEY_TIMESTAMPS = "TeamChatTimestamps_v1", -- show message times (boolean)
	SETTING_KEY_ENTER_TO_SEND = "TeamChatEnterToSend_v1", -- Enter sends (boolean)
	SETTING_KEY_TEXT_SIZE = "TeamChatTextSize_v1", -- "Small" | "Default" | "Large"
	SETTING_KEY_LAST_SEEN_VERSION = "TeamChatLastSeenVersion_v1", -- version whose What's New was shown
	SETTING_KEY_ABOUT_SEEN = "TeamChatAboutSeen_v1", -- About was shown on first install (boolean)
	SETTING_KEY_NAMES = "TeamChatNames_v1", -- "Display name" | "Username"
	SETTING_KEY_SHOW_BADGES = "TeamChatShowBadges_v1", -- bought/custom badges (boolean)
	SETTING_KEY_BADGE_TOOLTIPS = "TeamChatBadgeTooltips_v1", -- badge name on hover (boolean)
	SETTING_KEY_LINK_PREVIEWS = "TeamChatLinkPreviews_v1", -- link previews under messages (boolean)
	SETTING_KEY_TYPING_INDICATOR = "TeamChatTypingIndicator_v1", -- "x is typing" (boolean)
	SETTING_KEY_ANIMATIONS = "TeamChatAnimations_v1", -- UI animations (boolean)
	SETTING_KEY_NOTIFICATIONS = "TeamChatNotifications_v1", -- "All" | "DMs only" | "Off"
	SETTING_KEY_NOTIFICATION_DURATION = "TeamChatNotificationDuration_v1", -- seconds (number)
	SETTING_KEY_LANGUAGE = "TeamChatLanguage_v1", -- "auto" or a Config/Languages code
	SETTING_KEY_SPELL_CHECK = "TeamChatSpellCheck_v1", -- red lines under misspelled words (boolean)
	SETTING_KEY_DICTIONARY = "TeamChatDictionary_v1", -- words added to the spell check (JSON list)

	-- DataModel folders. Shared data lives in ServerStorage.<PLACE_DATA_FOLDER_NAME>
	-- (see Core/PlaceStorage) so Team Create syncs it and it saves with the place.
	PLACE_DATA_FOLDER_NAME = "TeamChatData",
	CHAT_FOLDER_NAME = "_TeamChatData",
	DM_FOLDER_NAME = "DirectMessages",
	TYPING_FOLDER_NAME = "TeamChatTyping",
	STUDIO_FOLDER_NAME = "_TeamChatStudio",

	-- Ranks (Services/Admin/Ranks); names are also shown by the UI
	RANK_NAMES = {
		[0] = "User",
		[1] = "Moderator",
		[2] = "Admin",
		[3] = "Owner",
	} :: { [number]: string },
}

return Constants
