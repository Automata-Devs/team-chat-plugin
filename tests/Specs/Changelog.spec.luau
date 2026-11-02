--[[
	What's New: main versions (1.0.0, 2.0.0, ...) hold their updates (1.13.1,
	1.12.4, ...). The page shows main versions as tabs and their updates as
	cards that fold open.
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	-- This version's notes count as seen, so its pop-up doesn't unfold anything first
	local current = game:GetService("ReplicatedStorage").TeamChatPlugin:GetAttribute("Version")
	local app = Harness.boot({ settings = { TeamChatAboutSeen_v1 = true, TeamChatLastSeenVersion_v1 = current } })
	local ok, err = pcall(function()
		local ui, gui = app.ui, app.gui
		local Changelog = require(app.copy.Config.Changelog) :: any

		-- The data: every main version is x.0.0 and holds updates of that x
		local shapeOk = #Changelog > 0
		for _, main in ipairs(Changelog) do
			local major = string.match(main.version, "^(%d+)%.0%.0$")
			shapeOk = shapeOk and major ~= nil and type(main.updates) == "table" and #main.updates > 0
			for _, update in ipairs(main.updates or {}) do
				shapeOk = shapeOk and string.match(update.version, "^(%d+)%.") == major
			end
		end
		t.check("main versions are x.0.0 and hold their x.y.z updates", shapeOk)

		local main = Changelog[1]
		local newest, older = main.updates[1], main.updates[2]
		ui.openChangelog(older.version)
		Harness.settle(2)
		local page = gui:FindFirstChild("ChangelogDialog", true) :: Frame

		local tab = page:FindFirstChild("Tab_" .. main.version, true) :: TextButton
		t.check("main versions are the tabs (" .. (tab and tab.Text or "none") .. ")", tab ~= nil and tab.Text == "1.0")
		local list = page:FindFirstChild("Updates", true) :: Frame
		local cards = 0
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") and string.find(child.Name, "^Update_") then
				cards += 1
			end
		end
		t.equal("its updates are listed as cards", cards, #main.updates)

		local function card(version: string): Frame
			return list:FindFirstChild("Update_" .. version) :: Frame
		end
		t.check("opening for a version unfolds that update", card(older.version):GetAttribute("Open") == true)
		t.check("…showing its notes", card(older.version):FindFirstChild("Notes") ~= nil)
		t.check("other updates stay folded", card(newest.version):GetAttribute("Open") ~= true)

		local header = card(newest.version):FindFirstChild("Header") :: TextButton
		t.check(
			"a card's header shows version, date and title",
			string.find((header:FindFirstChild("Label") :: TextLabel).Text, newest.version, 1, true) ~= nil
		)
		ui.closeSettings()
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
