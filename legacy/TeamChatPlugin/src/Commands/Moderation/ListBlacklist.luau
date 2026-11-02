--!strict
-- List all blacklisted users

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)

return {
	Name = "listblacklist",
	Aliases = {"listbl", "bllist"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation", "Info"},
	Description = "List all blacklisted users",
	Contributors = {"D3veloperHac"},
	Args = {},
	Function = function(speaker, args, ctx)
		local list = AdminNetwork.getBlacklistedUsers()
		if #list == 0 then
			ctx.addSystemMessage("No blacklisted users.")
			return
		end

		ctx.addSystemMessage("Blacklisted users (" .. #list .. "):")
		for _, data in ipairs(list) do
			ctx.addSystemMessage("  " .. data.username .. " (ID: " .. data.userId .. ") - " .. (data.reason or "No reason"))
		end
	end,
}