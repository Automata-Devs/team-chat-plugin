--!strict
--[[
	StudioCollab

	Studio collaboration helpers shared through the place
	(ServerStorage.TeamChatData._TeamChatStudio):
	  - claims: "I'm editing this" markers on instances (/claim)
	  - camera positions: each user's camera, so others can jump to it (/goto)

	The camera is published only when it moves, at most every
	CAMERA_PUBLISH_INTERVAL seconds (Team Create replicates every write).

	Usage:
		StudioCollab.init()                                  -- once, in App
		local ok, owner = StudioCollab.claim(part, userId, "fixing lights")
		local cframe = StudioCollab.getUserCameraCFrame(userId)
]]

local Constants = require(script.Parent.Parent.Config.Constants)
local Identity = require(script.Parent.Parent.Core.Identity)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local PlaceStorage = require(script.Parent.Parent.Core.PlaceStorage)

local CAMERA_PUBLISH_INTERVAL = 1 -- seconds
local ATTRIBUTE_NAME_LIMIT = 100

local StudioCollab = {}

local function getFolder(): Folder
	return PlaceStorage.getFolder(Constants.STUDIO_FOLDER_NAME)
end

-- "12 numbers separated by commas" <-> CFrame
local function serializeCFrame(cframe: CFrame): string
	local parts = table.pack(cframe:GetComponents())
	for index = 1, parts.n do
		parts[index] = string.format("%.4f", parts[index])
	end
	return table.concat(parts, ",", 1, parts.n)
end

local function deserializeCFrame(text: string): CFrame?
	local numbers = {}
	for value in string.gmatch(text, "[^,]+") do
		local number = tonumber(value)
		if not number then
			return nil
		end
		table.insert(numbers, number)
	end
	if #numbers ~= 12 then
		return nil
	end
	return CFrame.new(table.unpack(numbers))
end

-- Attribute name for an instance's claim (attribute names allow [%w_], max 100 chars)
local function claimKey(instance: Instance): string
	local key = "claim_" .. string.gsub(instance:GetFullName(), "[^%w_]", "_")
	return string.sub(key, 1, ATTRIBUTE_NAME_LIMIT - 5)
end

--[=[
	Starts sharing this user's camera position with collaborators.
]=]
function StudioCollab.init()
	getFolder()
	local userId = Identity.userId
	if userId <= 0 then
		return
	end

	local attribute = "cam_" .. tostring(userId)
	local lastPublished = 0
	local pending = false
	local camera: Camera? = nil
	local cameraConnection: RBXScriptConnection? = nil

	local function publish()
		pending = false
		if camera and Lifetime.alive then
			lastPublished = os.clock()
			getFolder():SetAttribute(attribute, serializeCFrame(camera.CFrame))
		end
	end

	local function onCameraMoved()
		if pending then
			return
		end
		pending = true
		local wait = math.max(0, CAMERA_PUBLISH_INTERVAL - (os.clock() - lastPublished))
		Lifetime.delay(wait, publish)
	end

	local function watch(newCamera: Camera?)
		if cameraConnection then
			cameraConnection:Disconnect()
		end
		camera = newCamera
		if newCamera then
			cameraConnection = Lifetime.connect(newCamera:GetPropertyChangedSignal("CFrame"), onCameraMoved)
			onCameraMoved()
		end
	end

	watch(workspace.CurrentCamera)
	Lifetime.connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
		watch(workspace.CurrentCamera)
	end)
end

--[=[
	Claims an instance for a user. Returns (true, nil) on success, or
	(false, ownerName) when someone else already claimed it.
]=]
function StudioCollab.claim(instance: Instance, userId: number, note: string?): (boolean, string?)
	local folder = getFolder()
	local key = claimKey(instance)
	local existing = folder:GetAttribute(key)
	if type(existing) == "string" then
		local ownerId = tonumber(string.match(existing, "^%d+")) or 0
		if ownerId ~= userId then
			return false, Identity.nameOf(ownerId) or "Unknown"
		end
	end
	folder:SetAttribute(key, tostring(userId) .. "|" .. (note or ""))
	return true, nil
end

--[=[
	Removes a claim on an instance.
]=]
function StudioCollab.unclaim(instance: Instance)
	getFolder():SetAttribute(claimKey(instance), nil)
end

--[=[
	A user's last shared camera CFrame, or nil if they haven't shared one.
]=]
function StudioCollab.getUserCameraCFrame(userId: number): CFrame?
	local value = getFolder():GetAttribute("cam_" .. tostring(userId))
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return deserializeCFrame(value)
end

return StudioCollab
