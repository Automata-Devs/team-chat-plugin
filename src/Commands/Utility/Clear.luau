--!strict
-- Clears the chat history (local view)

local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "clear",
	Aliases = { "cls" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Clear all messages from your chat view",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		ctx.clearChat()
		ctx.addSystemMessage(Language.t("reply.clear.done"))
	end,
}
