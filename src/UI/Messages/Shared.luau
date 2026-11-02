--[[
	Messages/Shared

	State and pieces shared by every message builder: the message text size,
	the jump-to-message handler (set by ChatWindow), the reply line shown above
	replies and the rounded surface that the jump flash lights up.
]]

local Author = require(script.Parent.Author)
local BadgeIcons = require(script.Parent.Parent.Components.BadgeIcons)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Markdown = require(script.Parent.Parent.Parent.Util.Markdown)
local Mentions = require(script.Parent.Parent.Parent.Util.Mentions)
local RichText = require(script.Parent.Parent.Parent.Util.RichText)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local UsernameColors = require(script.Parent.Parent.Parent.Util.UsernameColors)

local FONTS = Theme.FONTS

local Shared = {}

-- Message text size options (pixel sizes), chosen in Settings.
Shared.TEXT_SIZES = { Small = 12, Default = 14, Large = 16 }
Shared.textSize = Shared.TEXT_SIZES.Default

-- Scrolls to a message by timestamp and flashes it. Assigned by ChatWindow
-- (it needs the scroll frame); reply rows call it when clicked.
Shared.jumpToMessage = nil :: ((number) -> ())?

local REPLY_ROW_HEIGHT = 20
local REPLY_PREVIEW_MAX_LENGTH = 100
local REPLY_NAME_TRANSPARENCY = 0.5 -- the replied-to username is drawn at half opacity
local MINI_AVATAR_SIZE = 16
local SPINE_THICKNESS = 2
local MINI_AVATAR_TRANSPARENCY = 0.2 -- the reply's mini avatar is a little see-through
local SPINE_RADIUS = 6 -- the reply line's rounded corner
local SPINE_END_GAP = 4 -- between the line and the mini avatar
local SPINE_AVATAR_GAP = 3 -- between the line and the message's avatar
local MENTION_BLUE = Color3.fromRGB(88, 101, 242) -- @mentions in reply previews
local MENTION_BAR_WIDTH = 2 -- the gold bar on the left of a message that mentions you

--[=[
	Shows the original author's headshot in a reply line (pass the row or the
	message container). Older replies don't store the id; ChatWindow fills it
	in from the original message once it's found.
]=]
function Shared.setReplyAvatar(rowOrContainer: Instance, userId: number?, themeColors: any?)
	local row = if rowOrContainer.Name == "ReplyReference"
		then rowOrContainer
		else rowOrContainer:FindFirstChild("ReplyReference")
	local miniAvatar = row and row:FindFirstChild("MiniAvatar") :: ImageLabel?
	if not miniAvatar or type(userId) ~= "number" or userId <= 0 then
		return
	end
	miniAvatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=48&h=48"
	miniAvatar:SetAttribute("Headshot", true)
	local initial = miniAvatar:FindFirstChild("Initial") :: TextLabel?
	if initial then
		initial.Visible = false
	end
	if themeColors and row then
		Shared.recolorReply(row, themeColors)
	end
end

--[=[
	(Re)writes a reply line's text: the original author's name (display name
	or username, per Settings) with their verified badge, then the preview.
	Called again when names or verified flags come in; a reply whose original
	was deleted keeps "Original message deleted".
]=]
function Shared.renderReplyLabel(row: Instance)
	local label = row:FindFirstChild("ReplyLabel") :: TextLabel?
	local container = row.Parent
	if not label or (container and container:GetAttribute("ReplyOriginalDeleted")) then
		return
	end
	local sender = row:GetAttribute("ReplySender") or ""
	local senderId = row:GetAttribute("ReplySenderId")
	label.Text = string.format(
		'<font color="%s" weight="semibold" transparency="%.2f">%s</font>%s  %s',
		RichText.toHex(UsernameColors.getNameColor(sender)),
		REPLY_NAME_TRANSPARENCY,
		Icons.escape(Author.nameOf(sender, senderId)),
		BadgeIcons.verifiedSuffix(Author.isVerified(senderId), 12),
		row:GetAttribute("ReplyPreview") or ""
	)
end

