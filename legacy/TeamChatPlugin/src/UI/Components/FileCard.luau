--!
-- FileCard
-- Creates a file attachment container with support for audio, video, and generic file cards.
-- Includes interactive audio player with waveform and video player with controls.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local RichTextHelper = require(script.Parent.Parent.Parent.Utils.RichTextHelper)

local FONT = Theme.FONT
local MAX_IMAGE_HEIGHT = Theme.MAX_IMAGE_HEIGHT

local FileCard = {}

--!
-- Determines the emoji icon for a given file type.
-- @param fileType string
-- @return string - emoji icon
--!
local function getFileIcon(fileType)
	local fileIcon = "\u{1F4C4}"
	if fileType == "Audio" then
		fileIcon = "\u{1F3B5}"
	elseif fileType == "Video" then
		fileIcon = "\u{1F3AC}"
	elseif fileType == "Mesh" then
		fileIcon = "\u{1F9CA}"
	elseif fileType == "Model" then
		fileIcon = "\u{1F4E6}"
	elseif fileType == "Script" then
		fileIcon = "\u{1F4DC}"
	elseif fileType == "Text" then
		fileIcon = "\u{1F4DD}"
	end
	return fileIcon
end

--!
-- Creates a file attachment container.
-- @param sender string - display name of the sender
-- @param timestamp number - message timestamp
-- @param content string? - optional text content accompanying the file
-- @param fileName string - name of the file
-- @param fileUrl string - URL of the file (rbxassetid://...)
-- @param fileType string - type of the file (Audio, Video, Mesh, etc.)
-- @param themeColors table - current theme color palette
-- @return Frame - the file container
--!
function FileCard.create(sender, timestamp, content, fileName, fileUrl, fileType, themeColors)
	local container = Instance.new("Frame")
	container.Name = "File_" .. tostring(timestamp)
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Position = UDim2.new(0, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.LayoutOrder = timestamp
	container.BorderSizePixel = 0

	local containerLayout = Instance.new("UIListLayout")
	containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	containerLayout.Padding = UDim.new(0, -4)
	containerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	containerLayout.Parent = container

	local fileIcon = getFileIcon(fileType)

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextContent"
	textLabel.Font = FONT
	textLabel.TextSize = 14
	textLabel.TextColor3 = themeColors.messageText
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.new(1, 0, 0, 20)
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.RichText = true
	textLabel.TextWrapped = true
	textLabel.LayoutOrder = 1
	textLabel.BorderSizePixel = 0
	textLabel.Parent = container
	textLabel.Text = RichTextHelper.buildMessage(sender, content or "", timestamp, themeColors)

	if fileType == "Audio" and fileUrl and fileUrl ~= "" then
		FileCard._buildAudioPlayer(container, fileName, fileUrl, themeColors)
		return container
	end

	local fileCard = Instance.new("Frame")
	fileCard.Name = "FileCard"
	fileCard.Size = UDim2.new(1, 0, 0, 48)
	fileCard.BackgroundColor3 = themeColors.scrollBack
	fileCard.BorderColor3 = themeColors.imageBorder
	fileCard.BorderSizePixel = 1
	fileCard.LayoutOrder = 2
	fileCard.Parent = container

	local fileCardCorner = Instance.new("UICorner")
	fileCardCorner.CornerRadius = UDim.new(0, 6)
	fileCardCorner.Parent = fileCard

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "FileIcon"
	iconLabel.Size = UDim2.new(0, 28, 0, 28)
	iconLabel.Position = UDim2.new(0, 8, 0.5, -14)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = fileIcon
	iconLabel.TextSize = 18
	iconLabel.Font = FONT
	iconLabel.BorderSizePixel = 0
	iconLabel.Parent = fileCard

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "FileName"
	nameLabel.Size = UDim2.new(1, -120, 0, 20)
	nameLabel.Position = UDim2.new(0, 42, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = fileName
	nameLabel.TextColor3 = themeColors.menuItemText
	nameLabel.Font = Enum.Font.BuilderSansMedium
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.BorderSizePixel = 0
	nameLabel.Parent = fileCard

	local typeLabel = Instance.new("TextLabel")
	typeLabel.Name = "FileTypeLabel"
	typeLabel.Size = UDim2.new(1, -120, 0, 14)
	typeLabel.Position = UDim2.new(0, 42, 0, 26)
	typeLabel.BackgroundTransparency = 1
	typeLabel.Text = fileType
	typeLabel.TextColor3 = themeColors.timestamp
	typeLabel.Font = FONT
	typeLabel.TextSize = 11
	typeLabel.TextXAlignment = Enum.TextXAlignment.Left
	typeLabel.BorderSizePixel = 0
	typeLabel.Parent = fileCard

	local actionButton = Instance.new("TextButton")
	actionButton.Name = "ActionButton"
	actionButton.Size = UDim2.new(0, 60, 0, 28)
	actionButton.Position = UDim2.new(1, -68, 0.5, -14)
	actionButton.BackgroundColor3 = themeColors.dialogButton
	actionButton.TextColor3 = themeColors.dialogButtonText
	actionButton.Font = FONT
	actionButton.TextSize = 12
	actionButton.AutoButtonColor = true
	actionButton.BorderSizePixel = 0
	actionButton.Parent = fileCard

	local actionCorner = Instance.new("UICorner")
	actionCorner.CornerRadius = UDim.new(0, 6)
	actionCorner.Parent = actionButton

	if fileType == "Audio" and fileUrl and fileUrl ~= "" then
		actionButton.Text = "Play"
		local sound = Instance.new("Sound")
		sound.Name = "AudioPreview"
		sound.SoundId = fileUrl
		sound.Parent = fileCard
		local isPlaying = false
		actionButton.MouseButton1Click:Connect(function()
			if isPlaying then
				sound:Stop()
				actionButton.Text = "Play"
				isPlaying = false
			else
				sound:Play()
				actionButton.Text = "Stop"
				isPlaying = true
			end
		end)
		sound.Ended:Connect(function()
			actionButton.Text = "Play"
			isPlaying = false
		end)
	elseif fileType == "Video" then
		FileCard._buildVideoPlayer(container, fileUrl, themeColors, actionButton)
	else
		actionButton.Text = "Open"
		actionButton.MouseButton1Click:Connect(function()
			local assetIdStr = string.match(fileUrl or "", "rbxassetid://(%d+)")
			if assetIdStr then
				local InsertService = game:GetService("InsertService")
				pcall(function()
					local model = InsertService:LoadAssetAsync(tonumber(assetIdStr))
					if model then
						model.Parent = workspace
					end
				end)
			end
		end)
	end

	return container
end

--!
-- Builds the audio player card with waveform, play/pause, and seek support.
-- @param container Frame - parent container
-- @param fileName string
-- @param fileUrl string - audio asset URL
-- @param themeColors table
--!
function FileCard._buildAudioPlayer(container, fileName, fileUrl, themeColors)
	local audioCard = Instance.new("Frame")
	audioCard.Name = "AudioPlayerCard"
	audioCard.Size = UDim2.new(1, 0, 0, 68)
	audioCard.BackgroundColor3 = themeColors.menuBack
	audioCard.BorderColor3 = themeColors.imageBorder
	audioCard.BorderSizePixel = 1
	audioCard.LayoutOrder = 2
	audioCard.Parent = container

	local audioCorner = Instance.new("UICorner")
	audioCorner.CornerRadius = UDim.new(0, 8)
	audioCorner.Parent = audioCard

	local playButton = Instance.new("TextButton")
	playButton.Name = "PlayPauseButton"
	playButton.Size = UDim2.new(0, 32, 0, 32)
	playButton.Position = UDim2.new(0, 8, 0.5, -16)
	playButton.BackgroundColor3 = themeColors.sendButton
	playButton.Text = "\u{25B6}"
	playButton.TextColor3 = themeColors.sendButtonText
	playButton.Font = Enum.Font.BuilderSansBold
	playButton.TextSize = 16
	playButton.AutoButtonColor = true
	playButton.BorderSizePixel = 0
	playButton.ZIndex = 3
	playButton.Parent = audioCard

	local playCorner = Instance.new("UICorner")
	playCorner.CornerRadius = UDim.new(1, 0)
	playCorner.Parent = playButton

	local audioName = Instance.new("TextLabel")
	audioName.Name = "AudioFileName"
	audioName.Size = UDim2.new(1, -58, 0, 18)
	audioName.Position = UDim2.new(0, 48, 0, 5)
	audioName.BackgroundTransparency = 1
	audioName.Text = fileName
	audioName.TextColor3 = themeColors.menuItemText
	audioName.Font = Enum.Font.BuilderSansMedium
	audioName.TextSize = 13
	audioName.TextXAlignment = Enum.TextXAlignment.Left
	audioName.TextTruncate = Enum.TextTruncate.AtEnd
	audioName.BorderSizePixel = 0
	audioName.ZIndex = 3
	audioName.Parent = audioCard

	local waveform = Instance.new("Frame")
	waveform.Name = "Waveform"
	waveform.Size = UDim2.new(1, -58, 0, 20)
	waveform.Position = UDim2.new(0, 48, 0, 26)
	waveform.BackgroundTransparency = 1
	waveform.BorderSizePixel = 0
	waveform.Active = true
	waveform.ZIndex = 2
	waveform.Parent = audioCard

	local WAVE_BAR_COUNT = 40
	local waveformLayout = Instance.new("UIListLayout")
	waveformLayout.FillDirection = Enum.FillDirection.Horizontal
	waveformLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	waveformLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	waveformLayout.SortOrder = Enum.SortOrder.LayoutOrder
	waveformLayout.Padding = UDim.new(0, 1)
	waveformLayout.Parent = waveform

	local seed = 0
	for index = 1, #fileName do
		seed = (seed * 33 + string.byte(fileName, index)) % 2147483647
	end
	if seed == 0 then seed = 1 end

	local waveformBars = {}
	for index = 1, WAVE_BAR_COUNT do
		seed = (seed * 48271) % 2147483647
		local barHeight = 4 + (seed % 15)
		local bar = Instance.new("Frame")
		bar.Name = "WaveBar_" .. index
		bar.Size = UDim2.new(1 / WAVE_BAR_COUNT, -1, 0, barHeight)
		bar.BackgroundColor3 = themeColors.scrollBar
		bar.BorderSizePixel = 0
		bar.LayoutOrder = index
		bar.ZIndex = 3
		bar.Parent = waveform

		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(1, 0)
		barCorner.Parent = bar
		table.insert(waveformBars, bar)
	end

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "PlaybackTime"
	timeLabel.Size = UDim2.new(1, -58, 0, 14)
	timeLabel.Position = UDim2.new(0, 48, 0, 48)
	timeLabel.BackgroundTransparency = 1
	timeLabel.TextColor3 = themeColors.timestamp
	timeLabel.Font = FONT
	timeLabel.TextSize = 11
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.BorderSizePixel = 0
	timeLabel.ZIndex = 3
	timeLabel.Parent = audioCard

	local sound = Instance.new("Sound")
	sound.Name = "AudioPreview"
	sound.Parent = audioCard

	local function formatAudioTime(seconds)
		local wholeSeconds = math.max(0, math.floor(seconds))
		return string.format("%d:%02d", math.floor(wholeSeconds / 60), wholeSeconds % 60)
	end

	local function updateAudioDisplay()
		local duration = sound.TimeLength
		local currentTime = sound.TimePosition
		local progress = duration > 0 and math.clamp(currentTime / duration, 0, 1) or 0
		local durationText = duration > 0 and formatAudioTime(duration) or "--:--"
		timeLabel.Text = formatAudioTime(currentTime) .. " / " .. durationText
		playButton.Text = sound.IsPlaying and "||" or "\u{25B6}"

		for index, bar in ipairs(waveformBars) do
			local barProgress = (index - 1) / WAVE_BAR_COUNT
			bar.BackgroundColor3 = barProgress < progress and themeColors.sendButton or themeColors.scrollBar
		end
	end

	local playbackUpdaterRunning = false
	local function updateWhilePlaying()
		if playbackUpdaterRunning then return end
		playbackUpdaterRunning = true
		task.spawn(function()
			while sound.Parent and sound.IsPlaying do
				updateAudioDisplay()
				task.wait(0.05)
			end
			updateAudioDisplay()
			playbackUpdaterRunning = false
		end)
	end

	sound.Loaded:Connect(function()
		updateAudioDisplay()
		if sound.IsPlaying then updateWhilePlaying() end
	end)
	sound.Ended:Connect(updateAudioDisplay)
	sound.Stopped:Connect(updateAudioDisplay)
	container.AncestryChanged:Connect(function(_, parent)
		if parent == nil and sound.IsPlaying then
			sound:Stop()
		end
	end)

	playButton.MouseButton1Click:Connect(function()
		if sound.IsPlaying then
			sound:Pause()
		else
			if sound.TimeLength > 0 and sound.TimePosition >= sound.TimeLength then
				sound.TimePosition = 0
			end
			if sound.TimePosition > 0 then
				sound:Resume()
			else
				sound:Play()
			end
		end
		updateAudioDisplay()
		if sound.IsPlaying then updateWhilePlaying() end
	end)

	waveform.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and sound.TimeLength > 0 then
			local width = waveform.AbsoluteSize.X
			if width > 0 then
				local mouseX = game:GetService("UserInputService"):GetMouseLocation().X
				local progress = math.clamp((mouseX - waveform.AbsolutePosition.X) / width, 0, 1)
				sound.TimePosition = progress * sound.TimeLength
				updateAudioDisplay()
			end
		end
	end)

	sound.SoundId = fileUrl
	updateAudioDisplay()
end

--!
-- Builds the video player with controls, progress bar, and play overlay.
-- @param container Frame - parent container
-- @param fileUrl string - video asset URL
-- @param themeColors table
-- @param actionButton TextButton - the file card action button (hidden once video loads)
--!
function FileCard._buildVideoPlayer(container, fileUrl, themeColors, actionButton)
	actionButton.Text = "Loading"
	actionButton.Visible = false

	local videoFrame = Instance.new("VideoFrame")
	videoFrame.Name = "VideoPlayer"
	videoFrame.Size = UDim2.new(1, 0, 0, 200)
	videoFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	videoFrame.BorderSizePixel = 0
	videoFrame.Volume = 50
	videoFrame.Looped = false
	videoFrame.LayoutOrder = 3
	videoFrame.Parent = container

	local videoCorner = Instance.new("UICorner")
	videoCorner.CornerRadius = UDim.new(0, 6)
	videoCorner.Parent = videoFrame

	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.Name = "LoadingLabel"
	loadingLabel.Size = UDim2.new(1, 0, 1, 0)
	loadingLabel.BackgroundTransparency = 1
	loadingLabel.Text = "Loading video..."
	loadingLabel.TextColor3 = themeColors.loadingText
	loadingLabel.Font = FONT
	loadingLabel.TextSize = 13
	loadingLabel.ZIndex = 5
	loadingLabel.Parent = videoFrame

	local errorLabel = Instance.new("TextLabel")
	errorLabel.Name = "ErrorLabel"
	errorLabel.Size = UDim2.new(1, 0, 1, 0)
	errorLabel.BackgroundTransparency = 1
	errorLabel.Text = "Video not available (local-only or unsupported format)"
	errorLabel.TextColor3 = themeColors.loadingText
	errorLabel.Font = FONT
	errorLabel.TextSize = 12
	errorLabel.ZIndex = 5
	errorLabel.Visible = false
	errorLabel.Parent = videoFrame

	local playOverlay = Instance.new("TextButton")
	playOverlay.Name = "PlayOverlay"
	playOverlay.Size = UDim2.new(0, 48, 0, 48)
	playOverlay.Position = UDim2.new(0.5, -24, 0.5, -24)
	playOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	playOverlay.BackgroundTransparency = 0.4
	playOverlay.Text = "\u{25B6}"
	playOverlay.TextColor3 = Color3.new(1, 1, 1)
	playOverlay.Font = Enum.Font.BuilderSansBold
	playOverlay.TextSize = 24
	playOverlay.AutoButtonColor = false
	playOverlay.ZIndex = 4
	playOverlay.Visible = false
	playOverlay.Parent = videoFrame

	local playOverlayCorner = Instance.new("UICorner")
	playOverlayCorner.CornerRadius = UDim.new(1, 0)
	playOverlayCorner.Parent = playOverlay

	local controlsBar = Instance.new("Frame")
	controlsBar.Name = "ControlsBar"
	controlsBar.Size = UDim2.new(1, 0, 0, 32)
	controlsBar.Position = UDim2.new(0, 0, 1, -32)
	controlsBar.BackgroundColor3 = Color3.new(0, 0, 0)
	controlsBar.BackgroundTransparency = 0.3
	controlsBar.BorderSizePixel = 0
	controlsBar.ZIndex = 3
	controlsBar.Visible = false
	controlsBar.Parent = videoFrame

	local controlsCorner = Instance.new("UICorner")
	controlsCorner.CornerRadius = UDim.new(0, 6)
	controlsCorner.Parent = controlsBar

	local progressBg = Instance.new("Frame")
	progressBg.Name = "ProgressBg"
	progressBg.Size = UDim2.new(1, -20, 0, 6)
	progressBg.Position = UDim2.new(0, 10, 0, 8)
	progressBg.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	progressBg.BorderSizePixel = 0
	progressBg.Active = true
	progressBg.ZIndex = 4
	progressBg.Parent = controlsBar

	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(1, 0)
	progressCorner.Parent = progressBg

	local progressFill = Instance.new("Frame")
	progressFill.Name = "ProgressFill"
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = themeColors.sendButton
	progressFill.BorderSizePixel = 0
	progressFill.ZIndex = 5
	progressFill.Parent = progressBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = progressFill

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "TimeLabel"
	timeLabel.Size = UDim2.new(1, -52, 0, 14)
	timeLabel.Position = UDim2.new(0, 32, 0, 16)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Text = "0:00 / 0:00"
	timeLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	timeLabel.Font = FONT
	timeLabel.TextSize = 11
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.ZIndex = 4
	timeLabel.Parent = controlsBar

	local controlPlayButton = Instance.new("TextButton")
	controlPlayButton.Name = "ControlPlayButton"
	controlPlayButton.Size = UDim2.new(0, 18, 0, 14)
	controlPlayButton.Position = UDim2.new(0, 9, 0, 16)
	controlPlayButton.BackgroundTransparency = 1
	controlPlayButton.Text = "\u{25B6}"
	controlPlayButton.TextColor3 = Color3.new(1, 1, 1)
	controlPlayButton.Font = Enum.Font.BuilderSansBold
	controlPlayButton.TextSize = 11
	controlPlayButton.AutoButtonColor = false
	controlPlayButton.BorderSizePixel = 0
	controlPlayButton.ZIndex = 4
	controlPlayButton.Parent = controlsBar

	local isVideoPlaying = false
	local videoReady = false
	local videoLoaded = false

	local function formatTime(seconds)
		local mins = math.floor(seconds / 60)
		local secs = math.floor(seconds % 60)
		return string.format("%d:%02d", mins, secs)
	end

	local function updatePlayControls()
		isVideoPlaying = videoFrame.Playing
		local symbol = isVideoPlaying and "\u{23F8}" or "\u{25B6}"
		playOverlay.Text = symbol
		playOverlay.Visible = not isVideoPlaying
		controlPlayButton.Text = symbol
	end

	local function markVideoLoaded()
		if videoLoaded then return end
		videoReady = true
		videoLoaded = true
		loadingLabel.Visible = false
		errorLabel.Visible = false
		playOverlay.Visible = true
		controlsBar.Visible = true
		actionButton.Visible = false
		updatePlayControls()
		local total = videoFrame.TimeLength
		if total and total > 0 then
			timeLabel.Text = "0:00 / " .. formatTime(total)
		end
	end

	videoFrame.Loaded:Connect(markVideoLoaded)
	videoFrame.Played:Connect(updatePlayControls)
	videoFrame.Paused:Connect(updatePlayControls)

	task.spawn(function()
		local deadline = os.clock() + 15
		while videoFrame.Parent and not videoLoaded and os.clock() < deadline do
			if videoFrame.IsLoaded then
				markVideoLoaded()
				break
			end
			task.wait(0.1)
		end
		if videoFrame.Parent and not videoLoaded then
			loadingLabel.Visible = false
			errorLabel.Text = "Video unavailable. Use a Roblox-uploaded video asset ID."
			errorLabel.Visible = true
			playOverlay.Visible = false
			controlsBar.Visible = false
		end
	end)

	local function togglePlay()
		if not videoReady then return end
		if videoFrame.Playing then
			videoFrame:Pause()
		else
			videoFrame:Play()
		end
		updatePlayControls()
	end

	playOverlay.MouseButton1Click:Connect(togglePlay)
	controlPlayButton.MouseButton1Click:Connect(togglePlay)

	progressBg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and videoReady then
			local mousePos = game:GetService("UserInputService"):GetMouseLocation()
			local barPos = progressBg.AbsolutePosition
			local barSize = progressBg.AbsoluteSize
			local relativeX = math.clamp((mousePos.X - barPos.X) / barSize.X, 0, 1)
			local total = videoFrame.TimeLength
			if total and total > 0 then
				videoFrame.TimePosition = relativeX * total
			end
		end
	end)

	task.spawn(function()
		while videoFrame.Parent do
			task.wait(0.1)
			if videoReady and videoFrame.TimeLength and videoFrame.TimeLength > 0 then
				local current = videoFrame.TimePosition or 0
				local total = videoFrame.TimeLength
				progressFill.Size = UDim2.new(current / total, 0, 1, 0)
				timeLabel.Text = formatTime(current) .. " / " .. formatTime(total)
			end
		end
	end)

	videoFrame.Ended:Connect(function()
		videoFrame.TimePosition = 0
		updatePlayControls()
		progressFill.Size = UDim2.new(0, 0, 1, 0)
	end)

	task.defer(function()
		if not container.Parent or not videoFrame.Parent then return end
		local sourceOk = pcall(function()
			videoFrame.Video = fileUrl
		end)
		if not sourceOk or type(fileUrl) ~= "string" or fileUrl == "" then
			videoLoaded = true
			loadingLabel.Visible = false
			errorLabel.Text = "Video unavailable. Use a Roblox-uploaded video asset ID."
			errorLabel.Visible = true
		end
	end)
end

--!
-- Re-themes a file container.
-- @param container Frame - the file container
-- @param themeColors table - current theme color palette
--!
function FileCard.recolor(container, themeColors)
	local sender = container:GetAttribute("Sender")
	local content = container:GetAttribute("Content")
	local timestamp = container:GetAttribute("Timestamp")
	if not sender or not timestamp then return end
	if content == nil then content = "" end

	local textLabel = container:FindFirstChild("TextContent")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.TextColor3 = themeColors.messageText
		textLabel.Text = RichTextHelper.buildMessage(sender, content, timestamp, themeColors)
	end

	local fileCard = container:FindFirstChild("FileCard")
	if fileCard and fileCard:IsA("Frame") then
		fileCard.BackgroundColor3 = themeColors.scrollBack
		fileCard.BorderColor3 = themeColors.imageBorder
		local fName = fileCard:FindFirstChild("FileName")
		if fName then
			fName.TextColor3 = themeColors.menuItemText
		end
		local fType = fileCard:FindFirstChild("FileTypeLabel")
		if fType then
			fType.TextColor3 = themeColors.timestamp
		end
		local fBtn = fileCard:FindFirstChild("ActionButton")
		if fBtn then
			fBtn.BackgroundColor3 = themeColors.dialogButton
			fBtn.TextColor3 = themeColors.dialogButtonText
		end
	end

	local videoFrame = container:FindFirstChild("VideoPlayer")
	if videoFrame and videoFrame:IsA("VideoFrame") then
		local loadingLabel = videoFrame:FindFirstChild("LoadingLabel")
		if loadingLabel then
			loadingLabel.TextColor3 = themeColors.loadingText
		end
		local errorLabel = videoFrame:FindFirstChild("ErrorLabel")
		if errorLabel then
			errorLabel.TextColor3 = themeColors.loadingText
		end
		local controlsBar = videoFrame:FindFirstChild("ControlsBar")
		if controlsBar then
			local progressBg = controlsBar:FindFirstChild("ProgressBg")
			if progressBg then
				local fillBar = progressBg:FindFirstChild("ProgressFill")
				if fillBar then
					fillBar.BackgroundColor3 = themeColors.sendButton
				end
			end
		end
	end
end

return FileCard