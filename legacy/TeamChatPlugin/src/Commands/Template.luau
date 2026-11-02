--!strict
-- Command template
-- Copy this module and modify the fields below to create a new command.
-- The CommandHandler auto-discovers ModuleScripts in this folder and subfolders.
return {
	Name = "commandName",
	Aliases = {"alias1", "alias2"},
	Prefixes = {"/"}, -- Command prefixes
	Enabled = true, -- If the command is enabled
	Rank = 0, -- Minimum rank to use the command
	RankLock = false, -- If the rank is locked to the specified rank
	Loopable = false, -- If the command can be looped
	Tags = {}, -- Command tags
	Description = "Command description",
	Contributors = {"YourName"}, -- Command contributors
	Args = {}, -- Command arguments (e.g. {"<username>", "[reason]"})
	Function = function(speaker, args, ctx) -- Command function
		-- speaker: { userId, username, name, rank }
		-- args: {string} of arguments passed after the command name
		-- ctx: context table with helper functions:
		--   ctx.addSystemMessage(text)  - show a system message in chat
		--   ctx.clearChat()             - clear the chat view
		ctx.addSystemMessage("Hello world!")
	end,
}