-- The reply line: up from the message's avatar, a rounded corner, then
-- right towards the mini avatar. A Path2D, so the line is the same even
-- thickness all the way round. The "Spine" frame's left edge is the avatar's
-- centre and its top is the middle of the reply row.
local function createSpine(row: Frame)
	-- From the reply row's middle down to the avatar's top: half the row, the
	-- message's 2px list padding and the avatar's 1px offset in its header
	local toAvatar = REPLY_ROW_HEIGHT // 2 + 2 + 1
	local width = Author.AVATAR_CENTER_OFFSET - SPINE_END_GAP
	local height = toAvatar - SPINE_AVATAR_GAP

	local spine = Instance.new("Frame")
	spine.Name = "Spine"
	spine.BackgroundTransparency = 1
	spine.Position = UDim2.fromOffset(-Author.AVATAR_CENTER_OFFSET, REPLY_ROW_HEIGHT // 2)
	spine.Size = UDim2.fromOffset(width, height)
	spine.Parent = row

	-- A quarter circle as a Bézier curve: handles 0.5523 × the radius long
	local handle = SPINE_RADIUS * 0.5523
	local line = Instance.new("Path2D")
	line.Name = "Line"
	line.Thickness = SPINE_THICKNESS
	line:SetControlPoints({
		Path2DControlPoint.new(UDim2.fromOffset(0, height)),
		Path2DControlPoint.new(UDim2.fromOffset(0, SPINE_RADIUS), UDim2.new(), UDim2.fromOffset(0, -handle)),
		Path2DControlPoint.new(UDim2.fromOffset(SPINE_RADIUS, 0), UDim2.fromOffset(-handle, 0), UDim2.new()),
		Path2DControlPoint.new(UDim2.fromOffset(width, 0)),
	})
	line.Parent = spine
end

--[=[
	Re-themes a reply row: its line, and the mini avatar's background (the
	plain avatar background behind a headshot, like message avatars; the
	author's name colour behind their initial).
]=]
function Shared.recolorReply(row: Instance, themeColors)
	local miniAvatar = row:FindFirstChild("MiniAvatar") :: ImageLabel?
	if miniAvatar and miniAvatar:GetAttribute("Headshot") then
		miniAvatar.BackgroundColor3 = themeColors.menuItemHover
	end
	local spine = row:FindFirstChild("Spine")
	local line = spine and spine:FindFirstChild("Line") :: Path2D?
	if line then
		-- Muted: the timestamp colour 45% of the way to the background
		-- (plugins can't set a Path2D's Transparency)
		line.Color3 = themeColors.timestamp:Lerp(themeColors.scrollBack, 0.45)
	end
end

--[=[
	The line above a reply: a mini avatar of the original author, their name
	(half opacity) and a one-line preview. With `withSpine` (messages that have
	an author header) a thin curved line runs from the reply's avatar up to it,
	like Discord; rows without an avatar (polls, announcements) show the reply
	arrow instead. Clicking it scrolls to the
	original and flashes it. The text label is named "ReplyLabel" (ChatWindow
	rewrites it when the original is deleted). The caller sets LayoutOrder and
	Parent.
]=]
function Shared.createReplyReference(replyRef, themeColors, withSpine: boolean?)
	local replyColor = UsernameColors.getNameColor(replyRef.sender)

	local row = Instance.new("Frame")
	row.Name = "ReplyReference"
	row.Size = UDim2.new(1, 0, 0, REPLY_ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0

	local x = 0
	local replyIcon: TextLabel? = nil
	if withSpine == true then
		createSpine(row)
	else
		local icon = Instance.new("TextLabel")
		icon.Name = "ReplyIcon"
		icon.Size = UDim2.new(0, 14, 1, 0)
		icon.BackgroundTransparency = 1
		Icons.apply(icon, "reply")
		icon.TextColor3 = themeColors.timestamp
		icon.TextSize = 14
		icon.Parent = row
		replyIcon = icon
		x += 18
	end

	-- Mini avatar of the original author (headshot, or their initial)
	local miniAvatar = Instance.new("ImageLabel")
	miniAvatar.Name = "MiniAvatar"
	miniAvatar.AnchorPoint = Vector2.new(0, 0.5)
	miniAvatar.Position = UDim2.new(0, x, 0.5, 0)
	miniAvatar.Size = UDim2.fromOffset(MINI_AVATAR_SIZE, MINI_AVATAR_SIZE)
	miniAvatar.BackgroundColor3 = replyColor
	miniAvatar.BackgroundTransparency = MINI_AVATAR_TRANSPARENCY
	miniAvatar.ImageTransparency = MINI_AVATAR_TRANSPARENCY
	miniAvatar.BorderSizePixel = 0
	miniAvatar.ScaleType = Enum.ScaleType.Crop
	miniAvatar.Parent = row
	local miniCorner = Instance.new("UICorner")
	miniCorner.CornerRadius = UDim.new(1, 0)
	miniCorner.Parent = miniAvatar
	local initial = Instance.new("TextLabel")
	initial.Name = "Initial"
	initial.Size = UDim2.fromScale(1, 1)
	initial.BackgroundTransparency = 1
	initial.FontFace = FONTS.bold
	initial.TextSize = 10
	initial.TextColor3 = Color3.new(1, 1, 1)
	initial.TextTransparency = MINI_AVATAR_TRANSPARENCY
	initial.Text = string.upper(string.sub(replyRef.sender or "?", 1, 1))
	initial.Parent = miniAvatar
	Shared.setReplyAvatar(row, replyRef.senderId)
	Shared.recolorReply(row, themeColors)
	x += MINI_AVATAR_SIZE + 6

	-- Name in the author's color (half opacity) + muted single-line preview
	local preview = string.gsub(Markdown.strip(replyRef.content), "%s+", " ")
	local previewLength = utf8.len(preview)
	if previewLength and previewLength > REPLY_PREVIEW_MAX_LENGTH then
		preview = string.sub(preview, 1, utf8.offset(preview, REPLY_PREVIEW_MAX_LENGTH + 1) - 1) .. "\u{2026}"
	end
	-- @mentions in the preview show in the mention blue
	local previewText = if preview == "" then "<i>Attachment</i>" else RichText.colorMentions(preview, MENTION_BLUE)
	row:SetAttribute("ReplySender", replyRef.sender or "")
	row:SetAttribute("ReplySenderId", replyRef.senderId or 0)
	row:SetAttribute("ReplyPreview", previewText)

	local label = Instance.new("TextLabel")
	label.Name = "ReplyLabel"
	label.Position = UDim2.fromOffset(x, 0)
	label.Size = UDim2.new(1, -(x + 6), 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = FONTS.body
	label.TextSize = 13
	label.TextColor3 = themeColors.timestamp
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.RichText = true
	label.Parent = row
	Shared.renderReplyLabel(row)

	-- Hover: brighter text (plugins can't change the cursor); click jumps to the original
	row.MouseEnter:Connect(function()
		label.TextColor3 = themeColors.messageText
		if replyIcon then
			replyIcon.TextColor3 = themeColors.messageText
		end
	end)
	row.MouseLeave:Connect(function()
		label.TextColor3 = themeColors.timestamp
		if replyIcon then
			replyIcon.TextColor3 = themeColors.timestamp
		end
	end)
	row.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and Shared.jumpToMessage and replyRef.timestamp then
			Shared.jumpToMessage(replyRef.timestamp)
		end
	end)

	return row
end

--[=[
	Gives a message container a rounded, normally invisible background that
	the jump-to-reply flash lights up (see flashMessage). Recolor keeps its
	color in sync with the theme via the HoverHighlight attribute.
]=]
function Shared.addMessageSurface(container, themeColors)
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

--[=[
	The line under a private bot message, like Discord: an eye, "Only you can
	see this" and a "Dismiss message" link that calls `onDismiss`.
]=]
function Shared.addOnlyYouNote(container: Instance, palette, onDismiss: () -> ())
	local note = Instance.new("Frame")
	note.Name = "OnlyYouNote"
	note.BackgroundTransparency = 1
	note.Size = UDim2.new(1, 0, 0, 18)
	note.LayoutOrder = 90 -- under the text and any card
	note.Parent = container
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = note

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(14, 14)
	icon.TextSize = 13
	icon.LayoutOrder = 1
	icon.Parent = note
	Icons.apply(icon, "onlyYou")

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(0, 1)
	text.AutomaticSize = Enum.AutomaticSize.X
	text.FontFace = FONTS.body
	text.TextSize = 11
	text.Text = Language.t("bot.onlyYou") .. "  \u{00B7}"
	text.LayoutOrder = 2
	text.Parent = note

	local dismiss = Instance.new("TextButton")
	dismiss.Name = "Dismiss"
	dismiss.BackgroundTransparency = 1
	dismiss.AutoButtonColor = false
	dismiss.Size = UDim2.fromScale(0, 1)
	dismiss.AutomaticSize = Enum.AutomaticSize.X
	dismiss.FontFace = FONTS.semibold
	dismiss.TextSize = 11
	dismiss.Text = Language.t("bot.dismiss")
	dismiss.LayoutOrder = 3
	dismiss.Parent = note
	dismiss.MouseButton1Click:Connect(onDismiss)
	-- Underlined on hover, like a link (plugins can't change the cursor)
	dismiss.MouseEnter:Connect(function()
		dismiss.RichText = true
		dismiss.Text = "<u>" .. Language.t("bot.dismiss") .. "</u>"
	end)
	dismiss.MouseLeave:Connect(function()
		dismiss.RichText = false
		dismiss.Text = Language.t("bot.dismiss")
	end)
	Shared.recolorOnlyYouNote(container, palette)
end

--[=[
	Re-themes the "Only you can see this" line (after a theme change).
]=]
function Shared.recolorOnlyYouNote(container: Instance, palette)
	local note = container:FindFirstChild("OnlyYouNote")
	if not note then
		return
	end
	(note:FindFirstChild("Icon") :: TextLabel).TextColor3 = palette.timestamp;
	(note:FindFirstChild("Text") :: TextLabel).TextColor3 = palette.timestamp;
	(note:FindFirstChild("Dismiss") :: TextButton).TextColor3 = palette.sendButton
end

--[=[
	The names the person using the plugin goes by: their username and, once
	their profile has loaded, their display name.
]=]
function Shared.myNames(): { string }
	local names = { Identity.username }
	local profile = if Author.getProfile and Identity.userId > 0 then Author.getProfile(Identity.userId) else nil
	if profile and profile.displayName and profile.displayName ~= "" then
		table.insert(names, profile.displayName)
	end
	return names
end

--[=[
	Whether a message is for the person using the plugin: it mentions them
	(by username or display name, or @everyone) or, given its `container`, it
	replies to one of their messages (like a Discord reply ping).
]=]
function Shared.mentionsMe(content: string?, container: Instance?): boolean
	if Identity.userId <= 0 then
		return false
	end
	if container then
		local replyTo = container:GetAttribute("ReplyToSenderId")
		local sender = container:GetAttribute("SenderId")
		if replyTo == Identity.userId and sender ~= Identity.userId then
			return true
		end
	end
	return Mentions.mentions(content, Shared.myNames())
end

-- The mention look's background: solid for the bar's width on the left,
-- tinted for the rest (a gradient, since every child of a message is laid
-- out in its list and can't be a separate bar)
local function fitMentionBar(container: GuiObject, gradient: UIGradient)
	local width = math.max(container.AbsoluteSize.X, 1)
	local edge = math.clamp(MENTION_BAR_WIDTH / width, 0.001, 0.5)
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(edge, 0),
		NumberSequenceKeypoint.new(edge + 0.0005, Theme.MENTION_ROW_TRANSPARENCY),
		NumberSequenceKeypoint.new(1, Theme.MENTION_ROW_TRANSPARENCY),
	})
end

--[=[
	Gives a message the "you were mentioned" look (a gold tint with a gold bar
	on the left, like Discord) when `content` mentions you, and takes it away
	when it doesn't (e.g. after an edit). Sets the Mentioned attribute.
]=]
function Shared.applyMention(container: GuiObject, palette, content: string?)
	local mentioned = Shared.mentionsMe(content, container)
	container:SetAttribute("Mentioned", mentioned)
	local gradient = container:FindFirstChild("MentionGradient") :: UIGradient?
	if not mentioned then
		if gradient then
			gradient:Destroy()
			container.BackgroundTransparency = 1
			container.BackgroundColor3 = palette.menuItemHover
		end
		return
	end
	if not gradient then
		local made = Instance.new("UIGradient")
		made.Name = "MentionGradient"
		made.Parent = container
		container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fitMentionBar(container, made)
		end)
		gradient = made
	end
	local mentionGradient = gradient :: UIGradient
	mentionGradient.Enabled = true
	fitMentionBar(container, mentionGradient)
	container.BackgroundColor3 = palette.mentionRow
	container.BackgroundTransparency = 0
end

return Shared
