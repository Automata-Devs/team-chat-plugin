--!strict
-- Adds an object to the workspace

local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "add",
	Aliases = {},
	Prefixes = { "/" }, -- Command prefixes
	Enabled = true, -- If the command is enabled
	Rank = 0, -- Minimum rank to use the command
	RankLock = false, -- If the rank is locked to the specified rank
	Loopable = false, -- If the command can be looped
	Tags = {}, -- Command tags
	Description = "Add objects to the workspace",
	Contributors = { "D3veloperHac" }, -- Command contributors
	Args = {
		{ name = "className", description = "Class to create, e.g. Part" },
		{ name = "service", description = "Where to put it (default Workspace)", optional = true },
	},
	Function = function(_speaker, args, ctx) -- Command function
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/add [object] [location]" }))
			return
		end

		local objectName = args[1]
		local location = args[2] or "Workspace"

		local service = game:GetService(location)
		if not service then
			ctx.addSystemMessage(Language.t("reply.add.badLocation", { location = location }))
			return
		end

		local ok, object = pcall(function()
			return Instance.new(objectName)
		end)
		if not ok or not object then
			ctx.addSystemMessage(Language.t("reply.add.badObject", { object = objectName }))
			return
		end

		object.Parent = service
		object.Name = objectName
		ctx.addSystemMessage(Language.t("reply.add.done", { object = objectName, location = location }))
	end,
}
