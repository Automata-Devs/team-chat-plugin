--!strict
-- Flips a coin and posts the result

local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "coinflip",
	Aliases = { "flip", "coin" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Fun" },
	Description = "Flip a coin",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		ctx.addEmbed({
			title = "\u{1FA99} " .. Language.t(if math.random() < 0.5 then "embed.coin.heads" else "embed.coin.tails"),
		}, { public = true })
	end,
}
