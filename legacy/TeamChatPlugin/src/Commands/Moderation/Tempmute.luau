--!strict
-- Mutes a user for a limited time

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)
local Abbreviate = require(script.Parent.Parent.Parent.Packages.Abbreviate)

-- Parses compound duration strings like "30s", "10m", "1h30m", "1w", "1mo", "1y".
-- (The Abbreviate module handles formatting; duration parsing stays local.)
local DURATION_UNITS: {[string]: number} = {s = 1, m = 60, h = 3600, d = 86400, w = 604800, mo = 2592000, y = 31536000}

local function parseDuration(text: string): number?
	local total, matched = 0, 0
	for amount, unit in text:lower():gmatch("(%d+)(%a+)") do
		local multiplier = DURATION_UNITS[unit]
		if not multiplier then
			return nil
		end
		total += tonumber(amount) :: number * multiplier
		matched += 1
	end
	if matched == 0 then
		return tonumber(text)
	end
	return total
end

return {
	Name = "tempmute",
	Aliases = {"tmute"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 1,
	RankLock = false,
	Loopable = false,
	Tags = {"Moderation"},
	Description = "Mute a user for a set duration",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>", "<duration>", "[reason]"},
	Function = function(speaker, args, ctx)
		if #args < 2 then
			ctx.addSystemMessage("Usage: /tempmute <username|userId> <duration> [reason]")
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. args[1])
			return
		end

		local seconds = parseDuration(args[2])
		if not seconds or seconds <= 0 then
			ctx.addSystemMessage("Invalid duration: " .. args[2])
			return
		end

		if AdminNetwork.getRank(userId) >= speaker.rank then
			ctx.addSystemMessage("You cannot mute someone of equal or higher rank.")
			return
		end

		local reason = #args > 2 and table.concat(args, " ", 3) or "No reason provided"
		AdminNetwork.mute(userId, args[1], reason, os.time() + seconds)
		ctx.addSystemMessage(`Muted {args[1]} for {Abbreviate.Format(seconds, "Time")} - Reason: {reason}`)
	end,
}