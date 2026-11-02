--!
-- ChatUI
-- Builds and manages the dock widget GUI for the TeamChat plugin.
-- Adaptive theme: matches Roblox Studio's light/dark mode automatically.
-- Supports image attachments via local file picker (StudioService:PromptImportFile).
-- Images are uploaded as permanent Roblox assets so they sync across Team Create.
-- Supports drag-and-drop of attachments via PluginGui.PluginDrag* events and Plugin:StartDrag().
--!

local ServerScriptService = game:GetService("ServerScriptService")
local StudioService = game:GetService("StudioService")
local AssetService = game:GetService("AssetService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UsernameColors = require(script.Parent.Parent.Utils.UsernameColors)
local TimeFormatter = require(script.Parent.Parent.Utils.TimeFormatter)
local AdminNetwork = require(script.Parent.Parent.Networking.AdminNetwork)
local Theme = require(script.Parent.Parent.Config.Theme)
local RichTextHelper = require(script.Parent.Parent.Utils.RichTextHelper)
local LinkHelper = require(script.Parent.Parent.Utils.LinkHelper)
local EmbedManager = require(script.Parent.Embeds.EmbedManager)
local Autocomplete = require(script.Parent.Components.Autocomplete)
local PluginConfig = require(script.Parent.Parent.Config.PluginConfig)
local Icons = require(script.Parent.Parent.Config.Icons)
local AudioPlayback = require(script.Parent.Components.AudioPlayback)
local GifPlayer = require(script.Parent.Components.GifPlayer)
local AttachmentCards = require(script.Parent.Components.AttachmentCards)
local ConversationList = require(script.Parent.Components.ConversationList)
local EmojiData = require(script.Parent.Parent.Utils.EmojiData)
local UsageTracker = require(script.Parent.Parent.Utils.UsageTracker)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local ChangelogDialog = require(script.Parent.ChangelogDialog)
local ModalKit = require(script.Parent.ModalKit)
local SettingsDialog = require(script.Parent.SettingsDialog)
local CreatePollDialog = require(script.Parent.CreatePollDialog)
local NewMessageDialog = require(script.Parent.NewMessageDialog)

-- Local aliases for theme and config constants (kept for readability)
local DEVELOPMENT_MODE = PluginConfig.DEVELOPMENT_MODE
local PLUGIN_VERSION = PluginConfig.PLUGIN_VERSION

local THEMES = Theme.PALETTES
local FONT = Theme.FONT
local FONTS = Theme.FONTS
local MAX_IMAGE_HEIGHT = Theme.MAX_IMAGE_HEIGHT
local IMAGE_FILTER = Theme.IMAGE_FILTER
local FILE_EXTENSIONS = Theme.FILE_EXTENSIONS
local INPUT_HEIGHT = Theme.INPUT_HEIGHT
local PREVIEW_HEIGHT = Theme.PREVIEW_HEIGHT
local MENU_WIDTH = Theme.MENU_WIDTH
local MAX_POLL_OPTIONS = Theme.MAX_POLL_OPTIONS

-- Message text size options (pixel sizes), configurable in the Settings dialog.
local TEXT_SIZES = { Small = 12, Default = 14, Large = 16 }
local messageTextSize = TEXT_SIZES.Default

-- Layout and timing constants used inside ChatUI.create
local HEADER_HEIGHT = 36
local ATTACHMENT_MIME_TYPE = "application/x-teamchat-attachment"
local CONTEXT_MENU_CURSOR_OFFSET = 2
local CONTEXT_MENU_EDGE_MARGIN = 4
local DANGER_HOVER_TRANSPARENCY = 0.85 -- red tint behind a hovered destructive item
local JUMP_SCROLL_TIME = 0.3
local FLASH_HOLD_TIME = 0.6
local FLASH_FADE_TIME = 1.2
local FLASH_START_TRANSPARENCY = 0.75
local SCROLL_BOTTOM_THRESHOLD = 24
local MAX_INPUT_HEIGHT = 240
local REPLY_BAR_HEIGHT = 30

local ChatUI = {}

--!
-- Detects the current Roblox Studio theme.
-- Delegates to the centralized Theme module.
--!
local function detectTheme()
	return Theme.detect()
end

--!
-- Converts a Color3 to a hex string for RichText <font color> tags.
-- Delegates to the centralized Theme module.
--!
local function toHex(color)
	return Theme.toHex(color)
end

--!
-- Builds the rich text content for a message's text label.
-- Delegates to the centralized RichTextHelper module.
--!
local function buildRichText(sender, content, timestamp, themeColors)
	return RichTextHelper.buildMessage(sender, content, timestamp, themeColors)
end

--!
-- Builds the header line of an announcement card:
-- megaphone + "Announcement" (Builder Extended) + sender + timestamp (Builder Mono).
--!
local function buildAnnouncementHeader(sender, timestamp, themeColors)
	return string.format(
		'<font color="%s">%s %sAnnouncement</font></font>  ·  <font color="%s"><b>%s</b></font>  ·  <font color="%s">%s%s</font></font>',
		toHex(themeColors.sendButton),
		Icons.inline("announcement"),
		Theme.richFont("extended", "bold"),
		toHex(UsernameColors.getNameColor(sender)),
		RichTextHelper.escape(sender),
		toHex(themeColors.timestamp),
		Theme.richFont("mono"),
		TimeFormatter.format(timestamp)
	)
end

-- Scrolls to a message by timestamp and flashes it. Assigned in ChatUI.create
-- (it needs the scroll frame); reply rows call it when clicked.
local jumpToMessage: ((number) -> ())? = nil

local REPLY_ROW_HEIGHT = 22
local REPLY_PREVIEW_MAX_LENGTH = 100
local REPLY_NAME_TRANSPARENCY = 0.5 -- the replied-to username is drawn at half opacity

--!
-- Creates the line shown above a reply: the Builder Icons reply arrow, the
-- original author's name and a one-line preview. Clicking it scrolls to the
-- original message and flashes it (see jumpToMessage).
-- The label is named "ReplyLabel" (markReplyDeleted rewrites it).
-- The caller sets LayoutOrder and Parent.
--!
local function createReplyReference(replyRef, themeColors)
	local replyColor = UsernameColors.getNameColor(replyRef.sender)

	local row = Instance.new("Frame")
	row.Name = "ReplyReference"
	row.Size = UDim2.new(1, 0, 0, REPLY_ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0

	-- Reply arrow (Builder Icons)
	local replyIcon = Instance.new("TextLabel")
	replyIcon.Name = "ReplyIcon"
	replyIcon.Position = UDim2.fromOffset(4, 0)
	replyIcon.Size = UDim2.new(0, 14, 1, 0)
	replyIcon.BackgroundTransparency = 1
	Icons.apply(replyIcon, "reply")
	replyIcon.TextColor3 = themeColors.timestamp
	replyIcon.TextSize = 14
	replyIcon.Parent = row

	-- Name in the author's color + muted single-line preview
	local preview = string.gsub(replyRef.content or "", "%s+", " ")
	local previewLength = utf8.len(preview)
	if previewLength and previewLength > REPLY_PREVIEW_MAX_LENGTH then
		preview = string.sub(preview, 1, utf8.offset(preview, REPLY_PREVIEW_MAX_LENGTH + 1) - 1) .. "\u{2026}"
	end
	local previewText = if preview == "" then "<i>Attachment</i>" else Icons.escape(preview)

	local label = Instance.new("TextLabel")
	label.Name = "ReplyLabel"
	label.Position = UDim2.fromOffset(23, 0)
	label.Size = UDim2.new(1, -29, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = FONTS.body
	label.TextSize = 13
	label.TextColor3 = themeColors.timestamp
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.RichText = true
	label.Text = string.format(
		'<font color="%s" weight="semibold" transparency="%.2f">%s</font>  %s',
		toHex(replyColor),
		REPLY_NAME_TRANSPARENCY,
		Icons.escape(replyRef.sender),
		previewText
	)
	label.Parent = row

	-- Hover: brighter text (plugins can't change the cursor); click jumps to the original
	row.MouseEnter:Connect(function()
		label.TextColor3 = themeColors.messageText
		replyIcon.TextColor3 = themeColors.messageText
	end)
	row.MouseLeave:Connect(function()
		label.TextColor3 = themeColors.timestamp
		replyIcon.TextColor3 = themeColors.timestamp
	end)
	row.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and jumpToMessage and replyRef.timestamp then
			jumpToMessage(replyRef.timestamp)
		end
	end)

	return row
end


--!
-- Gives a message container a rounded, normally invisible background that
-- the jump-to-reply flash lights up (see flashMessage). recolorMessageContainer
-- keeps its color in sync with the theme via the HoverHighlight attribute.
--!
local function addMessageSurface(container, themeColors)
	container.BackgroundColor3 = themeColors.menuItemHover
	container.BackgroundTransparency = 1
	container:SetAttribute("HoverHighlight", true)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.PaddingTop = UDim.new(0, 2)
	padding.PaddingBottom = UDim.new(0, 2)
	padding.Parent = container
end

--!
-- Creates a message container (Frame) with optional inline image.
--!
local function createMessageContainer(sender, timestamp, content, imageUrl, themeColors, replyRef)
	local container = Instance.new("Frame")
	container.Name = "Message_" .. tostring(timestamp)
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

	addMessageSurface(container, themeColors)

	-- Reply reference (reply arrow + name + preview)
	if replyRef and replyRef.sender then
		local replyRow = createReplyReference(replyRef, themeColors)
		replyRow.LayoutOrder = 0
		replyRow.Parent = container
	end

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextContent"
	textLabel.Font = FONT
	textLabel.TextSize = messageTextSize
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
	textLabel.Text = buildRichText(sender, content, timestamp, themeColors)

	if imageUrl and imageUrl ~= "" then
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "ImageAttachment"
		GifPlayer.apply(imageLabel, imageUrl)
		imageLabel.BackgroundColor3 = themeColors.scrollBack
		imageLabel.BorderColor3 = themeColors.imageBorder
		imageLabel.BorderSizePixel = 1
		imageLabel.ScaleType = Enum.ScaleType.Fit
		imageLabel.Size = UDim2.new(0, 200, 0, MAX_IMAGE_HEIGHT)
		imageLabel.LayoutOrder = 2
		imageLabel.Parent = container

		local imageCorner = Instance.new("UICorner")
		imageCorner.CornerRadius = UDim.new(0, 6)
		imageCorner.Parent = imageLabel

		imageLabel:GetPropertyChangedSignal("Image"):Connect(function()
			if imageLabel.Image == "" then
				imageLabel.Visible = false
			end
		end)
	end

	return container
end

--!
-- Creates a highlighted announcement card (Discord-style broadcast).
--!
local function createAnnouncementContainer(sender, timestamp, content, themeColors, replyRef)
	local card = Instance.new("Frame")
	card.Name = "Announcement_" .. tostring(timestamp)
	card.Size = UDim2.new(1, -4, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = timestamp
	card.BackgroundColor3 = themeColors.inputFrame
	card.BorderSizePixel = 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 9)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = themeColors.divider
	cardStroke.Transparency = 0.35
	cardStroke.Parent = card

	-- Colored accent bar along the left edge
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(0, 3, 1, 0)
	accentBar.Position = UDim2.new(0, 0, 0, 0)
	accentBar.BackgroundColor3 = themeColors.sendButton
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 2
	accentBar.Parent = card
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 9)
	accentCorner.Parent = accentBar

	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingTop = UDim.new(0, 10)
	cardPadding.PaddingBottom = UDim.new(0, 10)
	cardPadding.PaddingLeft = UDim.new(0, 14)
	cardPadding.PaddingRight = UDim.new(0, 12)
	cardPadding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = card

	local senderColor = UsernameColors.getNameColor(sender)
	local escapedSender = string.gsub(string.gsub(sender, "<", "<"), ">", ">")
	local escapedContent = string.gsub(string.gsub(content or "", "<", "<"), ">", ">")

	local layoutOrder = 1

	-- Reply reference (if present)
	if replyRef and replyRef.sender then
		local replyRow = createReplyReference(replyRef, themeColors)
		replyRow.LayoutOrder = layoutOrder
		replyRow.Parent = card
		layoutOrder = layoutOrder + 1
	end

	-- Header: megaphone + "Announcement" + sender + timestamp
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 17)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.TextSize = 12
	header.TextColor3 = themeColors.timestamp
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.RichText = true
	header.Text = buildAnnouncementHeader(sender, timestamp, themeColors)
	header.LayoutOrder = layoutOrder
	header.Parent = card

	layoutOrder = layoutOrder + 1

	-- Message body
	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.FontFace = FONTS.semibold
	body.TextSize = messageTextSize
	body.TextColor3 = themeColors.messageText
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Text = escapedContent
	body.LayoutOrder = layoutOrder
	body.Parent = card

	return card
end

--!
-- Creates a poll container (Frame) with question, options, and vote bars.
--!
local function createPollContainer(sender, timestamp, pollData, themeColors, replyRef)
	local card = Instance.new("Frame")
	card.Name = "Poll_" .. tostring(timestamp)
	card.Size = UDim2.new(1, -4, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = timestamp
	card.BackgroundColor3 = themeColors.inputFrame
	card.BorderSizePixel = 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 9)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = themeColors.divider
	cardStroke.Transparency = 0.35
	cardStroke.Parent = card
	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingTop = UDim.new(0, 10)
	cardPadding.PaddingBottom = UDim.new(0, 10)
	cardPadding.PaddingLeft = UDim.new(0, 10)
	cardPadding.PaddingRight = UDim.new(0, 10)
	cardPadding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 7)
	layout.Parent = card

	local senderColor = UsernameColors.getNameColor(sender)
	local escapedSender = string.gsub(string.gsub(sender, "<", "<"), ">", ">")
	local escapedQuestion = string.gsub(string.gsub(pollData.question or "", "<", "<"), ">", ">")

	local layoutOrder = 1

	-- Reply reference (if present)
	if replyRef and replyRef.sender then
		local replyRow = createReplyReference(replyRef, themeColors)
		replyRow.LayoutOrder = layoutOrder
		replyRow.Parent = card
		layoutOrder = layoutOrder + 1
	end

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 17)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.TextSize = 12
	header.TextColor3 = themeColors.timestamp
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.RichText = true
	header.Text = RichTextHelper.buildPollHeader(sender, timestamp, themeColors)
	header.LayoutOrder = layoutOrder
	header.Parent = card

	layoutOrder = layoutOrder + 1

	local question = Instance.new("TextLabel")
	question.Name = "Question"
	question.Size = UDim2.new(1, 0, 0, 0)
	question.AutomaticSize = Enum.AutomaticSize.Y
	question.BackgroundTransparency = 1
	question.FontFace = FONTS.heading
	question.TextSize = 15
	question.TextColor3 = themeColors.messageText
	question.TextXAlignment = Enum.TextXAlignment.Left
	question.TextYAlignment = Enum.TextYAlignment.Top
	question.TextWrapped = true
	question.Text = escapedQuestion
	question.LayoutOrder = layoutOrder
	question.Parent = card

	layoutOrder = layoutOrder + 1

	local summary = Instance.new("TextLabel")
	summary.Name = "VoteSummary"
	summary.Size = UDim2.new(1, 0, 0, 16)
	summary.BackgroundTransparency = 1
	summary.Font = FONT
	summary.TextSize = 12
	summary.TextColor3 = themeColors.timestamp
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Text = "0 votes  ·  Select an option"
	summary.LayoutOrder = layoutOrder
	summary.Parent = card

	layoutOrder = layoutOrder + 1

	for i, option in ipairs(pollData.options) do
		local row = Instance.new("TextButton")
		row.Name = "Option_" .. i
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = themeColors.pollBar
		row.Text = ""
		row.AutoButtonColor = true
		row.LayoutOrder = layoutOrder
		row.BorderSizePixel = 0
		row.ClipsDescendants = true
		row.Parent = card
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 7)
		rowCorner.Parent = row

		local bar = Instance.new("Frame")
		bar.Name = "VoteBar"
		bar.Size = UDim2.new(0, 0, 1, 0)
		bar.BackgroundColor3 = themeColors.pollBarVoted
		bar.BackgroundTransparency = 0.58
		bar.BorderSizePixel = 0
		bar.ZIndex = 1
		bar.Parent = row
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(0, 7)
		barCorner.Parent = bar

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -94, 1, 0)
		label.Position = UDim2.new(0, 11, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = option
		label.TextColor3 = themeColors.pollBarText
		label.Font = Enum.Font.BuilderSansMedium
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 2
		label.Parent = row

		local result = Instance.new("TextLabel")
		result.Name = "VoteCount"
		result.Size = UDim2.new(0, 78, 1, 0)
		result.Position = UDim2.new(1, -88, 0, 0)
		result.BackgroundTransparency = 1
		result.Text = "0%  ·  0"
		result.TextColor3 = themeColors.pollBarText
		result.FontFace = FONTS.mono
		result.TextSize = 12
		result.TextXAlignment = Enum.TextXAlignment.Right
		result.ZIndex = 2
		result.Parent = row

		layoutOrder = layoutOrder + 1
	end
	return card
end

local function updatePollVotes(container, pollData, themeColors)
	local totalVotes = 0
	for _, voters in ipairs(pollData.votes or {}) do
		totalVotes += #voters
	end
	local summary = container:FindFirstChild("VoteSummary")
	if summary then
		summary.Text = tostring(totalVotes) .. (totalVotes == 1 and " vote" or " votes") .. (totalVotes == 0 and "  ·  Select an option" or "  ·  Click an option to change your vote")
	end
	for i = 1, #pollData.options do
		local row = container:FindFirstChild("Option_" .. i)
		if row then
			local bar = row:FindFirstChild("VoteBar")
			local result = row:FindFirstChild("VoteCount")
			local count = pollData.votes and pollData.votes[i] and #pollData.votes[i] or 0
			local pct = totalVotes > 0 and count / totalVotes or 0
			if bar then bar.Size = UDim2.new(pct, 0, 1, 0) end
			if result then result.Text = string.format("%d%%  ·  %d", math.floor(pct * 100 + 0.5), count) end
		end
	end
end

-- File and audio cards fill the chat width between these bounds, so they
-- neither stretch across a wide widget nor squash in a narrow one.
local FILE_CARD_MIN_WIDTH = 100
local FILE_CARD_MAX_WIDTH = 250

local function addFileCardBounds(card)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(FILE_CARD_MIN_WIDTH, 0)
	constraint.MaxSize = Vector2.new(FILE_CARD_MAX_WIDTH, math.huge)
	constraint.Parent = card
end

local function createFileContainer(sender, timestamp, content, fileName, fileUrl, fileType, themeColors, replyRef)
	local container = Instance.new("Frame")
	container.Name = "File_" .. tostring(timestamp)
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Position = UDim2.new(0, 0, 0,0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.LayoutOrder = timestamp
	container.BorderSizePixel = 0

	local containerLayout = Instance.new("UIListLayout")
	containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	containerLayout.Padding = UDim.new(0, -4)
	containerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	containerLayout.Parent = container

	addMessageSurface(container, themeColors)

	-- Reply reference (reply arrow + name + preview)
	if replyRef and replyRef.sender then
		local replyRow = createReplyReference(replyRef, themeColors)
		replyRow.LayoutOrder = 0
		replyRow.Parent = container
	end

	-- File-type icons come from Icons.forFileType(fileType) (see fileIconLabel below).

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
	textLabel.Text = buildRichText(sender, content or "", timestamp, themeColors)

	if fileType == "Audio" and fileUrl and fileUrl ~= "" then
		local audioCard = Instance.new("Frame")
		audioCard.Name = "AudioPlayerCard"
		audioCard.Size = UDim2.new(1, 0, 0, 68)
		audioCard.BackgroundColor3 = themeColors.menuBack
		audioCard.BorderSizePixel = 0
		audioCard.LayoutOrder = 2
		audioCard.Parent = container
		addFileCardBounds(audioCard)

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
		timeLabel.FontFace = FONTS.mono
		timeLabel.TextSize = 11
		timeLabel.TextXAlignment = Enum.TextXAlignment.Left
		timeLabel.BorderSizePixel = 0
		timeLabel.ZIndex = 3
		timeLabel.Parent = audioCard

		AudioPlayback.wire(audioCard, fileUrl, themeColors)
	else
		AttachmentCards.createFile(container, fileName, fileUrl, fileType, themeColors, addFileCardBounds)
	end

	return container
end


--!
-- Re-renders an existing message container with new theme colors.
--!
local function recolorMessageContainer(container, themeColors)
	local sender = container:GetAttribute("Sender")
	local content = container:GetAttribute("Content")
	local timestamp = container:GetAttribute("Timestamp")
	if not sender or not timestamp then return end
	if content == nil then content = "" end

	if container:GetAttribute("HoverHighlight") then
		container.BackgroundColor3 = themeColors.menuItemHover
	end

	if container:GetAttribute("IsPoll") then
		container.BackgroundColor3 = themeColors.inputFrame
		local headerLabel = container:FindFirstChild("Header")
		if headerLabel and sender and timestamp then
			headerLabel.Text = RichTextHelper.buildPollHeader(sender, timestamp, themeColors)
		end
		local questionLabel = container:FindFirstChild("Question")
		if questionLabel then questionLabel.TextColor3 = themeColors.messageText end
		local summaryLabel = container:FindFirstChild("VoteSummary")
		if summaryLabel then summaryLabel.TextColor3 = themeColors.timestamp end
	end

	if container:GetAttribute("IsAnnouncement") then
		container.BackgroundColor3 = themeColors.inputFrame
		local accentBar = container:FindFirstChild("AccentBar")
		if accentBar then accentBar.BackgroundColor3 = themeColors.sendButton end
		local headerLabel = container:FindFirstChild("Header")
		if headerLabel and sender and timestamp then
			headerLabel.Text = buildAnnouncementHeader(sender, timestamp, themeColors)
		end
		local bodyLabel = container:FindFirstChild("Body")
		if bodyLabel then bodyLabel.TextColor3 = themeColors.messageText end
	end

	local textLabel = container:FindFirstChild("TextContent")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.TextColor3 = themeColors.messageText
		textLabel.Text = buildRichText(sender, content, timestamp, themeColors)
	end

	local imageLabel = container:FindFirstChild("ImageAttachment")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.BackgroundColor3 = themeColors.scrollBack
		imageLabel.BorderColor3 = themeColors.imageBorder
	end

	EmbedManager.recolor(container, themeColors)

	AttachmentCards.recolor(container, themeColors)

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
		local progressFill = videoFrame:FindFirstChild("ControlsBar")
		if progressFill then
			local fill = progressFill:FindFirstChild("ProgressBg")
			if fill then
				local fillBar = fill:FindFirstChild("ProgressFill")
				if fillBar then
					fillBar.BackgroundColor3 = themeColors.sendButton
				end
			end
		end
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextButton") and string.match(child.Name, "^Option_%d+$") then
			child.BackgroundColor3 = themeColors.pollBar
			local voteBar = child:FindFirstChild("VoteBar")
			if voteBar then
				voteBar.BackgroundColor3 = themeColors.pollBarVoted
			end
			local label = child:FindFirstChild("Label")
			if label then
				label.TextColor3 = themeColors.pollBarText
			end
			local voteCount = child:FindFirstChild("VoteCount")
			if voteCount then
				voteCount.TextColor3 = themeColors.pollBarText
			end
		end
	end
end

--!
-- Creates the dock widget and returns the UI elements.
-- @param pluginInstance The plugin global
--!
function ChatUI.create(pluginInstance)
	local widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Left,
		true,
		false,
		300,
		500,
		250,
		300
	)

	local widget = pluginInstance:CreateDockWidgetPluginGui("TeamChatWidget", widgetInfo)
	widget.Title = "Team Chat"

	-- Clean up any old children from previous plugin load
	for _, child in ipairs(widget:GetChildren()) do
		child:Destroy()
	end

	local currentThemeName = detectTheme()
	local themeColors = THEMES[currentThemeName]
	local composerHeight = INPUT_HEIGHT

	-- Main container fills the entire widget
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.Position = UDim2.new(0, 0, 0, 0)
	container.BackgroundColor3 = themeColors.scrollBack
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Parent = widget

	-- Conversations sidebar (pinned team chat + DMs) on the left; the chat
	-- fills the rest. It expands to show names when the panel is wide, or
	-- when its toggle is clicked. Fields are filled in further down; kept in
	-- one table so create stays under Luau's 200-local limit.
	local conversationSidebar = { title = "Team Chat" }
	do
		local sidebar
		local manualExpanded: boolean? = nil
		local function applyWidth()
			local width = sidebar.width()
			container.Position = UDim2.fromOffset(width, 0)
			container.Size = UDim2.new(1, -width, 1, 0)
		end
		local function setExpanded(expanded: boolean)
			sidebar.setExpanded(expanded)
			applyWidth()
		end
		sidebar = ConversationList.create(themeColors, widget, function(id)
			if conversationSidebar.selectCallback then
				conversationSidebar.selectCallback(id)
			end
		end, function(expanded)
			manualExpanded = expanded
			setExpanded(expanded)
		end, function()
			if conversationSidebar.newMessageDialog then
				conversationSidebar.newMessageDialog.open()
			end
		end, function(id)
			if conversationSidebar.closeCallback then
				conversationSidebar.closeCallback(id)
			end
		end)
		local function autoExpand()
			if manualExpanded ~= nil then return end
			local wide = widget.AbsoluteSize.X >= 600
			if wide ~= sidebar.expanded then
				setExpanded(wide)
			end
		end
		widget:GetPropertyChangedSignal("AbsoluteSize"):Connect(autoExpand)
		applyWidth()
		task.defer(autoExpand)
		conversationSidebar.list = sidebar
	end

	-- Autocomplete dropdown (command suggestions)
	local autocompleteFrame = Autocomplete.create(themeColors, container)
	local autocompleteItems = {}
	local autocompleteSelectedIndex = 1

	--!
	-- Hides the autocomplete dropdown.
	--!
	local function hideAutocomplete()
		autocompleteFrame.Visible = false
		autocompleteItems = {}
		autocompleteSelectedIndex = 1
	end

	--!
	-- Updates the visual selection highlight in the autocomplete dropdown.
	--!
	local function updateAutocompleteSelection()
		Autocomplete.setSelected(autocompleteFrame, autocompleteSelectedIndex)
	end

	-- Header bar: the open conversation's title

	local header = Instance.new("Frame")
	header.Name = "TopBar"
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.BackgroundColor3 = themeColors.inputFrame
	header.BorderSizePixel = 0
	header.ZIndex = 5
	header.Parent = container

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Position = UDim2.fromOffset(12, 0)
	headerTitle.Size = UDim2.new(1, -24, 1, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.FontFace = FONTS.heading
	headerTitle.TextSize = 16
	headerTitle.TextColor3 = themeColors.messageText
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.TextTruncate = Enum.TextTruncate.AtEnd
	headerTitle.RichText = true
	headerTitle.ZIndex = 5
	headerTitle.Parent = header

	--!
	-- The open conversation ("Team Chat" or "@Name") followed by the version
	-- (and Development Mode tag) in
	-- small, muted mono text. Re-run by applyTheme so the color follows it.
	--!
	local function renderHeaderTitle()
		local tag = if PLUGIN_VERSION then PLUGIN_VERSION else ""
		if DEVELOPMENT_MODE then
			tag ..= (if tag ~= "" then " \u{00B7} " else "") .. "Development Mode"
		end
		local title = Icons.escape(conversationSidebar.title)
		if tag == "" then
			headerTitle.Text = title
			return
		end
		headerTitle.Text = string.format(
			'%s  <font size="10" color="%s">%s%s</font></font>',
			title,
			toHex(themeColors.timestamp),
			Theme.richFont("mono"),
			Icons.escape(tag)
		)
	end
	renderHeaderTitle()

	local headerDivider = Instance.new("Frame")
	headerDivider.Name = "Divider"
	headerDivider.AnchorPoint = Vector2.new(0, 1)
	headerDivider.Position = UDim2.new(0, 0, 1, 0)
	headerDivider.Size = UDim2.new(1, 0, 0, 1)
	headerDivider.BackgroundColor3 = themeColors.divider
	headerDivider.BorderSizePixel = 0
	headerDivider.ZIndex = 5
	headerDivider.Parent = header

	-- What's New and Settings sit at the bottom of the sidebar, above its
	-- expand/collapse toggle; each has a tooltip (wired further down)
	local sidebarWhatsNewButton = conversationSidebar.list.addFooterButton("WhatsNewButton", "whatsNew", "What's New")
	local sidebarSettingsButton = conversationSidebar.list.addFooterButton("SettingsButton", "settings", "Settings")

	-- Scrolling frame for messages (below the header)
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "MessageList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -(INPUT_HEIGHT + HEADER_HEIGHT))
	scrollFrame.Position = UDim2.new(0, 0, 0, HEADER_HEIGHT)
	scrollFrame.BackgroundColor3 = themeColors.scrollBack
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = themeColors.scrollBar
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	scrollFrame.Parent = container

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.Parent = scrollFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 5)
	padding.Parent = scrollFrame

	-- Round "scroll to bottom" button (Discord-style): shown when the user
	-- has scrolled away from the bottom of the message list so new messages
	-- can be missed; clicking it jumps the list back to the bottom.
	local scrollButton = Instance.new("TextButton")
	scrollButton.Name = "ScrollToBottomButton"
	scrollButton.Size = UDim2.new(0, 33, 0, 33)
	scrollButton.AnchorPoint = Vector2.new(1, 1)
	scrollButton.Position = UDim2.new(1, -14, 1, -(INPUT_HEIGHT + 14))
	scrollButton.BackgroundColor3 = themeColors.menuBack
	Icons.apply(scrollButton, "scrollDown")
	scrollButton.TextColor3 = themeColors.menuItemText
	scrollButton.TextSize = 20
	scrollButton.AutoButtonColor = true
	scrollButton.BorderSizePixel = 0
	scrollButton.Visible = false
	scrollButton.ZIndex = 12
	scrollButton.Parent = container

	local scrollButtonCorner = Instance.new("UICorner")
	scrollButtonCorner.CornerRadius = UDim.new(1, 0)
	scrollButtonCorner.Parent = scrollButton

	local scrollButtonStroke = Instance.new("UIStroke")
	scrollButtonStroke.Color = themeColors.menuBorder
	scrollButtonStroke.Thickness = 1
	scrollButtonStroke.Parent = scrollButton

	-- Soft drop shadow so the button stands out over the message list
	local scrollButtonShadow = Instance.new("UIShadow")
	scrollButtonShadow.BlurRadius = UDim.new(0, 8)
	scrollButtonShadow.Color = Color3.fromRGB(0, 0, 0)
	scrollButtonShadow.Transparency = 0.55
	scrollButtonShadow.Parent = scrollButton

	-- Context menu for message interactions (reply, delete, copy)
	local contextMenu = Instance.new("Frame")
	contextMenu.Name = "ContextMenu"
	contextMenu.Size = UDim2.new(0, 160, 0, 0)
	contextMenu.AutomaticSize = Enum.AutomaticSize.Y
	contextMenu.BackgroundColor3 = themeColors.menuBack
	contextMenu.BorderColor3 = themeColors.menuBorder
	contextMenu.BorderSizePixel = 1
	contextMenu.Visible = false
	contextMenu.ZIndex = 20
	contextMenu.Parent = container

	local contextMenuCorner = Instance.new("UICorner")
	contextMenuCorner.CornerRadius = UDim.new(0, 6)
	contextMenuCorner.Parent = contextMenu

	local contextMenuLayout = Instance.new("UIListLayout")
	contextMenuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contextMenuLayout.Padding = UDim.new(0, 4)
	contextMenuLayout.Parent = contextMenu

	local contextMenuPadding = Instance.new("UIPadding")
	contextMenuPadding.PaddingTop = UDim.new(0, 6)
	contextMenuPadding.PaddingBottom = UDim.new(0, 6)
	contextMenuPadding.PaddingLeft = UDim.new(0, 8)
	contextMenuPadding.PaddingRight = UDim.new(0, 8)
	contextMenuPadding.Parent = contextMenu

	local contextMenuStroke = Instance.new("UIStroke")
	contextMenuStroke.Color = themeColors.menuBorder
	contextMenuStroke.Thickness = 1
	contextMenuStroke.Parent = contextMenu

	local contextMenuShadow = Instance.new("UIShadow")
	contextMenuShadow.BlurRadius = UDim.new(0, 12)
	contextMenuShadow.Color = Color3.fromRGB(0, 0, 0)
	contextMenuShadow.Transparency = 0.5
	contextMenuShadow.Parent = contextMenu

-- Context menu entries ({ item, icon, label, danger }) and divider, kept so
-- recolorContextMenu can follow theme changes.
local contextMenuItems = {}
local contextMenuDivider: Frame

local function contextMenuTextColor(danger: boolean): Color3
	return if danger then themeColors.danger else (themeColors.menuItemText or themeColors.messageText)
end

--!
-- Re-applies theme colors to the context menu and its items.
--!
local function recolorContextMenu()
	contextMenu.BackgroundColor3 = themeColors.menuBack
	contextMenuStroke.Color = themeColors.menuBorder
	contextMenuDivider.BackgroundColor3 = themeColors.menuBorder
	for _, entry in ipairs(contextMenuItems) do
		local color = contextMenuTextColor(entry.danger)
		entry.icon.TextColor3 = color
		entry.label.TextColor3 = color
	end
end

--!
-- Creates a menu entry: Builder Icons glyph + label. Destructive entries
-- (danger = true) are drawn in the theme's danger color and get a red tint
-- on hover. Used by the message context menu and (with parent) the plus menu.
--!
local function createContextMenuItem(text: string, iconKey: string, layoutOrder: number, danger: boolean?, parent: GuiObject?): TextButton
	local isDanger = danger == true

	local item = Instance.new("TextButton")
	item.Name = text .. "Item"
	item.Size = UDim2.new(1, 0, 0, 30)
	item.BackgroundTransparency = 1
	item.Text = ""
	item.AutoButtonColor = false
	item.LayoutOrder = layoutOrder
	item.ZIndex = 21
	item.Parent = parent or contextMenu

	local itemCorner = Instance.new("UICorner")
	itemCorner.CornerRadius = UDim.new(0, 4)
	itemCorner.Parent = item

	local itemPadding = Instance.new("UIPadding")
	itemPadding.PaddingLeft = UDim.new(0, 8)
	itemPadding.PaddingRight = UDim.new(0, 8)
	itemPadding.Parent = item

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 16, 1, 0)
	icon.BackgroundTransparency = 1
	Icons.apply(icon, iconKey)
	icon.TextSize = 16
	icon.ZIndex = 22
	icon.Parent = item

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.fromOffset(26, 0)
	label.Size = UDim2.new(1, -26, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.FontFace = FONTS.medium
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 22
	label.Parent = item

	local color = contextMenuTextColor(isDanger)
	icon.TextColor3 = color
	label.TextColor3 = color

	item.MouseEnter:Connect(function()
		if isDanger then
			item.BackgroundColor3 = themeColors.danger
			item.BackgroundTransparency = DANGER_HOVER_TRANSPARENCY
		else
			item.BackgroundColor3 = themeColors.menuItemHover
			item.BackgroundTransparency = 0
		end
	end)
	item.MouseLeave:Connect(function()
		item.BackgroundTransparency = 1
	end)

	table.insert(contextMenuItems, { item = item, icon = icon, label = label, danger = isDanger })
	return item
end

local replyMenuItem = createContextMenuItem("Reply", "reply", 1)
local copyMenuItem = createContextMenuItem("Copy", "copy", 2)

-- Thin separator so the destructive action sits apart at the bottom
contextMenuDivider = Instance.new("Frame")
contextMenuDivider.Name = "Divider"
contextMenuDivider.Size = UDim2.new(1, 0, 0, 1)
contextMenuDivider.BackgroundColor3 = themeColors.menuBorder
contextMenuDivider.BorderSizePixel = 0
contextMenuDivider.LayoutOrder = 3
contextMenuDivider.ZIndex = 21
contextMenuDivider.Parent = contextMenu

local deleteMenuItem = createContextMenuItem("Delete", "delete", 4, true)

local contextMenuTargetTimestamp: number? = nil
local contextMenuTargetContainer: Instance? = nil
local contextMenuTargetSender: string? = nil
local contextMenuTargetContent: string? = nil
local contextMenuTargetType: string? = nil
local contextMenuTargetOptions: {string}? = nil
local contextMenuTargetVotes: {{string}}? = nil
local contextMenuTargetPollData: any? = nil
local contextMenuTargetFileData: {fileName: string, fileUrl: string, fileType: string}? = nil

-- Callbacks for message interactions (reply, delete, copy).
-- Declared before the context menu handlers below so the handlers
-- capture these locals instead of falling back to nil globals.
local onReplyCallback: ((number) -> ())? = nil
local onDeleteCallback: ((number) -> ())? = nil
local onCopyCallback: ((number) -> ())? = nil

-- Last cursor position the menu was opened at (widget coordinates), so the
-- menu can be re-placed once its automatic height is known.
local contextMenuCursor = Vector2.zero

--!
-- Places the context menu next to the cursor (widget coordinates), flipping
-- it left/up when it would overflow the panel and clamping it inside.
--!
local function placeContextMenu()
	local bounds = container.AbsoluteSize
	local menuSize = contextMenu.AbsoluteSize
	local cursor = contextMenuCursor - (container.AbsolutePosition - widget.AbsolutePosition)

	local x = cursor.X + CONTEXT_MENU_CURSOR_OFFSET
	local y = cursor.Y + CONTEXT_MENU_CURSOR_OFFSET
	if x + menuSize.X > bounds.X - CONTEXT_MENU_EDGE_MARGIN then
		x = cursor.X - CONTEXT_MENU_CURSOR_OFFSET - menuSize.X
	end
	if y + menuSize.Y > bounds.Y - CONTEXT_MENU_EDGE_MARGIN then
		y = cursor.Y - CONTEXT_MENU_CURSOR_OFFSET - menuSize.Y
	end
	x = math.clamp(x, CONTEXT_MENU_EDGE_MARGIN, math.max(CONTEXT_MENU_EDGE_MARGIN, bounds.X - menuSize.X - CONTEXT_MENU_EDGE_MARGIN))
	y = math.clamp(y, CONTEXT_MENU_EDGE_MARGIN, math.max(CONTEXT_MENU_EDGE_MARGIN, bounds.Y - menuSize.Y - CONTEXT_MENU_EDGE_MARGIN))

	contextMenu.Position = UDim2.fromOffset(x, y)
end

-- The menu uses AutomaticSize, so its height can settle after it is shown
-- (or change when items are toggled); keep it next to the cursor.
contextMenu:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if contextMenu.Visible then
		placeContextMenu()
	end
end)

