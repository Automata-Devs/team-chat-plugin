--!strict
-- Lists who is online in the chat

local ChatNetwork = require(script.Parent.Parent.Parent.Services.Chat)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "who",
	Aliases = { "online", "users" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Communication" },
	Description = "List users currently online",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		local users = ChatNetwork.getOnlineUsers()
		if #users == 0 then
			ctx.addSystemMessage(Language.t("reply.who.nobody"))
			return
		end
		local fields = {}
		for _, user in users do
			table.insert(fields, {
				name = user.name,
				value = Language.tOr("rank." .. tostring(user.rank), tostring(user.rank)),
				inline = true,
			})
		end
		ctx.addEmbed({ title = Language.t("embed.who.title", { count = #users }), fields = fields })
	end,
}
