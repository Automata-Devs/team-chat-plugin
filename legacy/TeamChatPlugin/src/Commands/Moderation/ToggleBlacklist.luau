--!strict
-- Toggle the blacklist on/off

-- Note: Blacklist is always active when users are blacklisted.
-- This command toggles whether the blacklist filter is enforced.

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "toggleblacklist",
	Aliases = {"tbl"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 2,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Toggle the blacklist filter on/off",
	Contributors = {"D3veloperHac"},
	Args = {},
	Function = function(speaker, args, ctx)
		local list = AdminNetwork.getBlacklistedUsers()
		if #list == 0 then
			ctx.addSystemMessage("Blacklist is empty. Add users with /blacklist first.")
			return
		end

		ctx.addSystemMessage("Blacklist is always active when users are blacklisted.")
		ctx.addSystemMessage("Blacklisted users: " .. #list)
		for _, data in ipairs(list) do
			ctx.addSystemMessage("  " .. data.username .. " (ID: " .. data.userId .. ") - " .. (data.reason or "No reason"))
		end
	end,
}