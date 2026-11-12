--!strict
-- Command template
-- Copy this module and modify the fields below to create a new command.
-- Commands/Registry auto-discovers ModuleScripts in this folder and subfolders.
return {
	Name = "commandName",
	Aliases = { "alias1", "alias2" },
	Prefixes = { "/" }, -- Command prefixes
	Enabled = true, -- If the command is enabled
	Rank = 0, -- Minimum rank to use the command
	RankLock = false, -- If the rank is locked to the specified rank
	Loopable = false, -- If the command can be looped
	Tags = {}, -- Command tags
	Description = "Command description",
	Contributors = { "YourName" }, -- Command contributors
	-- Command arguments, shown above the message box while typing the command, e.g.
	-- { { name = "user", description = "Username or user ID" },
	--   { name = "reason", description = "Why", optional = true } }
	Args = {},
	Function = function(_speaker, _args, ctx) -- Command function (drop the _ when you use them)
		-- speaker: { userId, username, name, rank }
		-- args: {string} of arguments passed after the command name
		-- ctx: context table with helper functions:
		--   ctx.addSystemMessage(text)  - show a system message in chat
		--   ctx.addEmbed(spec)          - reply with a card: { title, description?,
		--                                 thumbnailUserId?, color?, footer?,
		--                                 fields = { { name, value, inline? } } }
		--                                 (UI/Embeds/Providers/CommandEmbed)
		--   ctx.clearChat()             - clear the chat view
		--   ctx.sendMessage(text)       - send a chat message as you
		--   ctx.openAbout() / ctx.openBadges() - open those windows
		ctx.addSystemMessage("Hello world!")
	end,
}
