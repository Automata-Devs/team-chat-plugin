--[[
	GifPlayer

	Animated GIFs for chat images. Roblox images can't animate, so a GIF is
	decoded (GifDecoder), its frames are packed into one sprite sheet image and
	uploaded like any other chat image. The image URL carries the sheet layout:

	  rbxassetid://123#gif=cols,rows,frameWidth,frameHeight,d1.d2.d3...

	(d = each frame's delay in ms). GifPlayer.apply shows any image URL on an
	ImageLabel and, for GIF URLs, steps ImageRectOffset through the frames.
	If the upload fails, the sheet stays a local EditableImage that only the
	sender can see.
]]

local AssetService = game:GetService("AssetService")

local GifDecoder = require(script.Parent.Parent.Parent.Util.GifDecoder)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)

local GifPlayer = {}

local MAX_FRAMES = 48
local SHEET_SIZE = 1024 -- largest EditableImage side
local MAX_FRAME_SIDE = 320 -- chat shows images at most 200x160
local LOCAL_PREFIX = "teamchat-local-gif://"

local localSheets: { [string]: EditableImage } = {}
local localCount = 0

type Animation = { offsets: { Vector2 }, delays: { number }, frame: number, nextAt: number }
local animations: { [ImageLabel]: Animation } = setmetatable({}, { __mode = "k" }) :: any
local loopRunning = false

--[=[
	Splits an image URL into its image part and GIF layout (nil for normal images).
]=]
function GifPlayer.parse(url: string?)
	if type(url) ~= "string" then
		return url, nil
	end
	local base, spec = string.match(url, "^(.-)#gif=(.+)$")
	if not base then
		return url, nil
	end
	local cols, rows, frameWidth, frameHeight, delayList = string.match(spec, "^(%d+),(%d+),(%d+),(%d+),([%d%.]+)$")
	if not cols then
		return base, nil
	end
	local delays = {}
	for delay in string.gmatch(delayList, "%d+") do
		table.insert(delays, math.max(20, tonumber(delay) :: number))
	end
	return base,
		{
			cols = tonumber(cols) :: number,
			rows = tonumber(rows) :: number,
			frameWidth = tonumber(frameWidth) :: number,
			frameHeight = tonumber(frameHeight) :: number,
			delays = delays,
		}
end

--[=[
	True when the URL is a GIF sprite sheet.
]=]
function GifPlayer.isGif(url: string?): boolean
	local _, layout = GifPlayer.parse(url)
	return layout ~= nil
end

local function runLoop()
	if loopRunning then
		return
	end
	loopRunning = true
	task.spawn(function()
		while Lifetime.alive and next(animations) do
			local now = os.clock()
			for label, animation in pairs(animations) do
				-- Labels get their image before they're parented, so unparented
				-- ones just wait; destroyed ones are removed (and the table is weak).
				if label.Parent and now >= animation.nextAt then
					animation.frame = animation.frame % #animation.offsets + 1
					label.ImageRectOffset = animation.offsets[animation.frame]
					animation.nextAt = now + animation.delays[animation.frame] / 1000
				end
			end
			task.wait(1 / 30)
		end
		loopRunning = false
	end)
end

