--!
-- PluginConfig
-- Central configuration for the TeamChat plugin.
-- Holds metadata, setting keys, and DataModel folder names so they
-- are defined in one place instead of scattered across modules.
--!

-- Read the PluginVersion StringValue at require-time. It sits next to `src`
-- in the plugin's own script (TeamChatPlugin > PluginVersion), wherever the
-- plugin lives (installed plugin, or the development copy in the place).
local pluginScript = script.Parent.Parent.Parent -- Config > src > TeamChatPlugin
local versionValue = pluginScript and pluginScript:GetAttribute("Version") or "Unknown"

local PluginConfig = {
	-- Metadata
	DEVELOPMENT_MODE = false,
	PLUGIN_VERSION = versionValue,
	PLUGIN_AUTHOR = "D3veloperHac",

	-- Plugin setting keys (persisted via plugin:SetSetting / GetSetting)
	-- History and version keys are per place: PlaceStorage.settingKey appends the PlaceId.
	SETTING_KEY_HISTORY = "TeamChatHistory_v2", -- local backup of the place's chat
	SETTING_KEY_ADMIN = "TeamChatAdmin_v1",
	SETTING_KEY_VERSIONS = "TeamChatVersions_v2",
	-- Pre-0.4 keys shared by every place; imported once into the first place opened
	SETTING_KEY_HISTORY_LEGACY = "TeamChatHistory_v1.1",
	SETTING_KEY_VERSIONS_LEGACY = "TeamChatVersions_v1",
	SETTING_KEY_LEGACY_MIGRATED = "TeamChatLegacyMigrated_v2", -- place key that received the legacy data
	SETTING_KEY_USAGE = "TeamChatUsage_v1", -- command / emoji usage counts (autocomplete ordering)
	SETTING_KEY_THEME = "TeamChatTheme_v1", -- UI theme preference (Auto / Light / Dark)
	SETTING_KEY_CLOCK = "TeamChatClock_v1", -- clock format preference (24h / 12h)
	SETTING_KEY_TIMESTAMPS = "TeamChatTimestamps_v1", -- show message timestamps (true / false)
	SETTING_KEY_ENTER_TO_SEND = "TeamChatEnterToSend_v1", -- Enter key sends the message (true / false)
	SETTING_KEY_TEXT_SIZE = "TeamChatTextSize_v1", -- message text size (Small / Default / Large)
	SETTING_KEY_LAST_SEEN_VERSION = "TeamChatLastSeenVersion_v1", -- version whose changelog was last shown

	-- DataModel folder names. Shared data lives in ServerStorage.<PLACE_DATA_FOLDER_NAME>
	-- (see Networking.PlaceStorage) so Team Create syncs it and it saves with the place.
	PLACE_DATA_FOLDER_NAME = "TeamChatData",
	CHAT_FOLDER_NAME = "_TeamChatData",
	ADMIN_FOLDER_NAME = "_TeamChatAdmin",
}

return PluginConfig