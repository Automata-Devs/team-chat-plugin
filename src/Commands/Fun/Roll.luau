--!strict
-- Rolls a die and posts the result

local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "roll",
	Aliases = { "dice" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Fun" },
	Description = "Roll a die",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "sides", description = "Number of sides (default 6)", optional = true },
	},
	Function = function(_speaker, args, ctx)
		local sides = math.floor(tonumber(args[1]) or 6)
		if sides < 2 or sides > 1000000 then
			ctx.addSystemMessage(Language.t("reply.roll.sides"))
			return
		end
		ctx.addEmbed({
			title = "\u{1F3B2} " .. Language.t("embed.roll.title", { result = math.random(1, sides) }),
			description = Language.t("embed.roll.range", { sides = sides }),
		}, { public = true })
	end,
}
