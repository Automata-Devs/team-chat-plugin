--!strict
-- Opens the About window

return {
	Name = "about",
	Aliases = { "info", "terms" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Show info about the plugin and its terms",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		ctx.openAbout()
	end,
}
