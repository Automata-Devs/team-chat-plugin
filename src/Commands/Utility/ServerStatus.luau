--!strict
-- Displays the server's status

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "serverstatus",
	Aliases = { "status", "ss" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility", "Info" },
	Description = "Displays the current server status",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		local users = game:GetService("Players"):GetPlayers()
		local myRank = AdminNetwork.getMyRank()
		ctx.addEmbed({
			title = Language.t("embed.status.title"),
			fields = {
				{ name = Language.t("embed.status.online"), value = tostring(#users), inline = true },
				{
					name = Language.t("embed.status.rank"),
					value = Language.tOr("rank." .. myRank, AdminNetwork.getRankName(myRank)),
					inline = true,
				},
				{
					name = Language.t("embed.status.whitelist"),
					value = Language.t(if AdminNetwork.isWhitelistEnabled() then "reply.on" else "reply.off"),
					inline = true,
				},
				{
					name = Language.t("embed.status.muted"),
					value = tostring(#AdminNetwork.getMutedUsers()),
					inline = true,
				},
				{
					name = Language.t("embed.status.banned"),
					value = tostring(#AdminNetwork.getBannedUsers()),
					inline = true,
				},
				{
					name = Language.t("embed.status.blacklisted"),
					value = tostring(#AdminNetwork.getBlacklistedUsers()),
					inline = true,
				},
			},
		})
	end,
}
