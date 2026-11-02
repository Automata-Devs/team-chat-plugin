--!strict
--[[
	ObjectTags

	#tags point at objects in the place, like a Discord channel mention. In a
	message a tag is saved as "#[<full path>]" (Instance:GetFullName(), e.g.
	"#[Workspace.Map.Door]") and shown as "#Door". Clicking it selects the
	object and, when it has a position, glides the camera to it.

	Usage:
		ObjectTags.search("doo", 7)          -- objects whose name starts with "doo" (selection first)
		ObjectTags.pathOf(instance)          -- "Workspace.Map.Door"
		ObjectTags.resolve("Workspace.Map.Door") -- the instance, or nil
		ObjectTags.focus(instance, animate)  -- select it and move the camera to it
]]

local Selection = game:GetService("Selection")
local TweenService = game:GetService("TweenService")

local ObjectTags = {}

-- Where the picker looks, in this order
local SEARCH_ROOTS = {
	"Workspace",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPlayer",
	"StarterPack",
	"Lighting",
	"SoundService",
}
local MAX_SCANNED = 20000 -- objects looked at per search, so huge places stay quick
local CAMERA_TIME = 0.6

-- The plugin's own folders aren't worth tagging
local HIDDEN = { TeamChatData = true, TeamChatPlugin = true, TeamChatTests = true, __TeamChatUnderTest = true }

function ObjectTags.pathOf(instance: Instance): string
	return instance:GetFullName()
end

--[=[
	The object a tag's path points at, or nil if it's gone. Names can
	contain dots, so each step tries the longest name that exists.
]=]
function ObjectTags.resolve(path: string): Instance?
	local parts = string.split(path, ".")
	local current: Instance = game
	local i = 1
	while i <= #parts do
		local found: Instance? = nil
		local used = 0
		for j = #parts, i, -1 do
			local name = table.concat(parts, ".", i, j)
			local child = current:FindFirstChild(name)
			if child then
				found, used = child, j - i + 1
				break
			end
		end
		if not found then
			return nil
		end
		current = found
		i += used
	end
	return if current ~= game then current else nil
end

local function isHidden(instance: Instance): boolean
	local current: Instance? = instance
	while current and current ~= game do
		if HIDDEN[current.Name] then
			return true
		end
		current = current.Parent
	end
	return false
end

--[=[
	Objects to tag whose name starts with `partial` (any case), the current
	selection first, up to `limit`.
]=]
function ObjectTags.search(partial: string, limit: number): { Instance }
	local query = string.lower(partial)
	local results, seen = {}, {}
	local function consider(instance: Instance): boolean
		if seen[instance] or isHidden(instance) then
			return false
		end
		if query == "" or string.sub(string.lower(instance.Name), 1, #query) == query then
			seen[instance] = true
			table.insert(results, instance)
		end
		return #results >= limit
	end
	for _, selected in ipairs(Selection:Get()) do
		if consider(selected) then
			return results
		end
	end
	if query == "" then
		return results -- just "#": what you have selected
	end
	local scanned = 0
	for _, rootName in ipairs(SEARCH_ROOTS) do
		local root = game:FindFirstChild(rootName)
		if root then
			for _, descendant in ipairs(root:GetDescendants()) do
				scanned += 1
				if scanned > MAX_SCANNED or consider(descendant) then
					return results
				end
			end
		end
	end
	return results
end

-- Where to look and how big the object is (nil when it has no position)
local function bounds(instance: Instance): (CFrame?, number?)
	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size.Magnitude
	elseif instance:IsA("Model") then
		local ok, cframe, size = pcall(function()
			return instance:GetBoundingBox()
		end)
		if ok then
			return cframe, size.Magnitude
		end
	elseif instance:IsA("Attachment") then
		return instance.WorldCFrame, 2
	end
	return nil, nil
end

--[=[
	Selects the object in Studio and, when it has a position, moves the
	camera to look at it (gliding there when `animate`). Returns whether
	the camera moved.
]=]
function ObjectTags.focus(instance: Instance, animate: boolean?): boolean
	Selection:Set({ instance })
	local center, size = bounds(instance)
	local camera = workspace.CurrentCamera
	if not center or not size or not camera then
		return false
	end
	-- Keep looking from the same direction, far enough to see all of it
	local direction = camera.CFrame.LookVector
	local distance = math.max(size * 1.2, 8)
	local target = CFrame.lookAt(center.Position - direction * distance, center.Position)
	if animate then
		TweenService:Create(
			camera,
			TweenInfo.new(CAMERA_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ CFrame = target, Focus = CFrame.new(center.Position) }
		):Play()
	else
		camera.CFrame = target
		camera.Focus = CFrame.new(center.Position)
	end
	return true
end

return ObjectTags