--[=[
	Shows an image URL on an ImageLabel, animating it when it's a GIF.
	Also resets a label that showed a GIF before.
]=]
function GifPlayer.apply(label: ImageLabel, url: string?)
	animations[label] = nil
	label.ImageRectOffset = Vector2.zero
	label.ImageRectSize = Vector2.zero

	local base, layout = GifPlayer.parse(url)
	if not layout then
		label.Image = base or ""
		return
	end

	local localSheet = localSheets[base]
	if localSheet then
		label.ImageContent = Content.fromObject(localSheet)
	elseif string.sub(base, 1, #LOCAL_PREFIX) == LOCAL_PREFIX then
		label.Image = "" -- another person's local-only GIF
		return
	else
		label.Image = base
	end

	local offsets = {}
	for index = 0, #layout.delays - 1 do
		local col = index % layout.cols
		local row = index // layout.cols
		table.insert(offsets, Vector2.new(col * layout.frameWidth, row * layout.frameHeight))
	end
	label.ImageRectSize = Vector2.new(layout.frameWidth, layout.frameHeight)
	label.ImageRectOffset = offsets[1]
	if #offsets > 1 then
		animations[label] =
			{ offsets = offsets, delays = layout.delays, frame = 1, nextAt = os.clock() + layout.delays[1] / 1000 }
		label.Destroying:Once(function()
			animations[label] = nil
		end)
		runLoop()
	end
end

-- Picks the frame size and grid so every frame fits on one sheet.
local function planSheet(width: number, height: number, frames: number)
	local scale = math.min(1, MAX_FRAME_SIDE / math.max(width, height))
	while true do
		local frameWidth = math.max(1, math.floor(width * scale))
		local frameHeight = math.max(1, math.floor(height * scale))
		local cols = math.floor(SHEET_SIZE / frameWidth)
		local rows = math.floor(SHEET_SIZE / frameHeight)
		if cols * rows >= frames then
			cols = math.min(cols, frames)
			return frameWidth, frameHeight, cols, math.ceil(frames / cols)
		end
		scale *= 0.9
	end
end

--[=[
	Decodes GIF bytes into a sprite sheet. Returns the EditableImage and the
	"#gif=..." layout suffix.
]=]
function GifPlayer.buildSheet(data: string): (EditableImage, string)
	-- Read the frame count first so the sheet can be planned before decoding.
	local width, height = 0, 0
	local plan = nil
	local sheet: buffer? = nil
	local delays = {}

	local function onFrame(canvas: buffer, delay: number)
		table.insert(delays, delay)
		local index = #delays - 1
		local frameWidth, frameHeight, cols = plan[1], plan[2], plan[3]
		local sheetWidth = cols * frameWidth
		local originX = (index % cols) * frameWidth
		local originY = (index // cols) * frameHeight
		for y = 0, frameHeight - 1 do
			local sourceRow = math.floor(y * height / frameHeight) * width
			local targetRow = ((originY + y) * sheetWidth + originX) * 4
			for x = 0, frameWidth - 1 do
				local sourceX = math.floor(x * width / frameWidth)
				buffer.writeu32(sheet :: buffer, targetRow + x * 4, buffer.readu32(canvas, (sourceRow + sourceX) * 4))
			end
		end
		if index % 4 == 3 then
			task.wait()
		end -- keep Studio responsive
	end

	-- First pass learns size and frame count without keeping pixels.
	width, height =
		string.byte(data, 7) + string.byte(data, 8) * 256, string.byte(data, 9) + string.byte(data, 10) * 256
	local count = 0
	do
		local ok, err = pcall(GifDecoder.decode, data, MAX_FRAMES, function()
			count += 1
		end)
		if not ok then
			error(err, 0)
		end
	end
	local frameWidth, frameHeight, cols, rows = planSheet(width, height, count)
	plan = { frameWidth, frameHeight, cols }
	sheet = buffer.create(cols * frameWidth * rows * frameHeight * 4)
	GifDecoder.decode(data, MAX_FRAMES, onFrame)

	local size = Vector2.new(cols * frameWidth, rows * frameHeight)
	local image = AssetService:CreateEditableImage({ Size = size })
	image:WritePixelsBuffer(Vector2.zero, size, sheet :: buffer)
	local delayText = {}
	for _, delay in ipairs(delays) do
		table.insert(delayText, tostring(math.floor(delay)))
	end
	return image,
		string.format("#gif=%d,%d,%d,%d,%s", cols, rows, frameWidth, frameHeight, table.concat(delayText, "."))
end

--[=[
	Turns a GIF file from the file picker into a chat image URL. Uploads the
	sheet so everyone can see it; falls back to a local-only sheet.
	Returns the URL and whether it was uploaded.
]=]
function GifPlayer.fromFile(file: File): (string, boolean)
	local image, suffix = GifPlayer.buildSheet(file:GetBinaryContents())

	local ok, result, assetId = pcall(function()
		return AssetService:CreateAssetAsync(image, Enum.AssetType.Image, {
			Name = "TeamChat GIF",
			Description = "GIF shared via Team Chat plugin",
		})
	end)
	if ok and result == Enum.CreateAssetResult.Success and assetId then
		return "rbxassetid://" .. tostring(assetId) .. suffix, true
	end

	localCount += 1
	local key = LOCAL_PREFIX .. tostring(localCount)
	localSheets[key] = image
	return key .. suffix, false
end

return GifPlayer
