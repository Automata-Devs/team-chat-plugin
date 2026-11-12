--!strict
--[[
	Backend

	Settings for the Team Chat backend (backend/, docs/backend): the server
	every message is mirrored to, under each person's own account
	(Services/Backend).

	Usage:
		local BackendConfig = require(Config.Backend)
		task.wait(BackendConfig.FLUSH_EVERY)
]]

return {
	-- TeamChatData.<FOLDER_NAME>: the server's Url, and the place's WorkspaceId, ChannelId and Invite
	FOLDER_NAME = "Backend",
	API_PREFIX = "/api/v1",

	-- Plugin setting keys
	SETTING_KEY_SESSIONS = "TeamChatBackendSessions_v1", -- my sign-ins, per server (this computer only)
	SETTING_KEY_OUTBOX = "TeamChatBackendOutbox_v1", -- edits, deletes and reactions waiting (per place)
	SETTING_KEY_CHANNELS = "TeamChatBackendChannels_v1", -- conversation -> backend channel id (per place)

	-- Timing (seconds)
	FLUSH_EVERY = 5, -- send new messages and waiting changes
	RETRY_EVERY = 30, -- while the server can't be reached
	RESCAN_EVERY = 120, -- look again for my messages that aren't stored yet
	LOOKUP_RETRY = 300, -- before asking again for a teammate who hasn't signed in
	POLL_EVERY = 2, -- while waiting for the browser sign-in
	SIGN_IN_SECONDS = 600,

	-- Limits
	BATCH = 50, -- messages per upload
	OUTBOX_LIMIT = 1000,
	MAX_CONTENT = 4000, -- characters, as on the server
	MAX_CLIENT_DATA = 7000, -- bytes of JSON (the server takes 8 KB)
	RESTORE_PAGES = 100, -- of 100 messages
	SUPPRESS_NOTIFICATIONS = 4096, -- message flag for older messages stored later

	-- Admin and up connect the place and create its workspace
	MANAGE_RANK = 2,
}
