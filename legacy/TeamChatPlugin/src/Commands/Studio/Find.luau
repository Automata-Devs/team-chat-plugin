--!strict
-- Searches the DataModel and selects matching instances

local Selection = game:GetService("Selection")

return {
	Name = "find",
	Aliases = {"search", "locate"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Studio"},
	Description = "Find instances by name and select them",
	Contributors = {"D3veloperHac"},
	Args = {"<name>", "[className]"},
	Function = function(speaker, args, ctx)
		if #args < 1 then
			ctx.addSystemMessage("Usage: /find <name> [className]")
			return
		end

		local query = args[1]:lower()
		local className = args[2]
		local results: {Instance} = {}

		for _, instance in game:GetDescendants() do
			if instance.Name:lower():find(query, 1, true) then
				if not className or instance:IsA(className) then
					table.insert(results, instance)
					if #results >= 100 then
						break
					end
				end
			end
		end

		if #results == 0 then
			ctx.addSystemMessage("No instances found for: " .. args[1])
			return
		end

		Selection:Set(results)
		ctx.addSystemMessage(`Selected {#results} instance(s).`)
	end,
}