--!strict
-- Moves your Studio camera to where a collaborator is looking
-- Uses StudioCollab for camera position sharing

local AdminNetwork = require(script.Parent.Parent.Parent.Services.Admin)
local StudioCollab = require(script.Parent.Parent.Parent.Services.StudioCollab)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "goto",
	Aliases = { "follow", "jumpto" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Studio" },
	Description = "Move your camera to a collaborator's camera position",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "user", description = "Whose camera to jump to (username or user ID)" },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/goto <username|userId>" }))
			return
		end

		local userId = AdminNetwork.resolveUserId(args[1])
		if not userId then
			ctx.addSystemMessage(Language.t("reply.unresolved", { user = args[1] }))
			return
		end

		local cframe = StudioCollab.getUserCameraCFrame(userId)
		local camera = workspace.CurrentCamera
		if not cframe or not camera then
			ctx.addSystemMessage(Language.t("reply.goto.noCamera", { user = args[1] }))
			return
		end

		camera.CFrame = cframe
		ctx.addSystemMessage(Language.t("reply.goto.done", { user = args[1] }))
	end,
}
