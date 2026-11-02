--!strict
-- Sends a private message to a collaborator

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local ChatNetwork = require(script.Parent.Parent.Parent.Services.Chat)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "whisper",
	Aliases = { "w", "pm", "msg" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Communication" },
	Description = "Send a direct message to a collaborator",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Who to message (username or user ID)" },
		{ name = "message", description = "What to send" },
	},
	Function = function(_speaker, args, ctx)
		if #args < 2 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/whisper <username|userId> <message>" }))
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = args[1] }))
			return
		end

		local message = table.concat(args, " ", 2)
		local ok = ChatNetwork.sendWhisper(userId, message)
		if not ok then
			ctx.addSystemMessage(Language.t("reply.whisper.failed", { user = args[1] }))
			return
		end

		ctx.addSystemMessage(Language.t("reply.whisper.sent", { user = args[1], message = message }))
	end,
}
