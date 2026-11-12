--!strict
--[[
	Database

	Settings for the team database: Team Chat's own server, reached over
	HttpService (Services/Database, server/, docs/DATABASE.md).

	Usage:
		local DatabaseConfig = require(Config.Database)
		task.wait(DatabaseConfig.FLUSH_EVERY)
]]

return {
	-- TeamChatData.<FOLDER_NAME> holds the server's Url and Token attributes for the whole place
	FOLDER_NAME = "Database",
	TOKEN_HEADER = "X-TeamChat-Token",
	API_PREFIX = "/v1",

	-- Plugin setting keys (per place, through Settings.placeKey)
	SETTING_KEY_OUTBOX = "TeamChatDatabaseOutbox_v1", -- writes waiting for the server (JSON list)
	SETTING_KEY_CACHE = "TeamChatDatabaseCache_v1", -- last answers, for reading while offline (JSON)

	-- Timing (seconds)
	FLUSH_EVERY = 5, -- send queued archive messages and writes
	RETRY_EVERY = 30, -- while the server can't be reached
	PROFILE_SYNC_EVERY = 300, -- upload my profile

	-- Limits
	ARCHIVE_BATCH = 50, -- messages per upload
	OUTBOX_LIMIT = 500, -- queued writes kept while offline (oldest dropped first)
	CACHE_LIMIT = 200, -- cached answers
	MAX_KEY_LENGTH = 128,
	MAX_VALUE_BYTES = 64 * 1024,
	SEARCH_LIMIT = 10,

	-- Only the team chat is archived: DMs stay in the place, between the people in them
	ARCHIVED_CONVERSATIONS = { main = true } :: { [string]: boolean },

	-- Admin and up can connect the place to a server or disconnect it
	MANAGE_RANK = 2,
}
