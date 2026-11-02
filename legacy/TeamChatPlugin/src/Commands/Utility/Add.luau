--!strict
-- Adds an object to the workspace

return {
	Name = "add",
	Aliases = {},
	Prefixes = {"/"}, -- Command prefixes
	Enabled = true, -- If the command is enabled
	Rank = 0, -- Minimum rank to use the command
	RankLock = false, -- If the rank is locked to the specified rank
	Loopable = false, -- If the command can be looped
	Tags = {}, -- Command tags
	Description = "Add objects to the workspace",
	Contributors = {"D3veloperHac"}, -- Command contributors
	Args = {"[object]", "[location]"}, -- Command arguments
	Function = function(speaker, args, ctx) -- Command function
		if #args < 1 then
			ctx.addSystemMessage("Usage: /add [object] [location]")
			return
		end
		
		local objectName = args[1]
		local location = args[2] or "Workspace"
		
		local service = game:GetService(location)
		if not service then
			ctx.addSystemMessage("Invalid location: " .. location)
			return
		end
		
		local ok, object = pcall(function()
			return Instance.new(objectName)
		end)
		if not ok or not object then
			ctx.addSystemMessage("Invalid object type: " .. objectName)
			return
		end
		
		object.Parent = service
		object.Name = objectName
		ctx.addSystemMessage("Added " .. objectName .. " to " .. location)
	end,
}