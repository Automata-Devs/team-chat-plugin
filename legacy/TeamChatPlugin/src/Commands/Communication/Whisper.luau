--!strict
-- Sends a private message to a collaborator

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)
local ChatNetwork = require(script.Parent.Parent.Parent.Networking.ChatNetwork)

return {
	Name = "whisper",
	Aliases = {"w", "pm", "msg"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Communication"},
	Description = "Send a direct message to a collaborator",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>", "<message>"},
	Function = function(speaker, args, ctx)
		if #args < 2 then
			ctx.addSystemMessage("Usage: /whisper <username|userId> <message>")
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. args[1])
			return
		end

		local message = table.concat(args, " ", 2)
		local ok = ChatNetwork.sendWhisper(userId, message)
		if not ok then
			ctx.addSystemMessage("Couldn't send a direct message to " .. args[1] .. ".")
			return
		end

		ctx.addSystemMessage(`Sent to {args[1]}'s DMs: {message}`)
	end,
}