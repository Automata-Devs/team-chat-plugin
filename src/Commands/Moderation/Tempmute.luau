--!strict
-- Mutes a user for a limited time

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Abbreviate = require(script.Parent.Parent.Parent.Packages.Abbreviate)
local Duration = require(script.Parent.Parent.Parent.Util.Duration)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "tempmute",
	Aliases = { "tmute" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Mute a user for a set duration",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Username or user ID" },
		{ name = "duration", description = "How long, e.g. 10m, 2h or 1d" },
		{ name = "reason", description = "Reason for the mute", optional = true },
	},
	Function = function(speaker, args, ctx)
		if #args < 2 then
			ctx.addSystemMessage(
				Language.t("commands.usage", { usage = "/tempmute <username|userId> <duration> [reason]" })
			)
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = args[1] }))
			return
		end

		local seconds = Duration.parse(args[2])
		if not seconds or seconds <= 0 then
			ctx.addSystemMessage(Language.t("reply.invalidDuration", { value = args[2] }))
			return
		end

		if AdminNetwork.getRank(userId) >= speaker.rank then
			ctx.addSystemMessage(Language.t("reply.mute.higher"))
			return
		end

		local reason = #args > 2 and table.concat(args, " ", 3) or "No reason provided"
		AdminNetwork.mute(userId, args[1], reason, os.time() + seconds)
		ctx.addEmbed({
			title = Language.t("embed.mod.mute", { user = args[1] }),
			thumbnailUserId = userId,
			color = Color3.fromRGB(255, 140, 50),
			fields = {
				{ name = Language.t("embed.mod.duration"), value = Abbreviate.Format(seconds, "Time"), inline = true },
				{ name = Language.t("embed.mod.reason"), value = reason },
			},
		}, { public = true })
	end,
}
