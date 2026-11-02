--!strict
-- Sends a message with a shrug after it

return {
	Name = "shrug",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Communication" },
	Description = "Send ¯\\_(ツ)_/¯",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "message", description = "Text before the shrug", optional = true },
	},
	Function = function(_speaker, args, ctx)
		local text = table.concat(args, " ")
		ctx.sendMessage((if text ~= "" then text .. " " else "") .. "¯\\_(ツ)_/¯")
	end,
}
