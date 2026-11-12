--[[
	Row

	One conversation in the sidebar: avatar (the game's icon or a tile with
	its initials; people's headshots) with an online dot and an unread
	badge, the name and a line under it, and the time of a DM's last
	message. A pill on the left edge marks the open conversation; hovering
	a DM shows an × that closes it.
]]

local Animation = require(script.Parent.Parent.Parent.Common.Animation)
local BadgeIcons = require(script.Parent.Parent.BadgeIcons)
local Icons = require(script.Parent.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local Preferences = require(script.Parent.Parent.Parent.Common.Preferences)
local Shared = require(script.Parent.Shared)
local Theme = require(script.Parent.Parent.Parent.Parent.Config.Theme)
local TimeFormat = require(script.Parent.Parent.Parent.Parent.Util.TimeFormat)

local FONTS = Theme.FONTS
local ROW_HEIGHT = Shared.ROW_HEIGHT
local AVATAR_SIZE = Shared.AVATAR_SIZE
local corner = Shared.corner
local newLabel = Shared.label

local Row = {}

-- "Team Chat Plugin" -> "TC"
local function initials(name: string): string
	local letters = ""
	for word in string.gmatch(name, "%w+") do
		letters ..= string.upper(string.sub(word, 1, 1))
		if #letters == 2 then
			break
		end
	end
	return if letters ~= "" then letters else "?"
end

-- When a DM's last message was sent: the time today (in the clock format
-- from Settings), else the day ("02/11"), with the year when older
local function shortTime(timestamp: number?): string
	if not timestamp or timestamp <= 0 then
		return ""
	end
	local now = os.date("*t")
	local date = os.date("*t", timestamp)
	if date.year == now.year and date.yday == now.yday then
		if TimeFormat.getClockFormat() == "12h" then
			local hour = date.hour % 12
			return string.format(
				"%d:%02d %s",
				if hour == 0 then 12 else hour,
				date.min,
				if date.hour >= 12 then "PM" else "AM"
			)
		end
		return string.format("%02d:%02d", date.hour, date.min)
	end
	return os.date(if date.year == now.year then "%d/%m" else "%d/%m/%y", timestamp)
end

--[=[
	Colors a row for its state: open, hovered, unread.
]=]
function Row.paint(view: Shared.View, row: TextButton)
	local colors = view.colors
	local id = row:GetAttribute("ConversationId")
	local selected = id == view.list.activeId
	if not row.Parent then
		return -- destroyed (list rebuilt or plugin stopped)
	end
	local unread = (row:GetAttribute("Unread") or 0) > 0
	local hovered = row == view.hoveredRow

	row.BackgroundColor3 = colors.menuItemHover
	Animation.tween(row, "quick", { BackgroundTransparency = if selected then 0 elseif hovered then 0.5 else 1 })

	local pill = row:FindFirstChild("Pill") :: Frame
	pill.BackgroundColor3 = colors.messageText
	local pillHeight = if selected then 32 elseif hovered then 18 elseif unread then 8 else 0
	pill.Size = UDim2.fromOffset(4, pillHeight)
	pill.Visible = pillHeight > 0

	local name = row:FindFirstChild("NameLabel") :: TextLabel
	name.TextColor3 = if selected or unread or hovered then colors.messageText else colors.menuItemText
	name.FontFace = if unread then FONTS.bold else FONTS.semibold

	local close = row:FindFirstChild("CloseButton") :: TextButton?
	if close then
		close.Visible = hovered
		close.BackgroundColor3 = colors.menuBack
		close.TextColor3 = colors.timestamp
	end
	-- The time makes way for the close button on hover
	local time = row:FindFirstChild("TimeLabel") :: TextLabel
	time.Visible = view.list.expanded and time.Text ~= "" and not (hovered and close ~= nil)
	time.TextColor3 = if unread then colors.messageText else colors.timestamp
end

--[=[
	Shows or hides a row's text for the rail or the expanded list.
]=]
function Row.layout(view: Shared.View, row: TextButton)
	local expanded = view.list.expanded
	row.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
	row:FindFirstChild("NameLabel").Visible = expanded
	row:FindFirstChild("SubLabel").Visible = expanded
	local time = row:FindFirstChild("TimeLabel") :: TextLabel
	time.Visible = expanded and time.Text ~= ""
	local close = row:FindFirstChild("CloseButton") :: TextButton?
	if close then
		-- Right side of the row when expanded; the avatar's corner on the rail
		close.AnchorPoint = if expanded then Vector2.new(1, 0.5) else Vector2.zero
		close.Position = if expanded then UDim2.new(1, -8, 0.5, 0) else UDim2.fromOffset(2, 2)
	end
end

--[=[
	Builds an empty row for an entry (filled by Row.fill), inside a holder
	that keeps the pill outside the row's rounded background.
]=]
function Row.create(view: Shared.View, entry): TextButton
	local colors = view.colors
	local row = Instance.new("TextButton")
	row.Name = "Conversation"
	row.Text = ""
	row.AutoButtonColor = false
	row.BorderSizePixel = 0
	row.BackgroundTransparency = 1
	row:SetAttribute("ConversationId", entry.id)
	corner(row, UDim.new(0, 8))

	local holder = Instance.new("Frame")
	holder.Name = "RowHolder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.Position = UDim2.fromOffset(6, 0)
	row.Parent = holder

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0, 0.5)
	pill.Position = UDim2.new(0, -6, 0.5, 0) -- flush with the sidebar's left edge
	pill.BorderSizePixel = 0
	pill.Size = UDim2.fromOffset(4, 0)
	pill.Parent = row
	corner(pill, UDim.new(0, 2))

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 6, 0.5, 0)
	avatar.Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
	avatar.BackgroundColor3 = colors.menuItemHover
	avatar.BorderSizePixel = 0
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Parent = row
	-- The pinned game is a rounded square (like Roblox game tiles); people are round
	corner(avatar, if entry.kind == "place" then UDim.new(0, 8) else UDim.new(1, 0))

	local fallback = newLabel("Fallback", avatar, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		TextColor3 = colors.timestamp,
		TextSize = 20,
	})
	Icons.apply(fallback, if entry.kind == "place" then "gameFallback" else "directMessages")

	local status = Instance.new("Frame")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(1, 1)
	status.Position = UDim2.new(1, 1, 1, 1)
	status.Size = UDim2.fromOffset(12, 12)
	status.BackgroundColor3 = colors.success
	status.BorderSizePixel = 0
	status.ZIndex = 2
	status.Visible = false
	status.Parent = avatar
	corner(status, UDim.new(1, 0))
	local statusRing = Instance.new("UIStroke")
	statusRing.Name = "Ring"
	statusRing.Thickness = 3
	statusRing.Color = colors.inputFrame
	statusRing.Parent = status

	-- Unread count: a red circle (a pill past 9) cut out of the avatar by a
	-- ring in the sidebar's colour, like Discord
	local badge = newLabel("Badge", avatar, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 5, 0, -4),
		Size = UDim2.fromOffset(18, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = colors.danger,
		TextColor3 = Color3.new(1, 1, 1),
		FontFace = FONTS.bold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 3,
		Visible = false,
	})
	corner(badge, UDim.new(1, 0))
	local badgePadding = Instance.new("UIPadding")
	badgePadding.PaddingLeft = UDim.new(0, 5)
	badgePadding.PaddingRight = UDim.new(0, 5)
	badgePadding.Parent = badge
	local badgeRing = Instance.new("UIStroke")
	badgeRing.Name = "Ring"
	badgeRing.Thickness = 3
	badgeRing.Color = colors.inputFrame
	-- Round the badge, not the digits (on a label a stroke outlines the text)
	badgeRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeRing.Parent = badge

	newLabel("NameLabel", row, {
		Position = UDim2.fromOffset(AVATAR_SIZE + 16, 7),
		-- DMs leave room on the right for the time of the last message
		Size = UDim2.new(1, -(AVATAR_SIZE + 22 + (if entry.kind == "dm" then 50 else 0)), 0, 18),
		FontFace = FONTS.semibold,
		TextSize = 14,
		Visible = false,
	})
	newLabel("TimeLabel", row, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 9),
		Size = UDim2.fromOffset(48, 14),
		FontFace = FONTS.body,
		TextSize = 11,
		TextColor3 = colors.timestamp,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
	})
	newLabel("SubLabel", row, {
		Position = UDim2.fromOffset(AVATAR_SIZE + 16, 25),
		Size = UDim2.new(1, -(AVATAR_SIZE + 22), 0, 15),
		FontFace = FONTS.body,
		TextSize = 12,
		TextColor3 = colors.timestamp,
		Visible = false,
	})

	if entry.kind == "dm" then
		local close = Instance.new("TextButton")
		close.Name = "CloseButton"
		close.Size = UDim2.fromOffset(18, 18)
		close.AutoButtonColor = false
		close.BorderSizePixel = 0
		close.TextSize = 11
		close.ZIndex = 4
		close.Visible = false
		Icons.apply(close, "close")
		close.Parent = row
		corner(close, UDim.new(1, 0))
		close.MouseEnter:Connect(function()
			view.hoveredRow = row
			Row.paint(view, row)
			close.TextColor3 = view.colors.danger
		end)
		close.MouseButton1Click:Connect(function()
			view.tooltip.hide()
			view.hoveredRow = nil
			view.onClose(row:GetAttribute("ConversationId"))
		end)
	end

	row.MouseEnter:Connect(function()
		view.hoveredRow = row
		Row.paint(view, row)
		view.tooltip.show(row, row:GetAttribute("DisplayName") or "")
	end)
	row.MouseLeave:Connect(function()
		if view.hoveredRow == row then
			view.hoveredRow = nil
			view.tooltip.hide()
		end
		Row.paint(view, row)
	end)
	row.MouseButton1Click:Connect(function()
		view.tooltip.hide()
		view.onSelect(row:GetAttribute("ConversationId"))
	end)

	Row.layout(view, row)
	return row
