--!
-- AudioPlayback
-- Makes the audio card in a file message playable: play/pause, a progress
-- waveform, the playback time and click-to-seek.
--
-- Sound doesn't play in Studio's edit mode, so this uses the audio API
-- (AudioPlayer wired to an AudioDeviceOutput), which does. Everything lives
-- under the card inside the plugin widget; the widget isn't part of the place,
-- so nothing replicates and only the person who pressed play hears it.
-- Only one card plays at a time; see MediaFocus.
--!

local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local MediaFocus = require(script.Parent.MediaFocus)

local LOAD_TIMEOUT = 10

local AudioPlayback = {}


local function formatTime(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

--!
-- Wires up an audio card built by ChatUI (PlayPauseButton, Waveform with
-- WaveBar_n children, PlaybackTime).
--!
function AudioPlayback.wire(card: Frame, fileUrl: string, themeColors)
	local playButton = card:FindFirstChild("PlayPauseButton") :: TextButton
	local waveform = card:FindFirstChild("Waveform") :: Frame
	local timeLabel = card:FindFirstChild("PlaybackTime") :: TextLabel

	local bars = {}
	for _, child in ipairs(waveform:GetChildren()) do
		local index = tonumber(string.match(child.Name, "^WaveBar_(%d+)$"))
		if index then bars[index] = child end
	end

	local player = Instance.new("AudioPlayer")
	player.Name = "AudioPreview"
	player.Volume = 1
	player.Parent = card

	local output = Instance.new("AudioDeviceOutput")
	output.Name = "AudioOutput"
	output.Parent = card

	local wire = Instance.new("Wire")
	wire.SourceInstance = player
	wire.TargetInstance = output
	wire.Parent = card

	local failed = false

	local function render()
		if failed then return end
		local duration = player.TimeLength
		local position = player.TimePosition
		local progress = if duration > 0 then math.clamp(position / duration, 0, 1) else 0
		timeLabel.Text = formatTime(position) .. " / " .. (if duration > 0 then formatTime(duration) else "--:--")
		Icons.apply(playButton, if player.IsPlaying then "pause" else "play", true)
		for index, bar in ipairs(bars) do
			bar.BackgroundColor3 = if (index - 1) / #bars < progress then themeColors.sendButton else themeColors.scrollBar
		end
	end

	local function fail()
		failed = true
		timeLabel.Text = "Can't load this audio. Local files only play for the sender."
		playButton.AutoButtonColor = false
		playButton.BackgroundTransparency = 0.5
	end

	local ticking = false
	local function tickWhilePlaying()
		if ticking then return end
		ticking = true
		task.spawn(function()
			while card.Parent and player.IsPlaying do
				render()
				task.wait(0.05)
			end
			ticking = false
			if card.Parent then render() end
		end)
	end

	local function waitUntilReady(): boolean
		local started = os.clock()
		while not player.IsReady and os.clock() - started < LOAD_TIMEOUT do
			task.wait(0.1)
		end
		return player.IsReady
	end

	local function play()
		MediaFocus.claim(player, function()
			player:Stop()
		end)
		if player.TimeLength > 0 and player.TimePosition >= player.TimeLength - 0.05 then
			player.TimePosition = 0
		end
		player:Play()
		render()
		tickWhilePlaying()
	end

	playButton.MouseButton1Click:Connect(function()
		if failed then return end
		if player.IsPlaying then
			player:Stop() -- Stop keeps TimePosition, so it acts as pause
			render()
			return
		end
		if player.IsReady then
			play()
			return
		end
		timeLabel.Text = "Loading..."
		task.spawn(function()
			if waitUntilReady() then
				play()
			else
				fail()
			end
		end)
	end)

	waveform.InputBegan:Connect(function(input)
		if failed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		local width = waveform.AbsoluteSize.X
		if width <= 0 or player.TimeLength <= 0 then return end
		local progress = math.clamp((input.Position.X - waveform.AbsolutePosition.X) / width, 0, 1)
		player.TimePosition = progress * player.TimeLength
		render()
	end)

	player.Ended:Connect(function()
		player.TimePosition = 0
		render()
	end)

	card.Destroying:Connect(function()
		MediaFocus.release(player)
	end)
	card.AncestryChanged:Connect(function(_, parent)
		if parent == nil then player:Stop() end
	end)

	player.Asset = fileUrl
	render()

	-- Show the length once it's known, without starting playback.
	task.spawn(function()
		if waitUntilReady() and card.Parent and not player.IsPlaying then render() end
	end)
end

return AudioPlayback
