--!strict
-- Lists all collaborators currently in the chat

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "listusers",
	Aliases = {"users", "who"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Utility", "Info"},
	Description = "Lists all collaborators in the chat",
	Contributors = {"D3veloperHac"},
	Args = {},
	Function = function(speaker, args, ctx)
		local Players = game:GetService("Players")
		local users = Players:GetPlayers()
		if #users == 0 then
			ctx.addSystemMessage("No collaborators currently online.")
			return
		end

		ctx.addSystemMessage("Collaborators (" .. #users .. "):")
		for _, player in ipairs(users) do
			local rank = AdminNetwork.getRank(player.UserId)
			local rankName = AdminNetwork.getRankName(rank)
			local tag = rank > 0 and (" [" .. rankName .. "]") or ""
			ctx.addSystemMessage("  " .. player.Name .. tag)
		end
	end,
}