end

--[=[
	Shows an entry (from Conversations.list) in its row.
]=]
function Row.fill(view: Shared.View, row: TextButton, entry)
	local colors = view.colors
	local unreadBefore = row:GetAttribute("Unread") or 0
	row:SetAttribute("Unread", entry.unread or 0)
	-- DMs: display name or username (Settings) and the verified badge, from
	-- the profile provider ChatWindow sets (getProfile)
	local getProfile = view.list.getProfile
	local profile = if entry.kind == "dm" and entry.userId and getProfile then getProfile(entry.userId) else nil
	local shownName = if entry.kind == "dm"
		then Preferences.nameFor(entry.name, profile and profile.displayName)
		else entry.name
	local richName = Icons.escape(shownName) .. BadgeIcons.verifiedSuffix(profile ~= nil and profile.verified, 13)
	row:SetAttribute("DisplayName", richName)

	local avatar = row:FindFirstChild("Avatar") :: ImageLabel
	local image = if entry.kind == "place"
		then entry.icon
		else "rbxthumb://type=AvatarHeadShot&id=" .. tostring(entry.userId) .. "&w=150&h=150"
	avatar.Image = image or ""
	local fallback = avatar:FindFirstChild("Fallback") :: TextLabel
	fallback.Visible = image == nil
	if entry.kind == "place" and image == nil then
		-- No game icon set: a tile with the game's initials
		avatar:SetAttribute("Initials", true)
		avatar.BackgroundColor3 = colors.sendButton
		fallback.RichText = false
		fallback.FontFace = FONTS.display
		fallback.TextSize = 16
		fallback.Text = initials(entry.name)
		fallback.TextColor3 = colors.sendButtonText
	end

	local status = avatar:FindFirstChild("Status") :: Frame
	status.Visible = entry.kind == "dm" and entry.online == true

	local badge = avatar:FindFirstChild("Badge") :: TextLabel
	badge.Visible = (entry.unread or 0) > 0
	badge.Text = if (entry.unread or 0) > 99 then "99+" else tostring(entry.unread or 0)
	if (entry.unread or 0) > unreadBefore then
		Animation.popIn(badge, 0.5, "pop")
	end

	local name = row:FindFirstChild("NameLabel") :: TextLabel
	name.RichText = true
	name.Text = richName
	local time = row:FindFirstChild("TimeLabel") :: TextLabel
	time.Text = if entry.kind == "dm" then shortTime(entry.lastTimestamp) else ""
	-- What search matches: the display name and the username
	row:SetAttribute(
		"SearchText",
		string.lower(shownName .. " " .. (entry.name or "") .. " " .. ((profile and profile.displayName) or ""))
	)
	local sub = row:FindFirstChild("SubLabel") :: TextLabel
	if entry.kind == "place" then
		sub.Text = Language.t("sidebar.teamChatOnline", { count = entry.onlineCount or 0 })
	else
		sub.Text = entry.preview
			or (
				(if entry.isFriend then Language.t("sidebar.friend") .. " \u{00B7} " else "")
				.. Language.t(if entry.online then "sidebar.online" else "sidebar.offline")
			)
	end
	Row.paint(view, row)
end

--[=[
	Re-themes a row.
]=]
function Row.recolor(view: Shared.View, row: TextButton)
	local colors = view.colors
	local avatar = row:FindFirstChild("Avatar") :: any
	local usesInitials = avatar:GetAttribute("Initials") == true
	avatar.BackgroundColor3 = if usesInitials then colors.sendButton else colors.menuItemHover
	avatar.Fallback.TextColor3 = if usesInitials then colors.sendButtonText else colors.timestamp
	avatar.Status.BackgroundColor3 = colors.success
	avatar.Status.Ring.Color = colors.inputFrame
	avatar.Badge.BackgroundColor3 = colors.danger
	avatar.Badge.Ring.Color = colors.inputFrame;
	(row :: any).SubLabel.TextColor3 = colors.timestamp
	Row.paint(view, row)
end

return Row
