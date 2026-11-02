--[[
	Runner (tests only)

	Runs the spec modules in tests/Specs. Each spec returns
	`function(t)` and reports with t.check(name, condition) / t.equal(name, actual, expected).

	Usage (Studio command bar, with dev.project.json synced):
		print(require(game.ServerStorage.TeamChatTests.Runner).run())         -- all specs
		print(require(game.ServerStorage.TeamChatTests.Runner).run("Smoke"))  -- specs whose name contains "Smoke"
]]

local Runner = {}

function Runner.run(filter: string?): string
	local lines = {}
	local passed, failed = 0, 0
	-- Run from a fresh copy of the whole tests folder: require() caches modules
	-- per instance, so edits synced by Rojo (Harness included) would be missed.
	local fresh = script.Parent:Clone()
	fresh.Name = "__TeamChatTestsRun"
	fresh.Parent = script.Parent.Parent
	local specs = fresh.Specs:GetChildren()
	table.sort(specs, function(a, b)
		return a.Name < b.Name
	end)

	for _, spec in ipairs(specs) do
		if spec:IsA("ModuleScript") and (not filter or string.find(spec.Name, filter, 1, true)) then
			table.insert(lines, "== " .. spec.Name)
			local t = {}
			function t.check(name: string, condition: any)
				if condition then
					passed += 1
					table.insert(lines, "  PASS " .. name)
				else
					failed += 1
					table.insert(lines, "  FAIL " .. name)
				end
			end
			function t.equal(name: string, actual: any, expected: any)
				t.check(
					("%s (got %s, expected %s)"):format(name, tostring(actual), tostring(expected)),
					actual == expected
				)
			end
			local ok, err = pcall(function()
				(require(spec) :: any)(t)
			end)
			if not ok then
				failed += 1
				table.insert(lines, "  ERROR " .. tostring(err))
			end
		end
	end
	fresh:Destroy()
	table.insert(lines, ("%d passed, %d failed"):format(passed, failed))
	return table.concat(lines, "\n")
end

return Runner
