--!strict
-- Lists who is online in the chat

local ChatNetwork = require(script.Parent.Parent.Parent.Networking.ChatNetwork)

return {
	Name = "who",
	Aliases = {"online", "users"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Communication"},
	Description = "List users currently online",
	Contributors = {"D3veloperHac"},
	Args = {},
	Function = function(speaker, args, ctx)
		local users = ChatNetwork.getOnlineUsers()
		if #users == 0 then
			ctx.addSystemMessage("Nobody else is online.")
			return
		end

		local names = {}
		for _, user in users do
			table.insert(names, `{user.name} (rank {user.rank})`)
		end
		ctx.addSystemMessage(`Online ({#users}): {table.concat(names, ", ")}`)
	end,
}