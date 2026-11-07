--!strict
--[[
	Messages/Author

	The Discord-style author header of a message: a round Roblox headshot on
	the left and "Name  12:34" above the text. The whole message is indented
	so its text, images, embeds and file cards line up under the name; the
	avatar hangs into that indent.

	System messages get a round badge with a code icon instead of a headshot,
	and senders without a user id get their initial. Badges (verified, custom,
	bought) follow the name as icons with a tooltip; the name is the display
	name or username (Settings). ChatWindow sets Author.getBadges,
	Author.getProfile and Author.tooltip.

	Usage:
		Author.attach(container, sender, senderId, timestamp, palette)  -- in a builder
		Author.render(container, palette)                               -- after theme/clock/badge changes
		Author.nameOf("builderman", 156)                                -- display name or username
]]

local BadgeIcons = require(script.Parent.Parent.Components.BadgeIcons)
local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Preferences = require(script.Parent.Parent.Common.Preferences)
local RichText = require(script.Parent.Parent.Parent.Util.RichText)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local TimeFormat = require(script.Parent.Parent.Parent.Util.TimeFormat)
local UsernameColors = require(script.Parent.Parent.Parent.Util.UsernameColors)

local AVATAR_SIZE = 36
local AVATAR_GAP = 10 -- between the avatar and the text column
local HEADER_HEIGHT = 18
local SYSTEM_SENDER = "System"
local BADGE_SIZE = 14

type Palette = { [string]: Color3 }

local Author = {}

-- The badges of a user id (RichText.Badge list). Assigned by ChatWindow from
-- the badge service; UI modules don't require services.
Author.getBadges = nil :: ((number) -> { RichText.Badge })?

-- A user id's profile ({ displayName?, verified }). Assigned by ChatWindow.
Author.getProfile = nil :: ((number) -> { displayName: string?, verified: boolean })?

-- Shows/hides the badge tooltip (a Components/Tooltip). Assigned by ChatWindow.
Author.tooltip = nil :: {
	show: (GuiObject, string) -> (),
	hide: (GuiObject?) -> (),
}?

--[=[
	A badge's tooltip text: just its name.
]=]
function Author.tooltipText(badge: RichText.Badge): string
	local id = (badge :: any).id or (if badge.verified then "verified" else nil)
	local name = badge.name or "Badge"
	return RichText.escape(if id then Language.tOr("badge." .. tostring(id) .. ".name", name) else name)
end

--[=[
	The name shown for a sender: their display name or username (Settings).
	The plugin's own messages ("System") show as Team Chat.
]=]
function Author.nameOf(sender: string, senderId: number?): string
	if sender == SYSTEM_SENDER then
		return Constants.PLUGIN_TITLE
	end
	if not Author.getProfile or type(senderId) ~= "number" or senderId <= 0 then
		return sender
	end
	return Preferences.nameFor(sender, Author.getProfile(senderId).displayName)
end

--[=[
	Whether a user id belongs to a verified Roblox account (when known).
]=]
function Author.isVerified(senderId: number?): boolean
	return Author.getProfile ~= nil
		and type(senderId) == "number"
		and senderId > 0
		and Author.getProfile(senderId).verified
end

-- How far message content is indented (container padding included).
Author.INDENT = AVATAR_SIZE + AVATAR_GAP + 4
-- How far left of the content the avatar's center is (reply lines draw to it).
Author.AVATAR_CENTER_OFFSET = AVATAR_GAP + AVATAR_SIZE // 2

local function headshotUrl(userId: number): string
	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
end

-- The badge shown instead of a headshot (System, or no user id)
local function styleBadge(avatar: ImageLabel, sender: string, palette: Palette)
	local badge = avatar:FindFirstChild("Badge") :: TextLabel?
	if not badge then
		return
	end
	if sender == SYSTEM_SENDER then
		avatar.BackgroundColor3 = palette.sendButton
		badge.TextColor3 = palette.sendButtonText
	else
		avatar.BackgroundColor3 = UsernameColors.getNameColor(sender)
		badge.TextColor3 = Color3.new(1, 1, 1)
	end
end

