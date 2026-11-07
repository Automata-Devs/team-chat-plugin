--[[
	Messages/TextMessage

	A normal message, Discord style: optional reply line, the author header
	(avatar, name, time; see Author), the text and an optional inline image
	(GIFs animate through GifPlayer).
]]

local AssetService = game:GetService("AssetService")

local Author = require(script.Parent.Author)
local GifPlayer = require(script.Parent.Parent.Components.GifPlayer)
local MentionPills = require(script.Parent.Parent.Text.MentionPills)
local MessageText = require(script.Parent.Parent.Text.MessageText)
local Shared = require(script.Parent.Shared)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT
local MAX_IMAGE_HEIGHT = Theme.MAX_IMAGE_HEIGHT
local MAX_IMAGE_WIDTH = 200

-- Pixel sizes of images already looked up, by asset URL (false = unknown)
local imageSizes: { [string]: Vector2 | false } = {}

-- Calls back with an image's pixel size: from a GIF's sprite-sheet suffix,
-- or read once from the asset (cached). Not called when it can't be read.
local function withImageSize(url: string, callback: (Vector2) -> ())
	local base, gif = GifPlayer.parse(url)
	if gif then
		callback(Vector2.new(gif.frameWidth, gif.frameHeight))
		return
	end
	local known = imageSizes[base]
	if known then
		callback(known)
		return
	elseif known == false then
		return
	end
	task.spawn(function()
		local ok, image = pcall(function()
			return AssetService:CreateEditableImageAsync(Content.fromUri(base))
		end)
		if ok and image then
			local size = image.Size -- read before Destroy (it's 0 x 0 after)
			image:Destroy()
			imageSizes[base] = size
			callback(size)
		else
			imageSizes[base] = false
		end
	end)
end

local TextMessage = {}

--!
-- Creates a message container (Frame) with optional inline image.
--!
function TextMessage.create(sender, timestamp, content, imageUrl, themeColors, replyRef, senderId)
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
	containerLayout.Padding = UDim.new(0, 2)
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

	Author.attach(container, sender, senderId, timestamp, themeColors)
	-- Mentions you, or replies to you: the gold look (needs SenderId from Author)
	Shared.applyMention(container, themeColors, content)

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextContent"
	textLabel.Font = FONT
	textLabel.TextSize = Shared.textSize
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
	-- Markdown, links, @mentions and #tags (UI/MessageText)
	MessageText.set(textLabel, content, themeColors)
	textLabel.Visible = content ~= "" -- image-only messages show just the image
	MentionPills.attach(textLabel, themeColors)

	if imageUrl and imageUrl ~= "" then
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "ImageAttachment"
		GifPlayer.apply(imageLabel, imageUrl)
		imageLabel.BackgroundColor3 = themeColors.scrollBack
		imageLabel.BorderColor3 = themeColors.imageBorder
		imageLabel.BorderSizePixel = 1
		imageLabel.ScaleType = Enum.ScaleType.Fit
		imageLabel.Size = UDim2.new(0, MAX_IMAGE_WIDTH, 0, MAX_IMAGE_HEIGHT) -- until its real size is known
		imageLabel.LayoutOrder = 2
		imageLabel.Parent = container

		local imageCorner = Instance.new("UICorner")
		imageCorner.CornerRadius = UDim.new(0, 8)
		imageCorner.Parent = imageLabel

		imageLabel:GetPropertyChangedSignal("Image"):Connect(function()
			if imageLabel.Image == "" then
				imageLabel.Visible = false
			end
		end)

		-- Size the box to the image's shape (fitted inside the max size), so it
		-- lines up with the text instead of sitting centered in empty space
		withImageSize(imageUrl, function(size: Vector2)
			if size.X <= 0 or size.Y <= 0 or not imageLabel.Parent then
				return
			end
			local scale = math.min(MAX_IMAGE_WIDTH / size.X, MAX_IMAGE_HEIGHT / size.Y, 1)
			imageLabel.Size =
				UDim2.fromOffset(math.max(1, math.floor(size.X * scale)), math.max(1, math.floor(size.Y * scale)))
		end)
	end

	return container
end

--[=[
	Re-renders a message's text from its Content and Edited attributes
	(after an edit, or a theme change).
]=]
function TextMessage.setBody(container, palette)
	local label = container:FindFirstChild("TextContent")
	if not label then
		return
	end
	local content = container:GetAttribute("Content") or ""
	local edited = container:GetAttribute("Edited") == true
	MessageText.set(label, content, palette, { edited = edited })
	label.Visible = content ~= "" or edited
	Shared.applyMention(container, palette, content)
end

return TextMessage