--!
-- Opens the context menu at the current mouse position inside the widget.
--!
local function showContextMenu(msgContainer, sender, timestamp, content, messageType, options, votes, pollData, fileData)
	contextMenuTargetTimestamp = timestamp
	contextMenuTargetContainer = msgContainer
	contextMenuTargetSender = sender
	contextMenuTargetContent = content
	contextMenuTargetType = messageType
	contextMenuTargetOptions = options
	contextMenuTargetVotes = votes
	contextMenuTargetPollData = pollData
	contextMenuTargetFileData = fileData
	contextMenuCursor = widget:GetRelativeMousePosition()
	contextMenu.Visible = true
	placeContextMenu()
end

local function hideContextMenu()
	contextMenu.Visible = false
	contextMenuTargetTimestamp = nil
	contextMenuTargetContainer = nil
	contextMenuTargetSender = nil
	contextMenuTargetContent = nil
	contextMenuTargetType = nil
	contextMenuTargetOptions = nil
	contextMenuTargetVotes = nil
	contextMenuTargetPollData = nil
	contextMenuTargetFileData = nil
end

-- Hide context menu when clicking elsewhere (clicks inside the menu are
-- handled by its items; its padding and divider do nothing)
local function isInside(gui: GuiObject, point: Vector2 | Vector3): boolean
	local topLeft, size = gui.AbsolutePosition, gui.AbsoluteSize
	return point.X >= topLeft.X and point.X <= topLeft.X + size.X
		and point.Y >= topLeft.Y and point.Y <= topLeft.Y + size.Y
