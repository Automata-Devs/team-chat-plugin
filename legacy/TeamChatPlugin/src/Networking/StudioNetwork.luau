--!
-- StudioNetwork
-- Manages Studio-specific collaboration features: instance claiming
-- and camera position sharing between collaborators via a shared DataModel folder.
--!

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PluginConfig = require(script.Parent.Parent.Config.PluginConfig)
local RankManager = require(script.Parent.Admin.RankManager)
local PlaceStorage = require(script.Parent.PlaceStorage)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)

local StudioNetwork = {}

local STUDIO_FOLDER_NAME = "_TeamChatStudio"
local studioFolder: Folder?
local cameraUpdateConnection: RBXScriptConnection?

--!
-- Returns (or lazily creates) the shared studio folder in the place
-- (ServerStorage.TeamChatData._TeamChatStudio, see PlaceStorage).
--!
local function getFolder(): Folder
	if studioFolder and studioFolder.Parent then
		return studioFolder
	end

	local folder = PlaceStorage.getFolder(STUDIO_FOLDER_NAME)
	studioFolder = folder
	return folder
end

--!
-- Serializes a CFrame to a comma-separated string of its 12 components.
--!
local function serializeCFrame(cf: CFrame): string
	local c = cf:GetComponents()
	return string.format("%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f", c)
end

--!
-- Deserializes a CFrame from a comma-separated string.
--!
local function deserializeCFrame(str: string): CFrame?
	local nums = {}
	for n in str:gmatch("%-?%d+%.?%d*") do
		table.insert(nums, tonumber(n))
	end
	if #nums ~= 12 then return nil end
	return CFrame.new(
		nums[1], nums[2], nums[3],
		nums[4], nums[5], nums[6],
		nums[7], nums[8], nums[9],
		nums[10], nums[11], nums[12]
	)
end

--!
-- Initializes the studio network. Starts camera position broadcasting.
--!
function StudioNetwork.init()
	getFolder()

	-- Periodically store the current camera CFrame for collaborators
	if RunService:IsEdit() then
		local camera = workspace.CurrentCamera
		if camera then
			local function updateCamera()
				local userId = RankManager.getUserId()
				if userId <= 0 then return end
				local attrFolder = getFolder()
				local camAttr = "cam_" .. tostring(userId)
				attrFolder:SetAttribute(camAttr, serializeCFrame(camera.CFrame))
			end
			cameraUpdateConnection = Lifetime.connect(RunService.RenderStepped, function()
				updateCamera()
			end)
		end
	end
end

--!
-- Claims an instance for the given user. Returns (true, nil) on success,
-- or (false, ownerName) if already claimed by someone else.
--!
function StudioNetwork.claim(instance: Instance, userId: number, note: string?): (boolean, string?)
	local folder = getFolder()
	local key = "claim_" .. instance:GetFullName()
	-- Replace dots with underscores for attribute name safety
	key = key:gsub("%.", "_")
	key = key:gsub("%s", "_")

	-- Attribute names have a 100-char limit; hash if too long
	if #key > 95 then
		key = key:sub(1, 95)
	end

	local existing = folder:GetAttribute(key)
	if existing then
		local existingUserId = tonumber(existing:match("^%d+")) or 0
		if existingUserId ~= userId then
			local ownerName = "Unknown"
			local ok, name = pcall(function()
				return Players:GetNameFromUserIdAsync(existingUserId)
			end)
			if ok and name then ownerName = name end
			return false, ownerName
		end
	end

	folder:SetAttribute(key, tostring(userId) .. "|" .. (note or ""))
	return true, nil
end

--!
-- Removes a claim on an instance.
--!
function StudioNetwork.unclaim(instance: Instance)
	local folder = getFolder()
	local key = "claim_" .. instance:GetFullName()
	key = key:gsub("%.", "_")
	key = key:gsub("%s", "_")
	if #key > 95 then
		key = key:sub(1, 95)
	end
	folder:SetAttribute(key, nil)
end

--!
-- Returns the camera CFrame for a given user, or nil if not available.
--!
function StudioNetwork.getUserCameraCFrame(userId: number): CFrame?
	local folder = getFolder()
	local camAttr = "cam_" .. tostring(userId)
	local str = folder:GetAttribute(camAttr)
	if not str or str == "" then return nil end
	return deserializeCFrame(str)
end

return StudioNetwork