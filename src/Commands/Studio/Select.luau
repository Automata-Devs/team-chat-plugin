--!strict
-- Selects instances by name in the Explorer

local Selection = game:GetService("Selection")

local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "select",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Studio" },
	Description = "Select instances by name",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "name", description = "Exact instance name" },
		{ name = "className", description = "Only this class, e.g. Part", optional = true },
	},
	Function = function(_speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage(Language.t("commands.usage", { usage = "/select <name> [className]" }))
			return
		end
		local found: { Instance } = {}
		for _, instance in ipairs(workspace:GetDescendants()) do
			if instance.Name == args[1] and (not args[2] or instance:IsA(args[2])) then
				table.insert(found, instance)
				if #found >= 500 then
					break
				end
			end
		end
		if #found == 0 then
			ctx.addSystemMessage(Language.t("reply.select.none", { name = args[1] }))
			return
		end
		Selection:Set(found)
		ctx.addSystemMessage(Language.t("reply.select.done", { count = #found, name = args[1] }))
	end,
}
