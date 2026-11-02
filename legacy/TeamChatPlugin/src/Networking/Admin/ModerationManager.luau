--!
-- ModerationManager
-- Manages mutes, bans, kicks, blacklists, and whitelists for the
-- Team Chat plugin. Operates on the shared AdminState module.
--!

local AdminState = require(script.Parent.AdminState)
local ChatState = require(script.Parent.Parent.Chat.ChatState)

local ModerationManager = {}

--!
-- Checks if a user can send messages (not muted, banned, blacklisted,
-- or if whitelist is off / user is whitelisted).
--!
function ModerationManager.canUserSend(userId: number): boolean
	if ModerationManager.isMuted(userId) then return false end
	if AdminState.bannedUsers[userId] then return false end
	if AdminState.blacklistedUsers[userId] then return false end
	if AdminState.whitelistEnabled and not AdminState.whitelistedUsers[userId] then return false end
	return true
end

-- ── Mute / Unmute ──

function ModerationManager.mute(userId: number, username: string?, reason: string?, expiry: number?)
	AdminState.mutedUsers[userId] = {
		userId = userId,
		username = username or "Unknown",
		reason = reason or "No reason provided",
		expiry = expiry, -- nil = permanent
	}
	AdminState.save()
end

function ModerationManager.unmute(userId: number)
	AdminState.mutedUsers[userId] = nil
	AdminState.save()
end

function ModerationManager.isMuted(userId: number): boolean
	local data = AdminState.mutedUsers[userId]
	if not data then return false end
	-- Check expiry for temporary mutes
	if data.expiry and os.time() >= data.expiry then
		AdminState.mutedUsers[userId] = nil
		AdminState.save()
		return false
	end
	return true
end

function ModerationManager.getMutedUsers(): {table}
	local list = {}
	for _, data in pairs(AdminState.mutedUsers) do
		table.insert(list, data)
	end
	return list
end

-- ── Ban / Unban ──

function ModerationManager.ban(userId: number, username: string?, reason: string?)
	AdminState.bannedUsers[userId] = {
		userId = userId,
		username = username or "Unknown",
		reason = reason or "No reason provided",
	}
	AdminState.save()
end

function ModerationManager.unban(userId: number)
	AdminState.bannedUsers[userId] = nil
	AdminState.save()
end

function ModerationManager.isBanned(userId: number): boolean
	return AdminState.bannedUsers[userId] ~= nil
end

function ModerationManager.getBannedUsers(): {table}
	local list = {}
	for _, data in pairs(AdminState.bannedUsers) do
		table.insert(list, data)
	end
	return list
end

-- ── Kick (temporary ban until rejoin) ──

function ModerationManager.kick(userId: number, username: string?, reason: string?)
	AdminState.bannedUsers[userId] = {
		userId = userId,
		username = username or "Unknown",
		reason = (reason or "Kicked") .. " [temporary]",
	}
	AdminState.save()
end

-- ── Blacklist / Unblacklist ──

function ModerationManager.blacklist(userId: number, username: string?, reason: string?)
	AdminState.blacklistedUsers[userId] = {
		userId = userId,
		username = username or "Unknown",
		reason = reason or "No reason provided",
	}
	AdminState.save()
end

function ModerationManager.unblacklist(userId: number)
	AdminState.blacklistedUsers[userId] = nil
	AdminState.save()
end

function ModerationManager.isBlacklisted(userId: number): boolean
	return AdminState.blacklistedUsers[userId] ~= nil
end

function ModerationManager.getBlacklistedUsers(): {table}
	local list = {}
	for _, data in pairs(AdminState.blacklistedUsers) do
		table.insert(list, data)
	end
	return list
end

-- ── Warnings ──

function ModerationManager.warn(userId: number, moderatorId: number, reason: string, moderatorName: string?)
	if not AdminState.warnedUsers[userId] then
		AdminState.warnedUsers[userId] = {}
	end
	local moderator = moderatorName or "Unknown"
	table.insert(AdminState.warnedUsers[userId], {
		userId = userId,
		reason = reason,
		moderatorId = moderatorId,
		moderatorName = moderator,
		timestamp = os.time(),
	})
	AdminState.save()
end

function ModerationManager.getWarnings(userId: number): {table}
	return AdminState.warnedUsers[userId] or {}
end

-- ── Slowmode ──

function ModerationManager.setSlowmode(seconds: number)
	AdminState.slowmodeSeconds = seconds
	AdminState.save()
end

function ModerationManager.getSlowmode(): number
	return AdminState.slowmodeSeconds or 0
end

-- ── Purge (delete recent messages) ──

function ModerationManager.purge(amount: number, userId: number?): number
	local folder = ChatState.getFolder()
	local messages = {}
	for _, child in ipairs(folder:GetChildren()) do
		local msgType = child:GetAttribute("MessageType") or "Text"
		if msgType == "Text" or msgType == "Broadcast" or msgType == "Whisper" then
			local senderId = child:GetAttribute("SenderId") or 0
			if not userId or senderId == userId then
				table.insert(messages, child)
			end
		end
	end
	-- Sort by timestamp descending (newest first)
	table.sort(messages, function(a, b)
		return (a:GetAttribute("Timestamp") or 0) > (b:GetAttribute("Timestamp") or 0)
	end)
	local removed = 0
	for i = 1, math.min(amount, #messages) do
		messages[i].Parent = nil
		removed += 1
	end
	if removed > 0 then
		ChatState.saveHistory()
	end
	return removed
end

-- ── Whitelist / Unwhitelist / Toggle / List ──

function ModerationManager.whitelist(userId: number, username: string?)
	AdminState.whitelistedUsers[userId] = {
		userId = userId,
		username = username or "Unknown",
	}
	AdminState.save()
end

function ModerationManager.unwhitelist(userId: number)
	AdminState.whitelistedUsers[userId] = nil
	AdminState.save()
end

function ModerationManager.isWhitelisted(userId: number): boolean
	return AdminState.whitelistedUsers[userId] ~= nil
end

function ModerationManager.toggleWhitelist(): boolean
	AdminState.whitelistEnabled = not AdminState.whitelistEnabled
	AdminState.save()
	return AdminState.whitelistEnabled
end

function ModerationManager.isWhitelistEnabled(): boolean
	return AdminState.whitelistEnabled
end

function ModerationManager.getWhitelistedUsers(): {table}
	local list = {}
	for _, data in pairs(AdminState.whitelistedUsers) do
		table.insert(list, data)
	end
	return list
end

return ModerationManager