end

--!
-- Current mouse position in the same space as GuiObject.AbsolutePosition.
-- Full-panel click catchers sit behind modals/menus and still receive clicks
-- made on top of them (frames don't block GUI buttons), so they use this to
-- only close when the click really was outside.
--!
local function mousePosition(): Vector2
	return widget:GetRelativeMousePosition() + widget.AbsolutePosition
end

container.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if contextMenu.Visible and isInside(contextMenu, input.Position) then
			return
		end
		hideContextMenu()
	end
end)

-- Context menu item handlers
replyMenuItem.MouseButton1Click:Connect(function()
	if contextMenuTargetTimestamp and onReplyCallback then
		onReplyCallback(contextMenuTargetTimestamp)
	end
	hideContextMenu()
end)

deleteMenuItem.MouseButton1Click:Connect(function()
	if contextMenuTargetTimestamp and onDeleteCallback then
		onDeleteCallback(contextMenuTargetTimestamp)
	end
	hideContextMenu()
end)

copyMenuItem.MouseButton1Click:Connect(function()
	if contextMenuTargetTimestamp and onCopyCallback then
		onCopyCallback(contextMenuTargetTimestamp)
	end
	hideContextMenu()
end)


	-- Auto-scroll to the bottom while the user is already there; when they
	-- have scrolled up, keep their reading position and show the button.
	-- NOTE: the list uses AutomaticCanvasSize, so the CanvasSize property
	-- stays at 0 — AbsoluteCanvasSize is the one that reflects the real
	-- scrollable content height.
	local isScrollAtBottom = true
	local function getMaxScroll()
		return math.max(0, scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteSize.Y)
	end
	local function scrollToBottom()
		scrollFrame.CanvasPosition = Vector2.new(0, getMaxScroll())
	end

	-- Jump-to-reply: scroll the original message into the middle of the list,
	-- then flash it in the accent color and fade out (like Discord).
	local activeFlashes = {} -- [message] = Tween, so a re-click restarts the flash

	local function flashMessage(target)
		if activeFlashes[target] then
			activeFlashes[target]:Cancel()
		end
		local fadeInfo = TweenInfo.new(FLASH_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, FLASH_HOLD_TIME)
		local tween
		if target:GetAttribute("HoverHighlight") then
			-- Plain messages: tint the hover surface, then fade it out
			target.BackgroundColor3 = themeColors.sendButton
			target.BackgroundTransparency = FLASH_START_TRANSPARENCY
			tween = TweenService:Create(target, fadeInfo, { BackgroundTransparency = 1 })
			tween.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					target.BackgroundColor3 = themeColors.menuItemHover
				end
			end)
		else
			-- Poll / announcement cards: light up the card's outline instead
			local stroke = target:FindFirstChildOfClass("UIStroke")
			if not stroke then return end
			stroke.Color = themeColors.sendButton
			stroke.Transparency = 0
			tween = TweenService:Create(stroke, fadeInfo, { Color = themeColors.divider, Transparency = 0.35 })
		end
		activeFlashes[target] = tween
		tween.Completed:Connect(function()
			if activeFlashes[target] == tween then
				activeFlashes[target] = nil
			end
		end)
		tween:Play()
	end

	jumpToMessage = function(timestamp)
		local target
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("GuiObject") and child:GetAttribute("Timestamp") == timestamp then
				target = child
				break
			end
		end
		if not target then return end -- original was deleted or isn't loaded

		local top = target.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y + scrollFrame.CanvasPosition.Y
		local y = math.clamp(top - (scrollFrame.AbsoluteSize.Y - target.AbsoluteSize.Y) / 2, 0, getMaxScroll())
		TweenService:Create(
			scrollFrame,
			TweenInfo.new(JUMP_SCROLL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CanvasPosition = Vector2.new(0, y) }
		):Play()
		flashMessage(target)
	end

	local function updateScrollState()
		isScrollAtBottom = scrollFrame.CanvasPosition.Y >= getMaxScroll() - SCROLL_BOTTOM_THRESHOLD
		scrollButton.Visible = not isScrollAtBottom
	end

	-- User scrolling only updates the at-bottom state and button visibility;
	-- it never forces the position, so scrolling up is never fought.
	scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(updateScrollState)

	-- When the content grows (new message, image load, reflow), follow the
	-- bottom only if the user was already there.
	local function updateScrollStateAndFollow()
		local wasAtBottom = isScrollAtBottom
		updateScrollState()
		if wasAtBottom then
			scrollToBottom()
		end
	end

	scrollFrame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(updateScrollStateAndFollow)
	scrollFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScrollStateAndFollow)

	scrollButton.MouseButton1Click:Connect(function()
		scrollToBottom()
		scrollButton.Visible = false
	end)

	-- Auto-fading scrollbar: invisible while idle, fades in whenever the
	-- user scrolls or the content changes, then fades back out after a
	-- short delay (Discord-style behavior).
	local SCROLLBAR_FADE_DELAY = 1.75
	local scrollFadeToken = 0
	local scrollFadeTween = nil
	local function hideScrollBar()
		if scrollFadeTween then
			scrollFadeTween:Cancel()
		end
		scrollFadeTween = TweenService:Create(scrollFrame,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ ScrollBarImageTransparency = 1 })
		scrollFadeTween:Play()
	end
	local function pulseScrollBar()
		scrollFadeToken += 1
		local token = scrollFadeToken
		if scrollFadeTween then
			scrollFadeTween:Cancel()
		end
		scrollFrame.ScrollBarImageTransparency = 0
		task.delay(SCROLLBAR_FADE_DELAY, function()
			if scrollFadeToken == token then
				hideScrollBar()
			end
		end)
	end
	scrollFrame.ScrollBarImageTransparency = 1
	scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(pulseScrollBar)
	scrollFrame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(pulseScrollBar)

	-- Empty state placeholder (shown when no messages exist)
	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.Size = UDim2.new(1, 0, 1, -(INPUT_HEIGHT + HEADER_HEIGHT))
	emptyState.Position = UDim2.new(0, 0, 0, HEADER_HEIGHT)
	emptyState.BackgroundTransparency = 1
	emptyState.BorderSizePixel = 0
	emptyState.Parent = container

	local emptyLayout = Instance.new("UIListLayout")
	emptyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	emptyLayout.FillDirection = Enum.FillDirection.Vertical
	emptyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	emptyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	emptyLayout.Padding = UDim.new(0, 10)
	emptyLayout.Parent = emptyState

	local emptyIcon = Instance.new("TextLabel")
	emptyIcon.Name = "Icon"
	emptyIcon.Size = UDim2.new(0, 48, 0, 48)
	emptyIcon.BackgroundTransparency = 1
	Icons.apply(emptyIcon, "emptyChat")
	emptyIcon.TextColor3 = themeColors.emptyTitle
	emptyIcon.TextSize = 36
	emptyIcon.LayoutOrder = 1
	emptyIcon.BorderSizePixel = 0
	emptyIcon.Parent = emptyState

	local emptyTitleLabel = Instance.new("TextLabel")
	emptyTitleLabel.Name = "Title"
	emptyTitleLabel.Size = UDim2.new(1, -20, 0, 24)
	emptyTitleLabel.BackgroundTransparency = 1
	emptyTitleLabel.Text = "No messages yet"
	emptyTitleLabel.TextColor3 = themeColors.emptyTitle
	emptyTitleLabel.FontFace = FONTS.display
	emptyTitleLabel.TextSize = 17
	emptyTitleLabel.LayoutOrder = 2
	emptyTitleLabel.BorderSizePixel = 0
	emptyTitleLabel.Parent = emptyState

	local emptySubtitle = Instance.new("TextLabel")
	emptySubtitle.Name = "Subtitle"
	emptySubtitle.Size = UDim2.new(1, -30, 0, 20)
	emptySubtitle.BackgroundTransparency = 1
	emptySubtitle.Text = "Send a message to start the conversation!"
	emptySubtitle.TextColor3 = themeColors.emptySubtitle
	emptySubtitle.Font = FONT
	emptySubtitle.TextSize = 13
	emptySubtitle.TextWrapped = true
	emptySubtitle.LayoutOrder = 3
	emptySubtitle.BorderSizePixel = 0
	emptySubtitle.Parent = emptyState

	local function hideEmptyState()
		emptyState.Visible = false
	end

	-- Shows the empty state again when no message containers are left
	-- (e.g. after the last message was deleted).
	local function showEmptyStateIfNoMessages()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") and child.Name:match("^Message_") then
				emptyState.Visible = false
				return
			end
		end
		emptyState.Visible = true
	end

	-- Divider line above input
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Position = UDim2.new(0, 0, 1, -INPUT_HEIGHT)
	divider.BackgroundColor3 = themeColors.divider
	divider.BorderSizePixel = 0
	divider.Parent = container

	-- Input frame at the bottom
	local inputFrame = Instance.new("Frame")
	inputFrame.Name = "InputFrame"
	inputFrame.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
	inputFrame.Position = UDim2.new(0, 0, 1, -INPUT_HEIGHT)
	inputFrame.BackgroundColor3 = themeColors.inputFrame
	inputFrame.BorderSizePixel = 0
	inputFrame.Parent = container

	-- Plus button (Discord-style expandable menu trigger)
	local attachButton = Instance.new("TextButton")
	attachButton.Name = "AttachButton"
	attachButton.Size = UDim2.new(0, 33, 0, 33)
	attachButton.Position = UDim2.new(0, 8, 0, 8)
	attachButton.BackgroundColor3 = themeColors.attachButton
	Icons.apply(attachButton, "add")
	attachButton.TextColor3 = themeColors.attachIcon
	attachButton.TextSize = 18
	attachButton.AutoButtonColor = true
	attachButton.BorderSizePixel = 0
	attachButton.Parent = inputFrame

	local attachCorner = Instance.new("UICorner")
	attachCorner.CornerRadius = UDim.new(1, 0)
	attachCorner.Parent = attachButton

	-- Plus menu: pops up above the plus button, styled like the message
	-- context menu (same frame look and createContextMenuItem entries)
	local menuFrame = Instance.new("Frame")
	menuFrame.Name = "Menu"
	menuFrame.Size = UDim2.new(0, MENU_WIDTH, 0, 0)
	menuFrame.AutomaticSize = Enum.AutomaticSize.Y
	menuFrame.AnchorPoint = Vector2.new(0, 1)
	menuFrame.Position = UDim2.new(0, 4, 1, -(INPUT_HEIGHT + 8))
	menuFrame.BackgroundColor3 = themeColors.menuBack
	menuFrame.BorderSizePixel = 0
	menuFrame.Visible = false
	menuFrame.ZIndex = 20
	menuFrame.Parent = container

	local menuClickCatcher = Instance.new("TextButton")
	menuClickCatcher.Name = "MenuClickCatcher"
	menuClickCatcher.Size = UDim2.new(1, 0, 1, 0)
	menuClickCatcher.Position = UDim2.new(0, 0, 0, 0)
	menuClickCatcher.BackgroundTransparency = 1
	menuClickCatcher.Text = ""
	menuClickCatcher.AutoButtonColor = false
	menuClickCatcher.Visible = false
	menuClickCatcher.ZIndex = 9
	menuClickCatcher.Parent = container

	local menuCorner = Instance.new("UICorner")
	menuCorner.CornerRadius = UDim.new(0, 6)
	menuCorner.Parent = menuFrame

	local menuStroke = Instance.new("UIStroke")
	menuStroke.Color = themeColors.menuBorder
	menuStroke.Thickness = 1
	menuStroke.Parent = menuFrame

	local menuShadow = Instance.new("UIShadow")
	menuShadow.BlurRadius = UDim.new(0, 12)
	menuShadow.Color = Color3.fromRGB(0, 0, 0)
	menuShadow.Transparency = 0.5
	menuShadow.Parent = menuFrame

	local menuLayout = Instance.new("UIListLayout")
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Padding = UDim.new(0, 4)
	menuLayout.Parent = menuFrame

	local menuPad = Instance.new("UIPadding")
	menuPad.PaddingTop = UDim.new(0, 6)
	menuPad.PaddingBottom = UDim.new(0, 6)
	menuPad.PaddingLeft = UDim.new(0, 8)
	menuPad.PaddingRight = UDim.new(0, 8)
	menuPad.Parent = menuFrame

	local menuItemPoll = createContextMenuItem("Create Poll", "createPoll", 1, false, menuFrame)
	menuItemPoll.Name = "MenuItemPoll"

	local menuItemFile = createContextMenuItem("Attach File(s)", "attachFile", 2, false, menuFrame)
	menuItemFile.Name = "MenuItemFile"

	-- Text box for typing messages
	local textBox = Instance.new("TextBox")
	textBox.Name = "InputBox"
	textBox.Size = UDim2.new(1, -98, 0, 33)
	textBox.Position = UDim2.new(0, 49, 0, 8)
	textBox.BackgroundColor3 = themeColors.inputBox
	textBox.TextColor3 = themeColors.textBoxText
	textBox.PlaceholderText = "Type a message..."
	textBox.PlaceholderColor3 = themeColors.placeholder
	textBox.Font = FONT
	textBox.TextSize = 14
	textBox.TextScaled = false
	textBox.TextWrapped = true -- Wrap long messages onto multiple lines
	-- MultiLine so text wraps while typing, like an HTML textarea (a single-line
	-- TextBox scrolls sideways past its edge until it loses focus). Enter then
	-- types a newline; MessageController turns a typed Enter into "send".
	textBox.MultiLine = true
	textBox.TextYAlignment = Enum.TextYAlignment.Center
	textBox.Text = ""
	textBox.ClearTextOnFocus = false
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.BorderSizePixel = 0
	textBox.ClipsDescendants = false -- Let the box grow with wrapped text
	textBox.Parent = inputFrame

	local textBoxCorner = Instance.new("UICorner")
	textBoxCorner.CornerRadius = UDim.new(1, 0) -- Pill shape when single-line; made adaptive in updateComposerLayout
	textBoxCorner.Parent = textBox

	local textBoxPadding = Instance.new("UIPadding")
	textBoxPadding.PaddingLeft = UDim.new(0, 7)
	textBoxPadding.PaddingRight = UDim.new(0, 5)
	textBoxPadding.PaddingTop = UDim.new(0, 5)
	textBoxPadding.PaddingBottom = UDim.new(0, 5)
	textBoxPadding.Parent = textBox

	--!
	-- Autocomplete suggestions: watches the input box and populates the
	-- dropdown with matching commands (while typing "/name") or emojis
	-- (while typing a trailing ":shortcode").
	-- Studio sends plugin widgets no keyboard events, so suggestions are picked
	-- by clicking (hover highlights) or with Tab, which is detected from the
	-- tab character it types into the box.
	-- commandProviderFn is forward-declared here because it is assigned via
	-- setCommandProvider further below.
	--!
	local commandProviderFn
	local autocompleteMode = nil -- "command" | "emoji"
	local emojiMatchStart = nil -- 1-based index of the ":" currently being typed

	local function clearAutocompleteItems()
		for _, child in ipairs(autocompleteFrame:GetChildren()) do
			if child:IsA("TextButton") and child.Name:match("^Item_%d+$") then
				child:Destroy()
			end
		end
	end

	--!
	-- Applies a selected suggestion to the input box.
	--!
	local function applyAutocompleteItem(item)
		if not item then
			return
		end

		if item.type == "command" then
			textBox.Text = "/" .. item.name .. " "
		elseif item.type == "emoji" and emojiMatchStart then
			textBox.Text = string.sub(textBox.Text, 1, emojiMatchStart - 1) .. item.emoji .. " "
		end
		textBox.CursorPosition = #textBox.Text + 1 -- keep typing after the suggestion

		hideAutocomplete()
	end

	--!
	-- Recomputes the suggestion list from the current input text.
	--!
	local function updateAutocomplete()
		-- Tab: take the tab character back out and pick the highlighted
		-- suggestion (if any). Tabs aren't kept in chat messages.
		if string.find(textBox.Text, "\t", 1, true) then
			local selected = autocompleteFrame.Visible and autocompleteItems[autocompleteSelectedIndex or 1]
			textBox.Text = string.gsub(textBox.Text, "\t", "")
			if selected then
				applyAutocompleteItem(selected)
			end
			return
		end

		clearAutocompleteItems()
		autocompleteItems = {}
		autocompleteSelectedIndex = 1
		autocompleteMode = nil
		emojiMatchStart = nil

		local text = textBox.Text

		if commandProviderFn and text:sub(1, 1) == "/" and not text:find("%s") then
			-- Command suggestions: "/partial" with no space typed yet.
			local query = text:sub(2):lower()

			for _, cmd in ipairs(commandProviderFn()) do
				if #autocompleteItems >= Autocomplete.MAX_ITEMS then
					break
				end

				local matches = query == ""
				or cmd.name:lower():sub(1, #query) == query

				if not matches then
					for _, alias in ipairs(cmd.aliases or {}) do
						if alias:lower():sub(1, #query) == query then
							matches = true
							break
						end
					end
				end

				if matches then
					table.insert(autocompleteItems, {
					type = "command",
					name = cmd.name,
					cmd = cmd,
				})
				end
			end

			autocompleteMode = "command"
		else
			-- Emoji suggestions: a trailing ":shortcode" still being typed.
			local colonPos = text:match(".*():")

			if colonPos then
				local typed = text:sub(colonPos + 1)

				if
					typed:match("^[%w_+-]*$")
					and EmojiData.isValidBoundary(text:sub(1, colonPos - 1))
				then
					for _, entry in ipairs(EmojiData.search(typed, nil, Autocomplete.MAX_ITEMS)) do
						table.insert(autocompleteItems, {
							type = "emoji",
							name = entry.name,
							emoji = entry.emoji,
						})
					end

					autocompleteMode = "emoji"
					emojiMatchStart = colonPos
				end
			end
		end

		if #autocompleteItems > 0 then
			for i, item in ipairs(autocompleteItems) do
				local btn
				if item.type == "command" then
					btn = Autocomplete.createItem(i, item.cmd, themeColors, AdminNetwork.getRankName)
				else
					btn = Autocomplete.createEmojiItem(i, item, themeColors)
				end

				btn.MouseButton1Click:Connect(function()
					applyAutocompleteItem(item)
				end)
				-- Hover highlights the suggestion (arrow keys never reach plugins)
				btn.MouseEnter:Connect(function()
					autocompleteSelectedIndex = i
					updateAutocompleteSelection()
				end)
				btn.Parent = autocompleteFrame
			end

			Autocomplete.setTitle(autocompleteFrame, if autocompleteMode == "command" then "Commands" else "Emoji")
			autocompleteFrame.Visible = true
			updateAutocompleteSelection()
		else
			autocompleteFrame.Visible = false
		end
	end

	textBox:GetPropertyChangedSignal("Text"):Connect(updateAutocomplete)

	-- Send button
	local sendButton = Instance.new("TextButton")
	sendButton.Name = "SendButton"
	sendButton.Size = UDim2.new(0, 33, 0, 33)
	sendButton.Position = UDim2.new(1, -41, 0, 8)
	sendButton.BackgroundColor3 = themeColors.sendButton
	Icons.apply(sendButton, "send", true)
	sendButton.TextColor3 = themeColors.sendButtonText
	sendButton.TextSize = 18
	sendButton.AutoButtonColor = true
	sendButton.BorderSizePixel = 0
	sendButton.Parent = inputFrame

	local sendCorner = Instance.new("UICorner")
	sendCorner.CornerRadius = UDim.new(1, 0)
	sendCorner.Parent = sendButton

	--!
	-- Pending image preview bar (shown above input when image is attached or uploading)
	--!
	local previewBar = Instance.new("Frame")
	previewBar.Name = "PreviewBar"
	previewBar.Size = UDim2.new(1, 0, 0, PREVIEW_HEIGHT)
	previewBar.Position = UDim2.new(0, 0, 1, -(INPUT_HEIGHT + PREVIEW_HEIGHT))
	previewBar.BackgroundColor3 = themeColors.inputFrame
	previewBar.BorderSizePixel = 0
	previewBar.Visible = false
	previewBar.ZIndex = 5
	previewBar.Parent = container

	--!
	-- Reply reference bar (shown above input when replying to a message)
	--!
	local replyBar = Instance.new("Frame")
	replyBar.Name = "ReplyBar"
	replyBar.Size = UDim2.new(1, 0, 0, REPLY_BAR_HEIGHT)
	replyBar.Position = UDim2.new(0, 0, 1, -(INPUT_HEIGHT + PREVIEW_HEIGHT + REPLY_BAR_HEIGHT))
	replyBar.BackgroundColor3 = themeColors.inputFrame
	replyBar.BorderSizePixel = 0
	replyBar.Visible = false
	replyBar.ZIndex = 10
	replyBar.Parent = container

	-- Pill-shaped chip (same look as the message input box) holding the text and close button
	local replyChip = Instance.new("Frame")
	replyChip.Name = "ReplyChip"
	replyChip.Size = UDim2.new(1, -16, 1, -6)
	replyChip.Position = UDim2.new(0, 8, 0, 3)
	replyChip.BackgroundColor3 = themeColors.inputBox
	replyChip.BorderSizePixel = 0
	replyChip.ZIndex = 11
	replyChip.Parent = replyBar

	local replyChipCorner = Instance.new("UICorner")
	replyChipCorner.CornerRadius = UDim.new(1, 0)
	replyChipCorner.Parent = replyChip

	-- "Replying to **Name**" (Discord-style). Children use ZIndex above the
	-- bar's own ZIndex so they are not drawn behind it.
	local replyText = Instance.new("TextLabel")
	replyText.Name = "ReplyText"
	replyText.Size = UDim2.new(1, -40, 1, 0)
	replyText.Position = UDim2.new(0, 12, 0, 0)
	replyText.BackgroundTransparency = 1
	replyText.TextColor3 = themeColors.timestamp
	replyText.Font = FONT
	replyText.TextSize = 13
	replyText.TextXAlignment = Enum.TextXAlignment.Left
	replyText.TextTruncate = Enum.TextTruncate.AtEnd
	replyText.RichText = true
	replyText.Text = ""
	replyText.BorderSizePixel = 0
	replyText.ZIndex = 12
	replyText.Parent = replyChip

	-- Round close button (grey circle with a dark ×), right-aligned
	local replyCloseButton = Instance.new("TextButton")
	replyCloseButton.Name = "ReplyCloseButton"
	replyCloseButton.Size = UDim2.new(0, 18, 0, 18)
	replyCloseButton.AnchorPoint = Vector2.new(1, 0.5)
	replyCloseButton.Position = UDim2.new(1, -4, 0.5, 0)
	replyCloseButton.BackgroundColor3 = themeColors.menuBorder
	Icons.apply(replyCloseButton, "close")
	replyCloseButton.TextColor3 = themeColors.attachIcon
	replyCloseButton.TextSize = 12
	replyCloseButton.AutoButtonColor = true
	replyCloseButton.BorderSizePixel = 0
	replyCloseButton.ZIndex = 12
	replyCloseButton.Parent = replyChip

	local replyCloseCorner = Instance.new("UICorner")
	replyCloseCorner.CornerRadius = UDim.new(1, 0)
	replyCloseCorner.Parent = replyCloseButton

	--!
	-- Typing indicator (Discord-style bouncing dots + "X is typing...").
	--!
	local RunService = game:GetService("RunService")

	local typingLabel = Instance.new("Frame")
	typingLabel.Name = "TypingIndicator"
	typingLabel.Size = UDim2.new(1, -20, 0, 16)
	typingLabel.BackgroundTransparency = 1
	typingLabel.Visible = false
	typingLabel.ZIndex = 6
	typingLabel.BorderSizePixel = 0
	typingLabel.Parent = container

	local typingLayout = Instance.new("UIListLayout")
	typingLayout.FillDirection = Enum.FillDirection.Horizontal
	typingLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	typingLayout.Padding = UDim.new(0, 1)
	typingLayout.Parent = typingLabel

	-- Three dots that ripple in a traveling wave, like Discord's typing animation.
	local typingDots = {}
	for index = 1, 3 do
		local dotHolder = Instance.new("Frame")
		dotHolder.Name = "DotHolder" .. index
		dotHolder.Size = UDim2.fromOffset(4, 8)
		dotHolder.BackgroundTransparency = 1
		dotHolder.Parent = typingLabel

		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.Size = UDim2.fromOffset(4, 4)
		dot.Position = UDim2.new(0, 0, 1, -4)
		dot.BackgroundColor3 = themeColors.timestamp
		dot.BorderSizePixel = 0
		dot.Parent = dotHolder

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		typingDots[index] = dot
	end

	-- Drives the wave: each dot follows the same sine motion, phase-shifted
	-- so the bump travels left-to-right through the dots.
	local waveConnection: RBXScriptConnection? = nil
	local function startWave()
		if waveConnection then return end
		local startTime = os.clock()
		waveConnection = RunService.Heartbeat:Connect(function()
			local t = os.clock() - startTime
			for index, dot in ipairs(typingDots) do
				local phase = t * math.pi * 2 * 1.1 - (index - 1) * (math.pi * 2 / 3)
				local lift = (math.sin(phase) + 1) / 2
				dot.Position = UDim2.new(0, 0, 1, -4 - 4 * lift)
			end
		end)
	end

	local function stopWave()
		if waveConnection then
			waveConnection:Disconnect()
			waveConnection = nil
		end
		for _, dot in ipairs(typingDots) do
			dot.Position = UDim2.new(0, 0, 1, -4)
		end
	end

	local typingText = Instance.new("TextLabel")
	typingText.Name = "Text"
	typingText.Size = UDim2.new(0, 0, 1, 0)
	typingText.AutomaticSize = Enum.AutomaticSize.X
	typingText.BackgroundTransparency = 1
	typingText.FontFace = FONTS.italic
	typingText.TextSize = 12
	typingText.RichText = true
	typingText.TextColor3 = themeColors.timestamp
	typingText.TextXAlignment = Enum.TextXAlignment.Left
	typingText.BorderSizePixel = 0
	typingText.Parent = typingLabel

	local typingTextPadding = Instance.new("UIPadding")
	typingTextPadding.PaddingLeft = UDim.new(0, 4)
	typingTextPadding.Parent = typingText

	local typingUsers = {}

	local function escapeRichText(text: string): string
		return (text:gsub("[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }))
	end

	local function buildTypingText()
		local count = #typingUsers
		if count == 0 then
			return ""
		elseif count == 1 then
			return "<b>" .. escapeRichText(typingUsers[1]) .. "</b> is typing..."
		elseif count == 2 then
			return "<b>" .. escapeRichText(typingUsers[1]) .. "</b> and <b>" .. escapeRichText(typingUsers[2]) .. "</b> are typing..."
		else
			return "<b>Several people</b> are typing..."
		end
	end

	--!
	-- Updates the typing indicator with the list of currently typing users.
	--!
	local function setTypingUsers(names)
		typingUsers = names or {}
		typingLabel.Visible = #typingUsers > 0
		if typingLabel.Visible then
			typingText.Text = buildTypingText()
			startWave()
		else
			stopWave()
		end
	end

	--!
	-- Registers a callback for local typing activity (true/false).
	--!
	local typingActivityCallback: ((boolean) -> ())? = nil
	local function onTypingActivity(fn)
		typingActivityCallback = fn
	end

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if typingActivityCallback then
			typingActivityCallback(#textBox.Text > 0)
		end
	end)
	textBox.FocusLost:Connect(function()
		if typingActivityCallback then
			typingActivityCallback(false)
		end
	end)

	-- Reply reference state
	local replyReferenceTimestamp: number? = nil
	local replyReferenceSender: string? = nil

	local function updateComposerLayout()
		-- Measure the wrapped text at the box's inner width (inside its padding).
		-- (TextBounds can't be used: it is clipped to the box's current height.)
		local horizontalPadding = textBoxPadding.PaddingLeft.Offset + textBoxPadding.PaddingRight.Offset
		local verticalPadding = textBoxPadding.PaddingTop.Offset + textBoxPadding.PaddingBottom.Offset
		local availableWidth = math.max(60, textBox.AbsoluteSize.X - horizontalPadding)
		local measuredHeight = textBox.TextSize
		local ok, bounds = pcall(function()
			local measuredText = textBox.Text == "" and " " or textBox.Text
			return TextService:GetTextSize(measuredText, textBox.TextSize, textBox.Font, Vector2.new(availableWidth, 100000))
		end)
		if ok and bounds then
			measuredHeight = bounds.Y
		end

		-- Box = text + its padding (so the last line is never cut off), at least 33px;
		-- the composer adds 8px above and below the box
		local wantedBoxHeight = math.max(33, math.ceil(measuredHeight) + verticalPadding)
		composerHeight = math.clamp(wantedBoxHeight + 16, INPUT_HEIGHT, MAX_INPUT_HEIGHT)
		inputFrame.Size = UDim2.new(1, 0, 0, composerHeight)
		inputFrame.Position = UDim2.new(0, 0, 1, -composerHeight)
		local textBoxHeight = composerHeight - 16
		textBox.Size = UDim2.new(1, -98, 0, textBoxHeight)
		-- Adaptive corner radius: pill shape (half the height) while single-line,
		-- capped at 16px as the box grows with wrapped text so corners stay proportionally smaller
		local cornerRadius = math.min(textBoxHeight / 2, 16)
		textBoxCorner.CornerRadius = UDim.new(0, cornerRadius)
		attachButton.Position = UDim2.new(0, 8, 1, -41)
		sendButton.Position = UDim2.new(1, -41, 1, -41)
		menuFrame.Position = UDim2.new(0, 4, 1, -(composerHeight + 8))

		local previewSpace = previewBar.Visible and PREVIEW_HEIGHT or 0
	local replySpace = replyBar.Visible and REPLY_BAR_HEIGHT or 0
	local totalBarSpace = previewSpace + replySpace
		scrollFrame.Size = UDim2.new(1, 0, 1, -(composerHeight + totalBarSpace + HEADER_HEIGHT))
		emptyState.Size = UDim2.new(1, 0, 1, -(composerHeight + totalBarSpace + HEADER_HEIGHT))
		divider.Position = UDim2.new(0, 0, 1, -(composerHeight + totalBarSpace))
		previewBar.Position = UDim2.new(0, 0, 1, -(composerHeight + PREVIEW_HEIGHT))
		replyBar.Position = UDim2.new(0, 0, 1, -(composerHeight + previewSpace + REPLY_BAR_HEIGHT))
		scrollButton.Position = UDim2.new(1, -14, 1, -(composerHeight + totalBarSpace + 14))
		typingLabel.Position = UDim2.new(0, 10, 1, -(composerHeight + totalBarSpace + 20))
		if autocompleteFrame then
			autocompleteFrame.Position = UDim2.new(0, 5, 1, -(composerHeight + 8))
		end
	end
	textBox:GetPropertyChangedSignal("Text"):Connect(updateComposerLayout)
	textBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateComposerLayout)
	task.defer(updateComposerLayout)

	local previewPadding = Instance.new("UIPadding")
	previewPadding.PaddingLeft = UDim.new(0, 8)
	previewPadding.PaddingRight = UDim.new(0, 8)
	previewPadding.PaddingTop = UDim.new(0, 4)
	previewPadding.PaddingBottom = UDim.new(0, 4)
	previewPadding.Parent = previewBar

	local previewThumbnail = Instance.new("ImageLabel")
	previewThumbnail.Name = "Thumbnail"
	previewThumbnail.Size = UDim2.new(0, 28, 0, 28)
	previewThumbnail.Position = UDim2.new(0, 0, 0.5, -14)
	previewThumbnail.BackgroundColor3 = themeColors.scrollBack
	previewThumbnail.BorderColor3 = themeColors.previewBorder
	previewThumbnail.BorderSizePixel = 1
	previewThumbnail.ScaleType = Enum.ScaleType.Fit
	previewThumbnail.ZIndex = 6
	previewThumbnail.Parent = previewBar

	local previewThumbCorner = Instance.new("UICorner")
	previewThumbCorner.CornerRadius = UDim.new(0, 4)
	previewThumbCorner.Parent = previewThumbnail

	local previewLabel = Instance.new("TextLabel")
	previewLabel.Name = "Label"
	previewLabel.Size = UDim2.new(1, -70, 1, 0)
	previewLabel.Position = UDim2.new(0, 36, 0, 0)
	previewLabel.BackgroundTransparency = 1
	previewLabel.RichText = true -- file previews embed an inline attachment icon
	previewLabel.Text = "Image attached"
	previewLabel.TextColor3 = themeColors.messageText
	previewLabel.Font = FONT
	previewLabel.TextSize = 12
	previewLabel.TextXAlignment = Enum.TextXAlignment.Left
	previewLabel.ZIndex = 6
	previewLabel.BorderSizePixel = 0
	previewLabel.Parent = previewBar

	local previewRemove = Instance.new("TextButton")
	previewRemove.Name = "Remove"
	previewRemove.Size = UDim2.new(0, 24, 0, 24)
	previewRemove.Position = UDim2.new(1, -24, 0.5, -12)
	previewRemove.BackgroundColor3 = themeColors.attachButton
	Icons.apply(previewRemove, "close")
	previewRemove.TextColor3 = themeColors.attachIcon
	previewRemove.TextSize = 14
	previewRemove.AutoButtonColor = true
	previewRemove.ZIndex = 6
	previewRemove.BorderSizePixel = 0
	previewRemove.Parent = previewBar

	local previewRemoveCorner = Instance.new("UICorner")
	previewRemoveCorner.CornerRadius = UDim.new(0, 4)
	previewRemoveCorner.Parent = previewRemove

	--!
	-- Drag-and-drop overlay (shown when a PluginDrag enters the widget).
	--!
	local dropOverlay = Instance.new("Frame")
	dropOverlay.Name = "DropOverlay"
	dropOverlay.Size = UDim2.new(1, 0, 1, 0)
	dropOverlay.BackgroundColor3 = themeColors.sendButton
	dropOverlay.BackgroundTransparency = 0.85
	dropOverlay.BorderSizePixel = 0
	dropOverlay.Visible = false
	dropOverlay.ZIndex = 30
	dropOverlay.Parent = container

	local dropOverlayCorner = Instance.new("UICorner")
	dropOverlayCorner.CornerRadius = UDim.new(0, 8)
	dropOverlayCorner.Parent = dropOverlay

	local dropOverlayStroke = Instance.new("UIStroke")
	dropOverlayStroke.Color = themeColors.sendButton
	dropOverlayStroke.Thickness = 3
	dropOverlayStroke.Transparency = 0.4
	dropOverlayStroke.Parent = dropOverlay

	local dropLabel = Instance.new("TextLabel")
	dropLabel.Name = "DropLabel"
	dropLabel.Size = UDim2.new(1, -20, 0, 40)
	dropLabel.Position = UDim2.new(0, 0, 0.5, -20)
	dropLabel.BackgroundTransparency = 1
	dropLabel.RichText = true
	dropLabel.Text = Icons.inline("dropFile", false, 20) .. "  Drop to attach"
	dropLabel.TextColor3 = themeColors.sendButtonText
	dropLabel.FontFace = FONTS.display
	dropLabel.TextSize = 16
	dropLabel.ZIndex = 31
	dropLabel.BorderSizePixel = 0
	dropLabel.Parent = dropOverlay

	-- State: the pending image URL (nil if none)
	local pendingImage: string? = nil
	local isUploading = false
	local pendingFile: {fileName: string, fileUrl: string, fileType: string}? = nil

	-- Callbacks set by the main plugin script
	local onVoteCallback: ((number, number) -> ())? = nil
	local onCreatePollCallback: ((string, {string}) -> ())? = nil

	-- Defined further below; the dialogs call it when the theme changes
	local applyTheme

	local function getThemeColors()
		return themeColors
	end

	-- Re-renders shown messages after a clock / timestamp / text size change
	local function refreshMessages()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") then
				for _, labelName in ipairs({ "TextContent", "Body" }) do
					local label = child:FindFirstChild(labelName)
					if label and label:IsA("TextLabel") then
						label.TextSize = messageTextSize
					end
				end
				recolorMessageContainer(child, themeColors)
			end
		end
	end

	-- Modal dialogs: a shared ModalKit shell, each dialog in its own module
	local modalKit = ModalKit.new({
		container = container,
		getThemeColors = getThemeColors,
		isInside = isInside,
		mousePosition = mousePosition,
	})

	local pollDialog = CreatePollDialog.create(modalKit, {
		getThemeColors = getThemeColors,
		onSubmit = function(question, options)
			if onCreatePollCallback then
				onCreatePollCallback(question, options)
			end
		end,
	})

	local settingsDialog = SettingsDialog.create(modalKit, {
		pluginInstance = pluginInstance,
		getThemeColors = getThemeColors,
		detectTheme = detectTheme,
		onThemeChanged = function(paletteName)
			applyTheme(paletteName)
		end,
		onDisplayChanged = refreshMessages,
		onTextSizeChanged = function(sizeName)
			messageTextSize = TEXT_SIZES[sizeName] or TEXT_SIZES.Default
		end,
	})

	-- "What's New"; closing it marks this version's notes as seen
	local changelog = ChangelogDialog.create(modalKit, {
		getThemeColors = getThemeColors,
		onClosed = function()
			if PLUGIN_VERSION then
				pcall(function()
					pluginInstance:SetSetting(PluginConfig.SETTING_KEY_LAST_SEEN_VERSION, PLUGIN_VERSION)
				end)
			end
		end,
	})

	-- "New message": pick a friend or type a username to start a DM
	conversationSidebar.newMessageDialog = NewMessageDialog.create(modalKit, {
		getThemeColors = getThemeColors,
		getHandlers = function()
			return conversationSidebar.newMessageHandlers
		end,
	})

-- Reply reference state (for Discord-style replies)
local replyReferenceTimestamp: number? = nil
local replyReferenceSender: string? = nil
local replyReferenceContent: string? = nil
local replyOriginalDeleted = false
local renderReplyText -- assigned below, forward-declared for removeMessage

	--!
	-- Shows the pending image preview bar.
	--!
	local function showPreview(imageUrl: string, labelText: string?)
		pendingImage = imageUrl
		pendingFile = nil
		GifPlayer.apply(previewThumbnail, imageUrl)
		previewThumbnail.Visible = true
		previewLabel.Text = Icons.escape(labelText or "Image attached")
		previewBar.Visible = true
		
	end

--!
-- Returns the current reply reference (timestamp, sender, content),
-- or nil when no reply is pending.
--!
local function getReplyReference()
	if replyReferenceTimestamp then
		return replyReferenceTimestamp, replyReferenceSender, replyReferenceContent
	end
	return nil
end

--!
-- Replaces a reply's quoted preview with "Original message deleted".
--!
local function markReplyDeleted(msgContainer)
	msgContainer:SetAttribute("ReplyOriginalDeleted", true)
	local ref = msgContainer:FindFirstChild("ReplyReference")
	if not ref then return end
	local label = ref:FindFirstChild("ReplyLabel", true)
	if label and label:IsA("TextLabel") then
		label.RichText = true
		label.Text = string.format('<font color="%s"><i>Original message deleted</i></font>', toHex(themeColors.timestamp))
	end
end

--!
-- After a reply is added, marks it as deleted if the message it replies to
-- is not in the chat (e.g. it was deleted before the plugin loaded).
--!
local function checkReplyTarget(msgContainer, replyRef)
	if not replyRef or not replyRef.timestamp then return end
	task.delay(1, function()
		if not msgContainer.Parent then return end
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child ~= msgContainer and child:GetAttribute("Timestamp") == replyRef.timestamp then
				return
			end
		end
		markReplyDeleted(msgContainer)
	end)
end

--!
-- Removes a message container from the scroll frame by timestamp, and
-- flags any replies (sent or pending) that pointed at it.
--!
local function removeMessage(timestamp: number)
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:GetAttribute("Timestamp") == timestamp then
			child.Parent = nil
			break
		end
	end
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:GetAttribute("ReplyToTimestamp") == timestamp then
			markReplyDeleted(child)
		end
	end
	if replyReferenceTimestamp == timestamp then
		replyOriginalDeleted = true
		renderReplyText()
	end
	showEmptyStateIfNoMessages()
end

	--!
	-- Hides the pending image preview bar.
	--!
	local function hidePreview()
		pendingImage = nil
		pendingFile = nil
		isUploading = false
		previewThumbnail.Image = ""
		previewThumbnail.Visible = true
		previewBar.Visible = false
	end

	--!
	-- Renders the "Replying to Name" header text for the pending reply.
	--!
	function renderReplyText()
		if replyOriginalDeleted and replyReferenceTimestamp then
			replyText.Text = string.format('<font color="%s"><i>Original message deleted</i></font>', toHex(themeColors.timestamp))
			return
		end
		if not replyReferenceSender then
			replyText.Text = ""
			return
		end
		local escapedName = string.gsub(string.gsub(string.gsub(tostring(replyReferenceSender), "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
		replyText.Text = string.format(
			'Replying to <font color="%s"><b>%s</b></font>',
			toHex(UsernameColors.getNameColor(replyReferenceSender)),
			escapedName
		)
	end

	--!
	-- Sets the reply reference and shows the reply bar.
	--!
	local function setReplyReference(timestamp: number, sender: string, content: string)
		replyReferenceTimestamp = timestamp
		replyReferenceSender = sender
		replyReferenceContent = content
		replyOriginalDeleted = false

		renderReplyText()
		replyBar.Visible = true
		updateComposerLayout()
		pcall(function()
			textBox:CaptureFocus()
		end)
	end

	--!
	-- Hides the reply reference bar.
	--!
	local function hideReplyReference()
		replyReferenceTimestamp = nil
		replyReferenceSender = nil
		replyReferenceContent = nil
		replyOriginalDeleted = false
		replyBar.Visible = false
		updateComposerLayout()
	end

	-- Connect reply close button
	replyCloseButton.MouseButton1Click:Connect(hideReplyReference)

	--!
	-- Uploads a local file as a permanent Roblox image asset so it syncs across Team Create.
	-- Falls back to the temporary ID (local-only) if upload fails.
	--!
	local function uploadImageFile(file)
		local tempId = file:GetTemporaryId()

		showPreview(tempId, "Uploading image...")
		isUploading = true

		task.spawn(function()
			local permanentUrl = nil

			local ok1, editableImage = pcall(function()
				return AssetService:CreateEditableImageAsync(Content.fromUri(tempId))
			end)

			if ok1 and editableImage then
				local ok2, result, assetId = pcall(function()
					return AssetService:CreateAssetAsync(editableImage, Enum.AssetType.Image, {
						Name = "TeamChat Image",
						Description = "Image shared via Team Chat plugin",
					})
				end)

				if ok2 and result == Enum.CreateAssetResult.Success and assetId then
					permanentUrl = "rbxassetid://" .. tostring(assetId)
				end
			end

			isUploading = false

			if permanentUrl then
				showPreview(permanentUrl, "Image attached")
			else
				showPreview(tempId, "Image attached (local only)")
				warn("[TeamChat] Could not upload image as permanent asset. Using temporary ID (local only).")
			end
		end)
	end

	--!
	-- Attaches a non-image file. Plugins can't upload audio, video, scripts,
	-- text or model files as Roblox assets (AssetService:CreateAssetAsync only
	-- takes Roblox objects such as EditableImage/EditableMesh/Models), so these
	-- use the file's temporary ID: it works on this computer only, and
	-- collaborators see the file card but can't open it.
	--!
	local function uploadFile(file)
		local fileName = file.Name
		local fileExt = string.lower(string.match(fileName, "%.([^.]+)$") or "")
		local fileType = FILE_EXTENSIONS[fileExt] or "Other"

		-- Show preview with uploading state
		pendingImage = nil
		pendingFile = nil
		previewThumbnail.Image = ""
		previewThumbnail.Visible = false
		previewLabel.Text = Icons.inline("attachFile", false, 14) .. " Uploading " .. Icons.escape(fileName) .. "..."
		previewBar.Visible = true
		updateComposerLayout()

		isUploading = true

		task.spawn(function()
			local permanentUrl = nil -- no plugin upload path exists yet for these types

			isUploading = false

			if permanentUrl then
				pendingFile = {
					fileName = fileName,
					fileUrl = permanentUrl,
					fileType = fileType,
				}
				previewLabel.Text = Icons.inline("attachFile", false, 14) .. " " .. Icons.escape(fileName)
			else
				local tempId = file:GetTemporaryId()
				if tempId and tempId ~= "" then
					pendingFile = {
						fileName = fileName,
						fileUrl = tempId,
						fileType = fileType,
					}
					previewLabel.Text = Icons.inline("attachFile", false, 14) .. " " .. Icons.escape(fileName) .. " (local only)"
					warn("[TeamChat] " .. fileName .. " is shared as a local-only file: plugins can't upload " .. fileType .. " files as Roblox assets, so collaborators won't be able to open it.")
				else
					hidePreview()
					warn("[TeamChat] Could not attach file: " .. fileName)
				end
			end
		end)
	end

	-- Attach menu, file picker and drag-and-drop wiring. In a do block so its
	-- helpers don't count toward create's 200-local limit; only
	-- setAttachMenuOpen is used outside it.
	local setAttachMenuOpen
	do
		--!
		-- Attach (+) menu: the plus button toggles the popup above it; the
		-- full-size click catcher behind the menu closes it on any other click.
		--!
		function setAttachMenuOpen(open: boolean)
			menuFrame.Visible = open
			menuClickCatcher.Visible = open
		end

		attachButton.MouseButton1Click:Connect(function()
			setAttachMenuOpen(not menuFrame.Visible)
		end)
		menuClickCatcher.MouseButton1Click:Connect(function()
			if not isInside(menuFrame, mousePosition()) then
				setAttachMenuOpen(false)
			end
		end)

		menuItemPoll.MouseButton1Click:Connect(function()
			setAttachMenuOpen(false)
			pollDialog.open()
		end)

		--!
		-- "Attach File(s)": opens the file picker. The composer holds one
		-- attachment at a time, so the first chosen file is used.
		--!
		local ATTACH_FILE_FILTER = table.clone(IMAGE_FILTER)
		for extension in pairs(FILE_EXTENSIONS) do
			if not table.find(ATTACH_FILE_FILTER, extension) then
				table.insert(ATTACH_FILE_FILTER, extension)
			end
		end

		local function attachFiles()
			setAttachMenuOpen(false)
			if isUploading then return end

			task.spawn(function()
				local ok, files = pcall(function()
					return StudioService:PromptImportFilesAsync(ATTACH_FILE_FILTER)
				end)
				if not ok then
					warn("[TeamChat] Could not open the file picker: " .. tostring(files))
					return
				end
				local file = files and files[1]
				if not file then return end -- picker cancelled

				local extension = string.lower(string.match(file.Name, "%.([^.]+)$") or "")
				if extension == "gif" then
					-- Decode the GIF into an animated sprite sheet (GifPlayer)
					pendingImage = nil
					pendingFile = nil
					previewThumbnail.Visible = false
					previewLabel.Text = Icons.inline("attachFile", false, 14) .. " Processing " .. Icons.escape(file.Name) .. "..."
					previewBar.Visible = true
					updateComposerLayout()
					isUploading = true
					local gifOk, url, uploaded = pcall(GifPlayer.fromFile, file)
					isUploading = false
					if gifOk then
						showPreview(url, if uploaded then "GIF attached" else "GIF attached (local only)")
					else
						hidePreview()
						warn("[TeamChat] Could not read " .. file.Name .. ": " .. tostring(url))
					end
					updateComposerLayout()
				elseif table.find(IMAGE_FILTER, extension) then
					uploadImageFile(file)
				else
					uploadFile(file)
				end
			end)
		end

		menuItemFile.MouseButton1Click:Connect(attachFiles)

		-- Remove the pending attachment from the composer
		previewRemove.MouseButton1Click:Connect(function()
			hidePreview()
			updateComposerLayout()
		end)

		--!
		-- Drag and drop: dragging an image or file card from the chat onto the
		-- widget shows the drop overlay; dropping attaches it to the composer.
		-- Drag data is "name|url|type" (see the Plugin:StartDrag calls).
		--!

		widget.PluginDragEntered:Connect(function(dragData)
			if dragData.MimeType == ATTACHMENT_MIME_TYPE then
				dropOverlay.Visible = true
			end
		end)
		widget.PluginDragLeft:Connect(function()
			dropOverlay.Visible = false
		end)
		widget.PluginDragDropped:Connect(function(dragData)
			dropOverlay.Visible = false
			if dragData.MimeType ~= ATTACHMENT_MIME_TYPE or type(dragData.Data) ~= "string" then return end

			local fileName, fileUrl, fileType = string.match(dragData.Data, "^(.-)|(.-)|(.-)$")
			if not fileUrl or fileUrl == "" then return end

			if fileType == "Image" then
				showPreview(fileUrl, "Image attached")
			else
				pendingImage = nil
				pendingFile = { fileName = fileName, fileUrl = fileUrl, fileType = fileType }
				previewThumbnail.Image = ""
				previewThumbnail.Visible = false
				previewLabel.Text = Icons.inline("attachFile", false, 14) .. " " .. Icons.escape(fileName)
				previewBar.Visible = true
			end
			updateComposerLayout()
		end)

	end

	--!
	-- Applies the current theme colors to all static UI elements
	-- and re-renders existing message labels.
	--!
	function applyTheme(name)
		themeColors = THEMES[name]
		currentThemeName = name

		container.BackgroundColor3 = themeColors.scrollBack
		scrollFrame.BackgroundColor3 = themeColors.scrollBack
		scrollFrame.ScrollBarImageColor3 = themeColors.scrollBar
		scrollButton.BackgroundColor3 = themeColors.menuBack
		scrollButton.TextColor3 = themeColors.menuItemText or themeColors.messageText
		scrollButtonStroke.Color = themeColors.menuBorder
		recolorContextMenu()
		divider.BackgroundColor3 = themeColors.divider
		inputFrame.BackgroundColor3 = themeColors.inputFrame
		header.BackgroundColor3 = themeColors.inputFrame
		headerTitle.TextColor3 = themeColors.messageText
		renderHeaderTitle()
		headerDivider.BackgroundColor3 = themeColors.divider
		conversationSidebar.list.recolor(themeColors)
		conversationSidebar.newMessageDialog.recolor()
		textBox.BackgroundColor3 = themeColors.inputBox
		textBox.TextColor3 = themeColors.textBoxText
		textBox.PlaceholderColor3 = themeColors.placeholder
		sendButton.BackgroundColor3 = themeColors.sendButton
		sendButton.TextColor3 = themeColors.sendButtonText
		attachButton.BackgroundColor3 = themeColors.attachButton
		attachButton.TextColor3 = themeColors.attachIcon
		typingText.TextColor3 = themeColors.timestamp
		for _, dot in ipairs(typingDots) do
			dot.BackgroundColor3 = themeColors.timestamp
		end

		previewBar.BackgroundColor3 = themeColors.inputFrame
		previewThumbnail.BackgroundColor3 = themeColors.scrollBack
		previewThumbnail.BorderColor3 = themeColors.previewBorder
		previewLabel.TextColor3 = themeColors.messageText
		previewRemove.BackgroundColor3 = themeColors.attachButton
		previewRemove.TextColor3 = themeColors.attachIcon

		dropOverlay.BackgroundTransparency = 0.85
		dropOverlayStroke.Color = themeColors.sendButton
		dropLabel.TextColor3 = themeColors.sendButtonText

		menuFrame.BackgroundColor3 = themeColors.menuBack
		menuStroke.Color = themeColors.menuBorder
		-- (the plus menu's items are recolored with the context menu's in recolorContextMenu)
		modalKit.recolor()
		pollDialog.recolor()
		settingsDialog.recolor()
		changelog.recolor()

		replyBar.BackgroundColor3 = themeColors.inputFrame
		replyChip.BackgroundColor3 = themeColors.inputBox
		replyText.TextColor3 = themeColors.timestamp
		replyCloseButton.BackgroundColor3 = themeColors.menuBorder
		replyCloseButton.TextColor3 = themeColors.attachIcon
		renderReplyText()
		emptyIcon.TextColor3 = themeColors.emptyTitle
		emptyTitleLabel.TextColor3 = themeColors.emptyTitle
		emptySubtitle.TextColor3 = themeColors.emptySubtitle

		Autocomplete.recolor(autocompleteFrame, themeColors)

		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") then
				recolorMessageContainer(child, themeColors)
			end
		end
	end

	-- Forward declaration: addMessage needs to report link-open failures but
	-- addSystemMessage is defined further below.
	local addSystemMessageRef

	local function addMessage(sender, timestamp, content, imageUrl, replyRef)
	hideEmptyState()
	local msgContainer = createMessageContainer(sender, timestamp, content, imageUrl, themeColors, replyRef)
	msgContainer:SetAttribute("Sender", sender)
	msgContainer:SetAttribute("Content", content)
	msgContainer:SetAttribute("Timestamp", timestamp)
	if imageUrl then
		msgContainer:SetAttribute("ImageUrl", imageUrl)
	end
	if replyRef then
		msgContainer:SetAttribute("ReplyToTimestamp", replyRef.timestamp)
		msgContainer:SetAttribute("ReplyToSender", replyRef.sender)
		msgContainer:SetAttribute("ReplyToContent", replyRef.content)
	end

	-- Clickable link support: attach hit-testing to the text label and
	-- add embed cards (handled by EmbedManager) for URLs in the message.
	local textLabel = msgContainer:FindFirstChild("TextContent")
	if textLabel and textLabel:IsA("TextLabel") then
		local linkMeta = LinkHelper.buildMeta(sender, content, timestamp)
		if #linkMeta.links > 0 then
			LinkHelper.attachLinkInteractions(textLabel, linkMeta, pluginInstance, function(url)
				if addSystemMessageRef then
					addSystemMessageRef("Couldn't open the link in your browser, so it was copied to your clipboard: " .. url)
				end
			end)
			local urls = {}
			for _, link in ipairs(linkMeta.links) do
				table.insert(urls, link.url)
			end
			EmbedManager.attach(msgContainer, urls, themeColors, { plugin = pluginInstance })
		end
	end

	msgContainer.Parent = scrollFrame

	checkReplyTarget(msgContainer, replyRef)
	-- Make image attachments draggable via Plugin:StartDrag
	if imageUrl and imageUrl ~= "" then
		local imageAttachment = msgContainer:FindFirstChild("ImageAttachment")
		if imageAttachment and imageAttachment:IsA("ImageLabel") then
			imageAttachment.Active = true
			imageAttachment.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					pluginInstance:StartDrag({
						MimeType = "application/x-teamchat-attachment",
						Data = "Image|" .. imageUrl .. "|Image",
						DragIcon = "",
						DragWidget = imageAttachment,
					})
				end
			end)
		end
	end

	-- Right-click context menu for message interactions (Discord-style)
	msgContainer.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			showContextMenu(msgContainer, sender, timestamp, content, "Message", nil, nil, nil)
		end
	end)
end


	local function addAnnouncementMessage(sender, timestamp, content, replyRef)
		hideEmptyState()
		local msgContainer = createAnnouncementContainer(sender, timestamp, content, themeColors, replyRef)
		msgContainer:SetAttribute("Sender", sender)
		msgContainer:SetAttribute("Timestamp", timestamp)
		msgContainer:SetAttribute("Content", content)
		msgContainer:SetAttribute("IsAnnouncement", true)
		if replyRef then
			msgContainer:SetAttribute("ReplyToTimestamp", replyRef.timestamp)
			msgContainer:SetAttribute("ReplyToSender", replyRef.sender)
			msgContainer:SetAttribute("ReplyToContent", replyRef.content)
		end
		msgContainer.Parent = scrollFrame

		checkReplyTarget(msgContainer, replyRef)
		-- Right-click context menu for announcement interactions (Discord-style)
		msgContainer.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				showContextMenu(msgContainer, sender, timestamp, content, "Announcement", nil, nil, nil)
			end
		end)
	end

	--!
	-- Adds a poll message to the scroll frame with interactive vote bars.
	--!
	local pollContainers = {}

	local function addPollMessage(sender, timestamp, pollData, replyRef)
		hideEmptyState()
		local msgContainer = createPollContainer(sender, timestamp, pollData, themeColors, replyRef)
		msgContainer:SetAttribute("Sender", sender)
		msgContainer:SetAttribute("Timestamp", timestamp)
		msgContainer:SetAttribute("IsPoll", true)
		if replyRef then
			msgContainer:SetAttribute("ReplyToTimestamp", replyRef.timestamp)
			msgContainer:SetAttribute("ReplyToSender", replyRef.sender)
			msgContainer:SetAttribute("ReplyToContent", replyRef.content)
		end
		msgContainer.Parent = scrollFrame
		pollContainers[timestamp] = msgContainer
		checkReplyTarget(msgContainer, replyRef)

		updatePollVotes(msgContainer, pollData, themeColors)

		-- Wire up click-to-vote on each option
		for i = 1, #pollData.options do
			local optionFrame = msgContainer:FindFirstChild("Option_" .. i)
			if optionFrame then
				optionFrame.MouseButton1Click:Connect(function()
					if onVoteCallback then
						onVoteCallback(timestamp, i)
					end
				end)
			end
		end

		-- Right-click context menu for poll interactions (Discord-style)
		msgContainer.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				showContextMenu(msgContainer, sender, timestamp, "", "Poll", pollData.options, pollData.votes, pollData, nil)
			end
		end)
	end

	--!
	-- Updates a poll message with new vote data.
	--!
	local function updatePollMessage(timestamp, pollData)
		local msgContainer = pollContainers[timestamp]
		if msgContainer then
			updatePollVotes(msgContainer, pollData, themeColors)
		end
	end

	--!
	-- Adds a file message to the scroll frame with a file card.
	--!
	local function addFileMessage(sender, timestamp, fileName, fileUrl, fileType, content, replyRef)
	hideEmptyState()
	local msgContainer = createFileContainer(sender, timestamp, content, fileName, fileUrl, fileType, themeColors, replyRef)
	msgContainer:SetAttribute("Sender", sender)
	msgContainer:SetAttribute("Timestamp", timestamp)
	msgContainer:SetAttribute("FileName", fileName)
	msgContainer:SetAttribute("FileUrl", fileUrl)
	msgContainer:SetAttribute("FileType", fileType)
	msgContainer:SetAttribute("IsFile", true)
	if replyRef then
		msgContainer:SetAttribute("ReplyToTimestamp", replyRef.timestamp)
		msgContainer:SetAttribute("ReplyToSender", replyRef.sender)
		msgContainer:SetAttribute("ReplyToContent", replyRef.content)
	end
	msgContainer.Parent = scrollFrame

	checkReplyTarget(msgContainer, replyRef)
	-- Make file/audio cards draggable via Plugin:StartDrag
	local draggableCard = msgContainer:FindFirstChild("FileCard")
		or msgContainer:FindFirstChild("AudioPlayerCard")
	if draggableCard and draggableCard:IsA("Frame") then
		draggableCard.Active = true
		draggableCard.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				for _, controlName in ipairs({ "PlayPauseButton", "Waveform", "DownloadButton" }) do
					local control = draggableCard:FindFirstChild(controlName, true)
					if control and isInside(control, Vector2.new(input.Position.X, input.Position.Y)) then return end
				end
				pluginInstance:StartDrag({
					MimeType = "application/x-teamchat-attachment",
					Data = (fileName or "file") .. "|" .. (fileUrl or "") .. "|" .. (fileType or "Other"),
					DragIcon = "",
					DragWidget = draggableCard,
				})
			end
		end)
	end

	-- Right-click context menu for file interactions (Discord-style)
	msgContainer.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			showContextMenu(msgContainer, sender, timestamp, content or "", "File", nil, nil, nil, {fileName = fileName, fileUrl = fileUrl, fileType = fileType})
		end
	end)
