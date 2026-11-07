--[[
	Messages/FileMessage

	A file message: the audio player card for audio, otherwise the generic file
	card (AttachmentCards). Cards stay between FILE_CARD_MIN_WIDTH and
	FILE_CARD_MAX_WIDTH wide.
]]

local Author = require(script.Parent.Author)
local AttachmentCards = require(script.Parent.Parent.Components.AttachmentCards)
local AudioPlayback = require(script.Parent.Parent.Components.AudioPlayback)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local MentionPills = require(script.Parent.Parent.Text.MentionPills)
local MessageText = require(script.Parent.Parent.Text.MessageText)
local Shared = require(script.Parent.Shared)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT
local FONTS = Theme.FONTS

local FileMessage = {}

-- File and audio cards fill the chat width between these bounds, so they
-- neither stretch across a wide widget nor squash in a narrow one.
local FILE_CARD_MIN_WIDTH = 100
local FILE_CARD_MAX_WIDTH = 250

function FileMessage.addCardBounds(card)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(FILE_CARD_MIN_WIDTH, 0)
	constraint.MaxSize = Vector2.new(FILE_CARD_MAX_WIDTH, math.huge)
	constraint.Parent = card
end

function FileMessage.create(sender, timestamp, content, fileName, fileUrl, fileType, themeColors, replyRef, senderId)
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

	Shared.addMessageSurface(container, themeColors)
	-- Real replies point at a message; the bot's "<name> used /command" line doesn't
	container:SetAttribute("ReplyToSenderId", if replyRef and replyRef.timestamp then replyRef.senderId else nil)

	-- Reply reference (reply arrow + name + preview)
	if replyRef and replyRef.sender then
		local replyRow = Shared.createReplyReference(replyRef, themeColors, true)
		replyRow.LayoutOrder = -1
		replyRow.Parent = container
	end

	-- File-type icons come from Icons.forFileType(fileType) (see fileIconLabel below).

	Author.attach(container, sender, senderId, timestamp, themeColors)
	Shared.applyMention(container, themeColors, content)

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
	MessageText.set(textLabel, content or "", themeColors)
	textLabel.Visible = (content or "") ~= ""
	MentionPills.attach(textLabel, themeColors)

	if fileType == "Audio" and fileUrl and fileUrl ~= "" then
		local audioCard = Instance.new("Frame")
		audioCard.Name = "AudioPlayerCard"
		audioCard.Size = UDim2.new(1, 0, 0, 68)
		audioCard.BackgroundColor3 = themeColors.menuBack
		audioCard.BorderSizePixel = 0
		audioCard.LayoutOrder = 2
		audioCard.Parent = container
		FileMessage.addCardBounds(audioCard)

		local audioCorner = Instance.new("UICorner")
		audioCorner.CornerRadius = UDim.new(0, 8)
		audioCorner.Parent = audioCard

		local audioStroke = Instance.new("UIStroke")
		audioStroke.Name = "CardStroke"
		audioStroke.Color = themeColors.imageBorder
		audioStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		audioStroke.Parent = audioCard

		local playButton = Instance.new("TextButton")
		playButton.Name = "PlayPauseButton"
		playButton.Size = UDim2.new(0, 32, 0, 32)
		playButton.Position = UDim2.new(0, 8, 0.5, -16)
		playButton.BackgroundColor3 = themeColors.sendButton
		Icons.apply(playButton, "play", true)
		playButton.TextColor3 = themeColors.sendButtonText
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

		-- Stable decorative bars; their color tracks the real playback position.
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
		if seed == 0 then
			seed = 1
		end

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
		end

		local timeLabel = Instance.new("TextLabel")
		timeLabel.Name = "PlaybackTime"
		timeLabel.Size = UDim2.new(1, -58, 0, 14)
		timeLabel.Position = UDim2.new(0, 48, 0, 48)
		timeLabel.BackgroundTransparency = 1
		timeLabel.TextColor3 = themeColors.timestamp
		timeLabel.FontFace = FONTS.mono
		timeLabel.TextSize = 11
		timeLabel.TextXAlignment = Enum.TextXAlignment.Left
		timeLabel.BorderSizePixel = 0
		timeLabel.ZIndex = 3
		timeLabel.Parent = audioCard

		AudioPlayback.wire(audioCard, fileUrl, themeColors)
	else
		AttachmentCards.createFile(container, fileName, fileUrl, fileType, themeColors, FileMessage.addCardBounds)
	end

	return container
end

return FileMessage
