--!strict
-- Toggle the whitelist filter on/off

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "togglewhitelist",
	Aliases = { "twl" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = { "Moderation" },
	Description = "Toggle the whitelist filter on/off (when on, only whitelisted users can chat)",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		local enabled = AdminNetwork.toggleWhitelist()
		local fields = {}
		if enabled then
			for _, data in ipairs(AdminNetwork.getWhitelistedUsers()) do
				table.insert(fields, { name = data.username, value = "ID " .. tostring(data.userId), inline = true })
			end
		end
		ctx.addEmbed({
			title = Language.t("embed.whitelist.title"),
			description = Language.t(if enabled then "reply.whitelist.on" else "reply.whitelist.off"),
			color = if enabled then Color3.fromRGB(63, 191, 110) else nil,
			fields = fields,
		}, { public = true })
	end,
}