--[=[
	Adds the author header (and avatar) to a message container built with a
	vertical UIListLayout and Shared.addMessageSurface. Stores SenderId on the
	container. The header uses LayoutOrder 0; put a reply line before it (-1).
]=]
function Author.attach(container: Frame, sender: string, senderId: number?, timestamp: number, palette: Palette)
	container:SetAttribute("SenderId", senderId or 0)
	container:SetAttribute("HasAuthor", true)

	local padding = container:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingLeft = UDim.new(0, Author.INDENT)
		padding.PaddingTop = UDim.new(0, 4)
		padding.PaddingBottom = UDim.new(0, 4)
	end

	local header = Instance.new("Frame")
	header.Name = "Author"
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.LayoutOrder = 0
	header:SetAttribute("Sender", sender)
	header:SetAttribute("Timestamp", timestamp)
	header.Parent = container

	-- Name, badges and time in a row (the avatar stays outside the layout)
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.Size = UDim2.fromScale(1, 1)
	line.BackgroundTransparency = 1
	line.Parent = header
	local lineLayout = Instance.new("UIListLayout")
	lineLayout.FillDirection = Enum.FillDirection.Horizontal
	lineLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	lineLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lineLayout.Padding = UDim.new(0, 4)
	lineLayout.Parent = line

	local label = Instance.new("TextLabel")
	label.Name = "AuthorLabel"
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 1
	label.FontFace = Theme.FONTS.semibold
	label.TextSize = 15
	label.RichText = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.LayoutOrder = 1
	label.Parent = line
	local shrink = Instance.new("UIFlexItem")
	shrink.FlexMode = Enum.UIFlexMode.Shrink -- long names truncate before the time is pushed out
	shrink.Parent = label

	local badges = Instance.new("Frame")
	badges.Name = "Badges"
	badges.Size = UDim2.fromScale(0, 1)
	badges.AutomaticSize = Enum.AutomaticSize.X
	badges.BackgroundTransparency = 1
	badges.LayoutOrder = 2
	badges.Parent = line
	local badgesLayout = Instance.new("UIListLayout")
	badgesLayout.FillDirection = Enum.FillDirection.Horizontal
	badgesLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	badgesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	badgesLayout.Padding = UDim.new(0, 3)
	badgesLayout.Parent = badges

	local time = Instance.new("TextLabel")
	time.Name = "TimeLabel"
	time.Size = UDim2.fromScale(0, 1)
	time.AutomaticSize = Enum.AutomaticSize.X
	time.BackgroundTransparency = 1
	time.FontFace = Theme.FONTS.body
	time.TextSize = 11
	time.TextYAlignment = Enum.TextYAlignment.Center
	time.LayoutOrder = 4
	time.Parent = line

	-- The plugin's own messages get a verified BOT tag (a check, then BOT)
	-- after the name, like a verified Discord bot
	if sender == SYSTEM_SENDER then
		Author.addBotTag(line, true)
	end
	local timePadding = Instance.new("UIPadding")
	timePadding.PaddingLeft = UDim.new(0, 2)
	timePadding.Parent = time

	-- Hangs to the left of the header, into the container's indent
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Position = UDim2.fromOffset(-(AVATAR_SIZE + AVATAR_GAP), 1)
	avatar.Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
	avatar.BackgroundColor3 = palette.menuItemHover
	avatar.BorderSizePixel = 0
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Parent = header
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = avatar

	local userId = senderId or 0
	if userId > 0 and sender ~= SYSTEM_SENDER then
		avatar.Image = headshotUrl(userId)
	else
		local badge = Instance.new("TextLabel")
		badge.Name = "Badge"
		badge.Size = UDim2.fromScale(1, 1)
		badge.BackgroundTransparency = 1
		badge.TextSize = if sender == SYSTEM_SENDER then 18 else 16
		if sender == SYSTEM_SENDER then
			Icons.apply(badge, "command")
		else
			badge.FontFace = Theme.FONTS.bold
			badge.Text = string.upper(string.sub(sender, 1, 1))
		end
		badge.Parent = avatar
	end

	Author.render(container, palette)
end

-- Replaces the badge icons in the header; each shows its name on hover
-- (when badge tooltips are on in Settings)
local function renderBadges(frame: Frame, badges: { RichText.Badge }, palette: Palette)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			if Author.tooltip then
				Author.tooltip.hide(child)
			end
			child:Destroy()
		end
	end
	for i, badge in ipairs(badges) do
		local icon = BadgeIcons.create(badge, BADGE_SIZE, palette.timestamp)
		icon.LayoutOrder = i
		icon.Parent = frame
		icon.MouseEnter:Connect(function()
			if Author.tooltip and Preferences.values.badgeTooltips then
				Author.tooltip.show(icon, Author.tooltipText(badge))
			end
		end)
		icon.MouseLeave:Connect(function()
			if Author.tooltip then
				Author.tooltip.hide(icon)
			end
		end)
	end
