--!strict
-- Shows a Roblox user's profile info and badges

local UserService = game:GetService("UserService")

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Badges = require(script.Parent.Parent.Parent.Services.Badges)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local UsernameColors = require(script.Parent.Parent.Parent.Util.UsernameColors)

return {
	Name = "whois",
	Aliases = { "profile" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Show someone's profile info",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/whois <user>" }))
			return
		end
		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = args[1] }))
			return
		end
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync({ userId })
		end)
		local info = ok and infos[1]
		if not info then
			ctx.addSystemMessage(Language.t("reply.whois.failed", { user = args[1] }))
			return
		end
		local badgeNames = {}
		for _, badge in ipairs(Badges.get(userId)) do
			local name = badge.name or ""
			table.insert(badgeNames, if badge.id then Language.tOr("badge." .. badge.id .. ".name", name) else name)
		end
		local rank = AdminNetwork.getRank(userId)
		local here = game:GetService("Players"):GetPlayerByUserId(userId) ~= nil
		ctx.addEmbed({
			title = info.DisplayName,
			description = "@" .. info.Username,
			thumbnailUserId = userId,
			color = UsernameColors.getNameColor(info.Username),
			fields = {
				{ name = Language.t("embed.whois.userId"), value = tostring(userId), inline = true },
				{
					name = Language.t("embed.whois.rank"),
					value = Language.tOr("rank." .. rank, AdminNetwork.getRankName(rank)),
					inline = true,
				},
				{
					name = Language.t("embed.whois.verified"),
					value = Language.t(if info.HasVerifiedBadge then "reply.yes" else "reply.no"),
					inline = true,
				},
				{
					name = Language.t("embed.whois.here"),
					value = Language.t(if here then "reply.yes" else "reply.no"),
					inline = true,
				},
				{
					name = Language.t("embed.whois.badges"),
					value = if #badgeNames > 0 then table.concat(badgeNames, ", ") else Language.t("reply.none"),
				},
			},
		})
	end,
}
