--!strict
-- List all whitelisted users

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "listwhitelist",
	Aliases = {"listwl", "wllist"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation", "Info"},
	Description = "List all whitelisted users",
	Contributors = {"D3veloperHac"},
	Args = {},
	Function = function(speaker, args, ctx)
		local enabled = AdminNetwork.isWhitelistEnabled()
		local list = AdminNetwork.getWhitelistedUsers()

		ctx.addSystemMessage("Whitelist mode: " .. (enabled and "ENABLED" or "DISABLED"))

		if #list == 0 then
			ctx.addSystemMessage("No whitelisted users.")
			return
		end

		ctx.addSystemMessage("Whitelisted users (" .. #list .. "):")
		for _, data in ipairs(list) do
			ctx.addSystemMessage("  " .. data.username .. " (ID: " .. data.userId .. ")")
		end
	end,
}