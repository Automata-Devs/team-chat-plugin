--!strict
-- Clears the chat history (local view)

return {
	Name = "clear",
	Aliases = {"cls"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Utility"},
	Description = "Clear all messages from your chat view",
	Contributors = {"D3veloperHac"},
	Args = {},
	Function = function(speaker, args, ctx)
		ctx.clearChat()
		ctx.addSystemMessage("Chat cleared.")
	end,
}