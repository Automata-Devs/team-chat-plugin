--[[
	#tags: pointing at objects in the place from the chat. The picker, how a
	tag is saved and shown, and clicking it (select + camera).
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local Selection = game:GetService("Selection")
	local camera = workspace.CurrentCamera
	local savedCamera = camera.CFrame
	local savedSelection = Selection:Get()
	local model = Instance.new("Model")
	model.Name = "TagTestModel"
	local door = Instance.new("Part")
	door.Name = "TagTestDoor"
	door.Anchored = true
	door.Size = Vector3.new(4, 8, 1)
	door.Position = Vector3.new(500, 50, 500)
	door.Parent = model
	local dotted = Instance.new("Part")
	dotted.Name = "v1.2 Sign"
	dotted.Anchored = true
	dotted.Parent = model
	model.Parent = workspace

	local ok, err = pcall(function()
		local ObjectTags = require(app.copy.Services.ObjectTags) :: any
		local ui, gui = app.ui, app.gui

		-- Finding and resolving
		local found = ObjectTags.search("tagtestd", 7)
		t.check("search finds objects by name", table.find(found, door) ~= nil)
		t.equal("a tag saves the full path", ObjectTags.pathOf(door), "Workspace.TagTestModel.TagTestDoor")
		t.equal("…which finds it again", ObjectTags.resolve(ObjectTags.pathOf(door)), door)
		t.equal("names with dots resolve too", ObjectTags.resolve(ObjectTags.pathOf(dotted)), dotted)
		t.equal("a missing object resolves to nil", ObjectTags.resolve("Workspace.Nothing.Here"), nil)
		Selection:Set({ dotted })
		t.equal("just # offers your selection", ObjectTags.search("", 7)[1], dotted)

		-- Clicking a tag: select it and move the camera to it
		local moved = ObjectTags.focus(door, false)
		t.check("focusing selects the object", Selection:Get()[1] == door)
		t.check(
			"…and moves the camera to look at it",
			moved
				and (camera.CFrame.Position - door.Position).Magnitude < 40
				and camera.CFrame.LookVector:Dot((door.Position - camera.CFrame.Position).Unit) > 0.99
		)
		local folder = Instance.new("Folder")
		folder.Name = "TagTestFolder"
		folder.Parent = workspace
		t.check("objects without a position are only selected", ObjectTags.focus(folder, false) == false)
		folder:Destroy()

		-- The picker in the message box
		local box = ui.textBox
		local menu = gui:FindFirstChild("Autocomplete", true) :: Frame
		box.Text = "look at #TagTestD"
		Harness.settle()
		t.check("typing # opens the Objects list", menu.Visible)
		t.equal("…titled Objects", (menu:FindFirstChild("Title") :: TextLabel).Text, "OBJECTS")
		box.Text = "look at #TagTestD\t"
		Harness.settle()
		t.equal("Tab puts the tag in", box.Text, "look at #[Workspace.TagTestModel.TagTestDoor] ")
		box.Text = "# Header"
		Harness.settle()
		t.check("a # header doesn't open it", not menu.Visible)
		box.Text = ""
		Harness.settle()

		-- In a message: shown as #Name with a pill, like a mention
		local stamp = os.time() + 950
		ui.addMessage("builderman", stamp, "the door #[Workspace.TagTestModel.TagTestDoor] is broken", nil, nil, 156)
		Harness.settle()
		local row
		for _, child in ipairs(gui:FindFirstChild("MessageList", true):GetChildren()) do
			if child:GetAttribute("Timestamp") == stamp then
				row = child
			end
		end
		local label = row and row:FindFirstChild("TextContent") :: TextLabel
		t.equal("a tag shows as #Name", label and label.ContentText, "the door #TagTestDoor is broken")
		local pill
		for _ = 1, 40 do
			pill = label and label:FindFirstChild("MentionPill")
			if pill then
				break
			end
			task.wait(0.1)
		end
		t.check("…with the same pill as a mention", pill ~= nil)

		local MessageText = require(app.copy.UI.Text.MessageText) :: any
		Selection:Set({})
		MessageText.onTag("Workspace.TagTestModel.TagTestDoor")
		t.check("clicking a tag selects the object", Selection:Get()[1] == door)
		local before = #gui:FindFirstChild("MessageList", true):GetChildren()
		MessageText.onTag("Workspace.Gone")
		Harness.settle()
		t.check("a tag whose object is gone says so", #gui:FindFirstChild("MessageList", true):GetChildren() > before)
	end)
	model:Destroy()
	camera.CFrame = savedCamera
	Selection:Set(savedSelection)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
