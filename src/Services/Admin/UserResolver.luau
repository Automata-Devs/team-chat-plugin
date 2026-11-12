--[[
	UserResolver

	Resolves usernames to userIds and vice versa via Roblox API.
]]

local Players = game:GetService("Players")

local UserResolver = {}

--[=[
	Resolves a username string or numeric ID to a userId.
	input: A numeric string or username
	Returns number? The resolved userId, or nil if not found
]=]
function UserResolver.resolveUserId(input: string): number?
	-- If it's all digits, treat as userId
	local numId = tonumber(input)
	if numId then
		return numId
	end

	-- Try GetUserIdFromNameAsync
	local ok, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(input)
	end)
	if ok and userId then
		return userId
	end
	return nil
end

return UserResolver
