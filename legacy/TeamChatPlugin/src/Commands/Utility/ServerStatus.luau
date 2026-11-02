--!strict
-- Displays the server's status

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "serverstatus",
	Aliases = {"status", "ss"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Utility", "Info"},
	Description = "Displays the current server status",
	Contributors = {"D3veloperHac"},
	Args = {},
	Function = function(speaker, args, ctx)
		local Players = game:GetService("Players")
		local users = Players:GetPlayers()
		local mutedCount = #AdminNetwork.getMutedUsers()
		local bannedCount = #AdminNetwork.getBannedUsers()
		local blacklistedCount = #AdminNetwork.getBlacklistedUsers()
		local whitelistStatus = AdminNetwork.isWhitelistEnabled() and "ON" or "OFF"

		ctx.addSystemMessage("=== Server Status ===")
		ctx.addSystemMessage("Online: " .. #users .. " collaborator(s)")
		ctx.addSystemMessage("Your rank: " .. AdminNetwork.getRankName(AdminNetwork.getMyRank()))
		ctx.addSystemMessage("Muted: " .. mutedCount .. " | Banned: " .. bannedCount .. " | Blacklisted: " .. blacklistedCount)
		ctx.addSystemMessage("Whitelist: " .. whitelistStatus)
	end,
}