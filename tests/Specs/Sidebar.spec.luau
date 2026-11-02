--[[
	The expanded sidebar in a narrow panel lies over the chat (overlay)
	instead of squeezing it; in a wide panel it sits beside the chat.
]]

local Harness = require(script.Parent.Parent.Harness)

local COLLAPSED, EXPANDED, OFFSET = 64, 220, 15

return function(t)
	-- Narrow panel: overlay
	local app =
		Harness.boot({ narrow = true, settings = { TeamChatAboutSeen_v1 = true, TeamChatLastSeenVersion_v1 = "x" } })
	local ok, err = pcall(function()
		local gui, hooks = app.gui, app.hooks
		local container = gui:FindFirstChild("Container") :: Frame
		local sidebar = gui:FindFirstChild("Sidebar") :: Frame
		local scrim = gui:FindFirstChild("SidebarScrim") :: TextButton
		local edge = sidebar:FindFirstChild("Edge") :: Frame
		local edgeZ = edge.ZIndex

		hooks.setSidebarExpanded(true)
		Harness.settle()
		t.check("expanded sidebar is full width", sidebar.AbsoluteSize.X == EXPANDED)
		t.equal("the chat keeps its collapsed position", container.Position.X.Offset, COLLAPSED)
		t.equal("the chat keeps its collapsed size", container.Size.X.Offset, -COLLAPSED)
		t.check("the chat behind is dimmed", scrim.Visible)
		t.check(
			"sidebar is raised above the chat",
			edge.ZIndex == edgeZ + OFFSET and sidebar:GetAttribute("Overlay") == true
		)
		t.check("…and stays below dialogs", edge.ZIndex < 20)

		-- Rows added while it's raised are raised too
		app.ui.setConversations({
			{ id = "main", kind = "place", name = "Place", onlineCount = 1, unread = 0 },
			{ id = "dm_x", kind = "dm", userId = 156, name = "builderman", unread = 0 },
		}, "main")
		Harness.settle()
		local lowest = math.huge
		for _, d in ipairs(sidebar:GetDescendants()) do
			if d:IsA("GuiObject") then
				lowest = math.min(lowest, d.ZIndex)
			end
		end
		t.check("every sidebar element is above the chat", lowest > OFFSET)

		-- Re-rendering (rows move between holders) must not raise anything twice
		for _ = 1, 3 do
			app.ui.setConversations({
				{ id = "dm_x", kind = "dm", userId = 156, name = "builderman", unread = 0 },
				{ id = "main", kind = "place", name = "Place", onlineCount = 1, unread = 0 },
			}, "dm_x")
			Harness.settle()
		end
		local highest = 0
		for _, d in ipairs(sidebar:GetDescendants()) do
			if d:IsA("GuiObject") then
				highest = math.max(highest, d.ZIndex)
			end
		end
		t.check("…and still below dialogs after re-rendering (" .. highest .. ")", highest < 20)

		-- Clicking the dimmed chat closes it
		hooks.clicks[scrim]()
		Harness.settle()
		t.check("clicking the chat closes the sidebar", sidebar.AbsoluteSize.X == COLLAPSED and not scrim.Visible)
		t.equal("ZIndexes go back down", edge.ZIndex, edgeZ)
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end

	-- Wide panel: beside the chat, no overlay
	local wide = Harness.boot({ settings = { TeamChatAboutSeen_v1 = true, TeamChatLastSeenVersion_v1 = "x" } })
	local ok2, err2 = pcall(function()
		local gui, hooks = wide.gui, wide.hooks
		hooks.setSidebarExpanded(true)
		Harness.settle()
		local container = gui:FindFirstChild("Container") :: Frame
		t.equal("wide panel: the chat moves over", container.Position.X.Offset, EXPANDED)
		t.check("wide panel: no dimming", not (gui:FindFirstChild("SidebarScrim") :: TextButton).Visible)

		-- DMs show when their last message was, and can be searched. The list is
		-- set right before each check: the real conversation list refreshes it
		-- whenever the chat changes.
		local now = os.time()
		local function showTestList()
			wide.ui.setConversations({
				{ id = "main", kind = "place", name = "Place", onlineCount = 1, unread = 0 },
				{ id = "dm_1_156", kind = "dm", userId = 156, name = "builderman", unread = 0, lastTimestamp = now },
				{
					id = "dm_1_261",
					kind = "dm",
					userId = 261,
					name = "shedletsky",
					unread = 0,
					lastTimestamp = now - 86400 * 40,
				},
			}, "main")
		end
		local sidebar = gui:FindFirstChild("Sidebar") :: Frame
		local function rowOf(name: string): TextButton?
			for _, label in ipairs(sidebar:GetDescendants()) do
				if label.Name == "NameLabel" and label:IsA("TextLabel") and string.find(label.Text, name, 1, true) then
					return label.Parent :: TextButton
				end
			end
			return nil
		end
		showTestList()
		local recent, older = rowOf("builderman"), rowOf("shedletsky")
		local recentTime = recent and (recent:FindFirstChild("TimeLabel") :: TextLabel)
		local olderTime = older and (older:FindFirstChild("TimeLabel") :: TextLabel)
		t.check(
			"today's DM shows the time: " .. (if recentTime then recentTime.Text else "?"),
			recentTime ~= nil and recentTime.Visible and string.find(recentTime.Text, "%d+:%d%d") ~= nil
		)
		t.check(
			"an older DM shows the date: " .. (if olderTime then olderTime.Text else "?"),
			olderTime ~= nil and string.find(olderTime.Text, "^%d%d/%d%d") ~= nil
		)
		local search = sidebar:FindFirstChild("Search", true) :: TextBox
		t.check("the expanded sidebar has a search box", search ~= nil and (search.Parent :: Frame).Visible)
		search.Text = "shed"
		showTestList()
		recent, older = rowOf("builderman"), rowOf("shedletsky")
		t.check(
			"search hides DMs that don't match",
			recent ~= nil and older ~= nil and not (recent.Parent :: Frame).Visible and (older.Parent :: Frame).Visible
		)
		local newMessageLabel = sidebar:FindFirstChild("NewMessage", true):FindFirstChild("NameLabel") :: TextLabel
		t.equal("…and offers to search friends", newMessageLabel.Text, 'Search friends for "shed"')
		search.Text = ""
		showTestList()
		recent = rowOf("builderman")
		t.check("clearing it shows them all again", recent ~= nil and (recent.Parent :: Frame).Visible)
	end)
	wide.stop()
	if not ok2 then
		error(err2, 0)
	end
end
