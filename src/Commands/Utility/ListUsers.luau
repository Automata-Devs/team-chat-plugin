--!strict
-- Lists all collaborators currently in the chat

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "listusers",
	Aliases = { "users", "who" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility", "Info" },
	Description = "Lists all collaborators in the chat",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		local users = game:GetService("Players"):GetPlayers()
		if #users == 0 then
			ctx.addSystemMessage(Language.t("reply.users.none"))
			return
		end

		local fields = {}
		for _, player in ipairs(users) do
			local rank = AdminNetwork.getRank(player.UserId)
			table.insert(fields, {
				name = player.DisplayName,
				value = "@" .. player.Name .. "  \u{00B7}  " .. Language.tOr(
					"rank." .. rank,
					AdminNetwork.getRankName(rank)
				),
				inline = true,
			})
		end
		ctx.addEmbed({ title = Language.t("embed.users.title", { count = #users }), fields = fields })
	end,
}
