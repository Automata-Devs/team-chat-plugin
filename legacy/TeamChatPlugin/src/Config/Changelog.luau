 --!
-- Changelog
-- What's new, ONE ENTRY PER DAY, newest first. Shown in the "What's New"
-- modal: automatically once after an update, and any time from the gift
-- button in the chat header.
--
-- To add an update: bump the plugin's Version attribute, then
--   - same day as the top entry: set its version to the new one and add
--     your changes to its list (merge or reword older lines as you like);
--   - new day: add a new entry at the TOP of the list:
--
--   {
--       version = "1.0.0",              -- must match the Version attribute exactly
--       date = "01/01/1999",            -- MM-DD-YYYY
--       title = "Short headline",       -- optional
--       changes = {
--           { type = "added",   text = "A new feature." },
--           { type = "changed", text = "Something that works differently." },
--           { type = "fixed",   text = "A bug that was fixed." },
--           { type = "removed", text = "Something that is gone." },
--       },
--   },
--
-- Change types follow Keep a Changelog (https://keepachangelog.com).
-- Only big updates get an entry; small version bumps don't, and What's New
-- then keeps showing the last big update.
--!

-- UNRELEASED: every change since the last published entry (bugs, fixes,
-- tweaks), newest first, tagged with the version it went into. Not shown in
-- What's New. When something big ships, move these lines into a new entry at
-- the top of the list below and empty this list.
local unreleased = {}
local _ = unreleased

return {
	{
		version = "1.5.0",
		date = "01/11/2026",
		title = "Direct messages & friends",
		changes = {
			{ type = "added", text = "Direct messages! A Discord-style sidebar with this game's team chat pinned at the top and a DM for every collaborator." },
			{ type = "added", text = "The sidebar shows avatars, a green dot for who's online, and red badges for unread messages in DMs and the team chat." },
			{ type = "added", text = "When the panel is wide, the sidebar shows names and each conversation's latest message; the toggle at its bottom expands or collapses it." },
			{ type = "added", text = "Everything works in DMs: replies, images, files, polls and deleting." },
			{ type = "added", text = "New message: the + in the sidebar lets you DM any of your Roblox friends (with search) or anyone by username. They see it when they open this place with Team Chat." },
			{ type = "added", text = "Friends are marked in your DMs." },
			{ type = "added", text = "Close a DM with the × that shows when you hover it. It comes back when they message you again or you start it again; no messages are deleted." },
			{ type = "added", text = "Games without their own icon get a tile with their initials; your game's icon shows as soon as you set one." },
			{ type = "changed", text = "/whisper sends a real direct message instead of a message everyone could see." },
		},
	},
	{
		version = "1.2.5",
		date = "01/11/2026",
		title = "Audio, GIFs and new file cards",
		changes = {
			{ type = "added", text = "Audio files play right in the chat: play/pause, a waveform that fills as it plays, the playback time, and click the waveform to skip." },
			{ type = "added", text = "Only you hear the audio you play; nothing is sent to anyone else." },
			{ type = "added", text = "Only one audio clip plays at a time: starting one pauses the other." },
			{ type = "added", text = "Animated GIFs: attach a .gif and everyone in the chat sees it move." },
			{ type = "added", text = "Long GIFs are trimmed to 48 frames but keep their total length; if a GIF can't be uploaded, only you can see it." },
			{ type = "changed", text = "Redesigned file cards: a colored icon per file type, the file extension and a \"local only\" tag under the name, and a compact download button." },
			{ type = "changed", text = "File and audio cards have properly rounded borders and follow the light and dark themes." },
			{ type = "changed", text = "File and audio cards stay between 100 and 250 pixels wide instead of stretching across the chat." },
			{ type = "changed", text = "Videos get a file card. For videos uploaded to Roblox, its button opens the video's page in your browser." },
			{ type = "changed", text = "What's New is shorter: one entry per day instead of one per small update." },
			{ type = "changed", text = "Small updates are now collected here and only published with the next big update." },
			{ type = "removed", text = "The in-chat video player: Studio can't show video inside plugins, so it only showed a black screen." },
			{ type = "removed", text = "The Output warning when a version has no changelog entry." },
			{ type = "fixed", text = "The version number in the header and the What's New popup work again." },
		},
	},
	{
		version = "1.0.10",
		date = "31/10/2026",
		title = "Official release!",
		changes = {
			{ type = "added", text = "Roblox's Builder icons throughout the chat: the empty chat, the send button, menus, modals and file cards." },
			{ type = "added", text = "Roblox's Builder fonts, with Builder Extended for titles and Builder Mono for times, numbers and commands." },
			{ type = "added", text = "A header with the plugin name, the version number, a What's New button and a Settings button." },
			{ type = "added", text = "What's New: this changelog pops up once after each update and can be opened any time from the header." },
			{ type = "added", text = "Icons next to the titles of the Settings, Poll and What's New windows." },
			{ type = "added", text = "Chat history is saved in each place and shared with Team Create collaborators, with a local backup of each place's chat." },
			{ type = "added", text = "Polls can have up to 10 answers." },
			{ type = "added", text = "Click a reply to jump to the original message, which flashes so you can spot it." },
			{ type = "added", text = "Commands can be turned off with Enabled = false." },
			{ type = "added", text = "If a link can't be opened, it's copied to your clipboard so you can paste it." },
			{ type = "changed", text = "New reply design: a reply icon with the username at half opacity." },
			{ type = "changed", text = "The right-click menu opens next to your cursor and has icons and a red Delete option." },
			{ type = "changed", text = "The plus menu looks like the right-click menu." },
			{ type = "changed", text = "Menus and windows close when you click outside them, even elsewhere in Studio." },
			{ type = "changed", text = "Windows scroll when they're taller than the panel, and Settings dims the chat behind it like the other windows." },
			{ type = "changed", text = "The two required poll answers no longer have a remove button." },
			{ type = "changed", text = "Link previews are a compact card with the site's name, a short address and an open arrow; they highlight softly on hover." },
			{ type = "changed", text = "Redesigned command and emoji suggestions: a title, icons, names with descriptions, rank badges and a hint." },
			{ type = "changed", text = "Hover over a suggestion to highlight it, then press Tab or click to pick it; suggestions close when you click outside the chat." },
			{ type = "changed", text = "Long messages wrap while you type and the message box grows to show every line." },
			{ type = "changed", text = "For multi-line messages, set Settings > Send Messages to \"Button Only\": Enter adds a new line and the Send button sends." },
			{ type = "removed", text = "Shift+Enter: Studio doesn't tell plugins which keys are held, so it can't be told apart from Enter." },
			{ type = "removed", text = "The highlight when hovering over a message." },
			{ type = "fixed", text = "Theme, clock format, timestamps, send mode and text size can be changed again, and are remembered." },
			{ type = "fixed", text = "Links open in your web browser instead of the Roblox Creator Hub, and no longer click on the wrong text after changing how times are shown." },
			{ type = "fixed", text = "The Download button opens the file's Roblox page, or copies a local-only file's ID." },
			{ type = "fixed", text = "The plus button, polls, file attachments and drag and drop work again, and sending a file no longer crashes the chat." },
			{ type = "fixed", text = "Hovering links and replies no longer spams errors in Output." },
			{ type = "fixed", text = "Old copies of the plugin no longer keep running after a reload." },
			{ type = "fixed", text = "Clicking inside a window or menu (or its padding) no longer closes it, and the toolbar's Settings button no longer reopens Settings right after closing it." },
			{ type = "fixed", text = "Long windows no longer hide the buttons at the bottom." },
			{ type = "fixed", text = "An error that stopped messages from showing up." },
		},
	},
}
