--!strict
-- Moves your Studio camera to where a collaborator is looking
-- Uses StudioNetwork for camera position sharing

local AdminNetwork = require(script.Parent.Parent.Parent.Networking.AdminNetwork)
local StudioNetwork = require(script.Parent.Parent.Parent.Networking.StudioNetwork)

return {
	Name = "goto",
	Aliases = {"follow", "jumpto"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Studio"},
	Description = "Move your camera to a collaborator's camera position",
	Contributors = {"D3veloperHac"},
	Args = {"<username|userId>"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /goto <username|userId>")
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage("Could not resolve user: " .. args[1])
			return
		end

		local cframe = StudioNetwork.getUserCameraCFrame(userId)
		local camera = workspace.CurrentCamera
		if not cframe or not camera then
			ctx.addSystemMessage("Could not get " .. args[1] .. "'s camera position.")
			return
		end

		camera.CFrame = cframe
		ctx.addSystemMessage("Moved camera to " .. args[1] .. ".")
	end,
}