--!strict
-- Toggle the whitelist filter on/off

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "togglewhitelist",
	Aliases = {"twl"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Toggle the whitelist filter on/off (when on, only whitelisted users can chat)",
	Contributors = {"D3veloperHac"},
	Args = {},
	Function = function(speaker, args, ctx)
		local enabled = AdminNetwork.toggleWhitelist()
		if enabled then
			local list = AdminNetwork.getWhitelistedUsers()
			ctx.addSystemMessage("Whitelist mode ENABLED. Only whitelisted users can send messages.")
			ctx.addSystemMessage("Whitelisted users: " .. #list)
			for _, data in ipairs(list) do
				ctx.addSystemMessage("  " .. data.username .. " (ID: " .. data.userId .. ")")
			end
		else
			ctx.addSystemMessage("Whitelist mode DISABLED. All users can send messages.")
		end
	end,
}