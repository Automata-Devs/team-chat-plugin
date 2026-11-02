--!strict
-- Opens the Badges window

return {
	Name = "badges",
	Aliases = { "shop", "store" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Show your badges and the badge shop",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		ctx.openBadges()
	end,
}