end

	--!
	-- Adds a system message to the chat.
	--!
	local function addSystemMessage(text)
		hideEmptyState()
		local msgContainer = createMessageContainer("System", os.time(), text, nil, themeColors)
		msgContainer:SetAttribute("Sender", "System")
		msgContainer:SetAttribute("Content", text)
		msgContainer:SetAttribute("Timestamp", os.time())
		msgContainer:SetAttribute("IsSystem", true)
		msgContainer.Parent = scrollFrame
		return msgContainer
	end
	addSystemMessageRef = addSystemMessage

	--!
	-- Clears all messages from the chat.
	--!
	local function clearChat()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") and child.Name:match("^Message_") then
				child:Destroy()
			end
		end
		pollContainers = {}
		emptyState.Visible = true
	end

	--!
	-- Conversations: switching empties the message list (PluginController
	-- then shows the new conversation's messages) and updates the header,
	-- placeholder and empty state.
	--!
	function conversationSidebar.reset()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		pollContainers = {}
		hideReplyReference()
		emptyState.Visible = true
	end

	function conversationSidebar.setConversation(info)
		local isDm = info.kind == "dm"
		conversationSidebar.title = if isDm then "@" .. info.name else "Team Chat"
		renderHeaderTitle()
		textBox.PlaceholderText = if isDm then "Message @" .. info.name else "Type a message..."
		Icons.apply(emptyIcon, if isDm then "directMessages" else "emptyChat")
		emptyTitleLabel.Text = if isDm then info.name else "No messages yet"
		emptySubtitle.Text = if isDm
			then "This is the start of your direct messages with " .. info.name .. ". Only the two of you see them here."
			else "Send a message to start the conversation!"
		emptySubtitle.Size = UDim2.new(1, -30, 0, if isDm then 36 else 20)
		conversationSidebar.list.setActive(info.id)
	end

	function conversationSidebar.setConversations(entries, activeId)
		conversationSidebar.list.update(entries, activeId)
	end

	function conversationSidebar.onSelect(callback)
		conversationSidebar.selectCallback = callback
	end

	function conversationSidebar.onClose(callback)
		conversationSidebar.closeCallback = callback
	end

	-- { getFriends, resolveUser, onPick } for the New message dialog
	function conversationSidebar.setNewMessageHandlers(handlers)
		conversationSidebar.newMessageHandlers = handlers
	end

	--!
	-- Sets the widget visibility.
	--!
	local function setVisible(visible)
		widget.Enabled = visible
		if visibilityCallback then
			visibilityCallback(visible)
		end
	end

	--!
	-- Registers a callback for widget visibility changes.
	--!
	local visibilityCallback
	local function onVisibilityChanged(fn)
		visibilityCallback = fn
	end

	--!
	-- Sets the command provider function for autocomplete.
	--!
	local function setCommandProvider(fn)
		commandProviderFn = fn
	end

	--!
	-- Returns the pending image URL (nil if none).
	--!
	local function getPendingImage()
		return pendingImage
	end

	--!
	-- Clears the pending image and hides the preview bar.
	--!
	local function clearPendingImage()
		pendingImage = nil
		hidePreview()
	end

	--!
	-- Returns the pending file (nil if none).
	--!
	local function getPendingFile()
		return pendingFile
	end

	--!
	-- Clears the pending file and hides the preview bar.
	--!
	local function clearPendingFile()
		pendingFile = nil
		hidePreview()
	end

	--!
	-- Returns whether an upload is in progress.
	--!
	local function isUploadingFn()
		return isUploading
	end

	--!
	-- Returns whether the autocomplete dropdown is visible.
	--!
	local function isAutocompleteVisible()
		return autocompleteFrame and autocompleteFrame.Visible or false
	end

	--!
	-- Registers a callback for vote casting.
	--!
	local function onVote(fn)
		onVoteCallback = fn
	end

	--!
	-- Registers a callback for poll creation.
	--!
	local function onCreatePoll(fn)
		onCreatePollCallback = fn
	end

	--!
	-- Registers a callback for message reply.
	--!
	local function onReply(fn)
		onReplyCallback = fn
	end

	--!
	-- Registers a callback for message deletion.
	--!
	local function onDelete(fn)
		onDeleteCallback = fn
	end

	--!
	-- Registers a callback for message copy.
	--!
	local function onCopy(fn)
		onCopyCallback = fn
	end

	-- Restore the saved settings, then apply the theme they pick
	settingsDialog.restore()
	applyTheme(settingsDialog.resolveTheme())

	-- "What's New": the sidebar button toggles it
	sidebarWhatsNewButton.MouseButton1Click:Connect(function()
		if changelog.isVisible() then
			changelog.close()
		else
			changelog.open(PLUGIN_VERSION)
		end
	end)

	-- Pop up once per published version. Only big updates get a changelog
	-- entry; small version bumps have none, so nothing pops up for them.
	local lastSeenOk, lastSeenVersion = pcall(function()
		return pluginInstance:GetSetting(PluginConfig.SETTING_KEY_LAST_SEEN_VERSION)
	end)
	if PLUGIN_VERSION and changelog.hasNotesFor(PLUGIN_VERSION) and not (lastSeenOk and lastSeenVersion == PLUGIN_VERSION) then
		task.defer(function()
			widget.Enabled = true -- the chat panel may be closed; open it so the popup is seen
			changelog.open(PLUGIN_VERSION)
		end)
	end

	-- The sidebar gear button toggles the settings dialog
	sidebarSettingsButton.MouseButton1Click:Connect(function()
		if settingsDialog.isVisible() then
			settingsDialog.close()
		else
			settingsDialog.open()
		end
	end)

	-- Clicking anywhere outside the widget (3D view, Explorer, another
	-- panel...) moves focus away from it: close any open menu or modal.
	widget.WindowFocusReleased:Connect(function()
		hideContextMenu()
		hideAutocomplete()
		setAttachMenuOpen(false)
		if pollDialog.isVisible() then
			pollDialog.close()
		end
		settingsDialog.closeFromFocusLoss()
		if changelog.isVisible() then
			changelog.close()
		end
	end)

	-- Sync widget visibility changes back to callbacks
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if visibilityCallback then
			visibilityCallback(widget.Enabled)
		end
	end)

	return {
		widget = widget,
		textBox = textBox,
		sendButton = sendButton,
		addMessage = addMessage,
		addAnnouncementMessage = addAnnouncementMessage,
		addPollMessage = addPollMessage,
		addFileMessage = addFileMessage,
		addSystemMessage = addSystemMessage,
		updatePollMessage = updatePollMessage,
		setReplyReference = setReplyReference,
		getReplyReference = getReplyReference,
		clearReplyReference = hideReplyReference,
		removeMessage = removeMessage,
		clearChat = clearChat,
		resetMessages = conversationSidebar.reset,
		setConversation = conversationSidebar.setConversation,
		setConversations = conversationSidebar.setConversations,
		onConversationSelected = conversationSidebar.onSelect,
		setNewMessageHandlers = conversationSidebar.setNewMessageHandlers,
		onConversationClosed = conversationSidebar.onClose,
		setVisible = setVisible,
		onVisibilityChanged = onVisibilityChanged,
		openSettings = settingsDialog.open,
		closeSettings = settingsDialog.close,
		openChangelog = changelog.open,
		toggleSettings = settingsDialog.toggle,
		isSettingsVisible = settingsDialog.isVisible,
		onSettingsVisibilityChanged = settingsDialog.onVisibilityChanged,
		setCommandProvider = setCommandProvider,
		getPendingImage = getPendingImage,
		clearPendingImage = clearPendingImage,
		getPendingFile = getPendingFile,
		clearPendingFile = clearPendingFile,
		isUploading = isUploadingFn,
		isAutocompleteVisible = isAutocompleteVisible,
		isEnterToSendEnabled = settingsDialog.isEnterToSendEnabled,
		onVote = onVote,
		onCreatePoll = onCreatePoll,
		onReply = onReply,
		onDelete = onDelete,
		onCopy = onCopy,
		setTypingUsers = setTypingUsers,
		onTypingActivity = onTypingActivity,
	}
end

return ChatUI