end

--[=[
	Adds a BOT tag after the name in a header's line: with a check for Team
	Chat itself (verified), plain for bots people made.
]=]
function Author.addBotTag(line: Instance, verified: boolean)
	if line:FindFirstChild("BotTag") then
		return
	end
	local tag = Instance.new("TextLabel")
	tag.Name = "BotTag"
	tag.Size = UDim2.fromOffset(0, 15)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.BorderSizePixel = 0
	tag.FontFace = Theme.FONTS.bold
	tag.TextSize = 10
	tag.RichText = true
	tag.Text = (if verified then Icons.inline("botCheck", true, 10) .. " " else "") .. Language.t("system.tag")
	tag.LayoutOrder = 3
	tag.Parent = line
	local tagCorner = Instance.new("UICorner")
	tagCorner.CornerRadius = UDim.new(0, 4)
	tagCorner.Parent = tag
	local tagPadding = Instance.new("UIPadding")
	tagPadding.PaddingLeft = UDim.new(0, 4)
	tagPadding.PaddingRight = UDim.new(0, 4)
	tagPadding.Parent = tag
	tag.MouseEnter:Connect(function()
		if Author.tooltip then
			Author.tooltip.show(tag, Language.t(if verified then "system.verified" else "bot.userBot"))
		end
	end)
	tag.MouseLeave:Connect(function()
		if Author.tooltip then
			Author.tooltip.hide(tag)
		end
	end)
end

--[=[
	Marks a message as from a bot someone made: a plain BOT tag and, when the
	bot has one, its own avatar picture.
]=]
function Author.markBot(container: Instance, avatarImage: string?, palette: Palette)
	local header = container:FindFirstChild("Author")
	if not header then
		return
	end
	Author.addBotTag(header:FindFirstChild("Line") :: Frame, false)
	local avatar = header:FindFirstChild("Avatar") :: ImageLabel
	if avatarImage and string.match(avatarImage, "^rbxassetid://%d+$") then
		avatar.Image = avatarImage
		local badge = avatar:FindFirstChild("Badge")
		if badge then
			badge:Destroy()
		end
	end
	Author.render(container, palette)
end

--[=[
	Re-renders the header (name color, badges, time format, avatar colors).
]=]
function Author.render(container: Instance, palette: Palette)
	local header = container:FindFirstChild("Author")
	if not header then
		return
	end
	local sender = header:GetAttribute("Sender")
	local timestamp = header:GetAttribute("Timestamp")
	if type(sender) ~= "string" or type(timestamp) ~= "number" then
		return
	end
	local line = header:FindFirstChild("Line") :: Frame
	local label = line:FindFirstChild("AuthorLabel") :: TextLabel
	local senderId = container:GetAttribute("SenderId")
	local badges: { RichText.Badge } = {}
	if sender ~= SYSTEM_SENDER and Author.getBadges and type(senderId) == "number" then
		for _, badge in ipairs(Author.getBadges(senderId)) do
			-- The verified badge always shows; others follow the Badges setting
			if badge.verified or Preferences.values.badges then
				table.insert(badges, badge)
			end
		end
	end
	label.Text = string.format(
		'<font color="%s">%s</font>',
		RichText.toHex(if sender == SYSTEM_SENDER then palette.messageText else UsernameColors.getNameColor(sender)),
		RichText.escape(Author.nameOf(sender, senderId))
	)
	local botTag = line:FindFirstChild("BotTag") :: TextLabel?
	if botTag then
		botTag.BackgroundColor3 = palette.sendButton
		botTag.TextColor3 = palette.sendButtonText
	end
	renderBadges(line:FindFirstChild("Badges") :: Frame, badges, palette)

	local time = line:FindFirstChild("TimeLabel") :: TextLabel
	time.Text = TimeFormat.formatPlain(timestamp)
	time.Visible = time.Text ~= ""
	time.TextColor3 = palette.timestamp

	local avatar = header:FindFirstChild("Avatar") :: ImageLabel
	avatar.BackgroundColor3 = palette.menuItemHover
	styleBadge(avatar, sender, palette)
end

return Author
