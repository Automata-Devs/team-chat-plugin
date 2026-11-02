--!
-- ConversationList
-- Discord-style sidebar on the left of the chat: the place's team chat is
-- pinned at the top (game icon), followed by a direct message for each
-- collaborator (avatar, online dot, unread badge). A pill on the left edge
-- marks the open conversation, like Discord's server list.
--
-- Collapsed it's an icon rail with a name tooltip on hover; expanded it also
-- shows names and the latest message. The footer at the bottom holds the
-- expand/collapse toggle and any buttons added with addFooterButton (each
-- with a tooltip).
-- The + at the top of the DMs starts a new message, and hovering a DM shows
-- an × that closes it. A game without its own icon gets a tile with its
-- initials.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local Animation = require(script.Parent.Parent.Animation)
local BadgeIcons = require(script.Parent.BadgeIcons)
local Preferences = require(script.Parent.Parent.Preferences)
local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)

local FONTS = Theme.FONTS

local ConversationList = {}

ConversationList.COLLAPSED_WIDTH = 64
ConversationList.EXPANDED_WIDTH = 220
-- Added to every sidebar ZIndex while it lies over the chat (setOverlay): the
-- widget uses Global ZIndexBehavior, so the sidebar must out-rank the chat's
-- content (up to 15) but stay under dialogs (20+). Its own ZIndexes go to 4.
ConversationList.OVERLAY_Z_OFFSET = 15

local ROW_HEIGHT = 48
local AVATAR_SIZE = 40
local PINNED_TOP = 8
local LIST_TOP = PINNED_TOP + ROW_HEIGHT + 22
local FOOTER_BUTTON_HEIGHT = 28
local FOOTER_GAP = 4

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

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function newLabel(name: string, parent: Instance, props): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	for key, value in pairs(props) do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

--!
-- Creates the sidebar.
-- @param themeColors table
-- @param parent Instance - where the sidebar frame goes (the widget)
-- @param onSelect (id: string) -> () - called when a conversation is clicked
-- @param onToggle (expanded: boolean) -> () - called when the toggle is clicked
-- @param onNewMessage () -> () - called when the + (new message) is clicked
-- @param onClose (id: string) -> () - called when a DM's × is clicked
--!
function ConversationList.create(
	themeColors,
	parent: Instance,
	onSelect: (string) -> (),
	onToggle: (boolean) -> (),
	onNewMessage: () -> (),
	onClose: (string) -> ()
)
	local self = { expanded = false, rows = {}, activeId = nil, entries = {} }
	local colors = themeColors

	local frame = Instance.new("Frame")
	frame.Name = "Sidebar"
	frame.Size = UDim2.new(0, ConversationList.COLLAPSED_WIDTH, 1, 0)
	frame.BackgroundColor3 = colors.inputFrame
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = parent
	self.frame = frame

	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(1, 0)
	edge.Position = UDim2.fromScale(1, 0)
	edge.Size = UDim2.new(0, 1, 1, 0)
	edge.BackgroundColor3 = colors.divider
	edge.BorderSizePixel = 0
	edge.ZIndex = 4 -- the widget uses Global ZIndexBehavior: above every row
	edge.Parent = frame

	-- Pinned team chat goes here (row created on the first update)
	local pinnedHolder = Instance.new("Frame")
	pinnedHolder.Name = "Pinned"
	pinnedHolder.Position = UDim2.fromOffset(0, PINNED_TOP)
	pinnedHolder.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	pinnedHolder.BackgroundTransparency = 1
	pinnedHolder.Parent = frame

	-- Short divider (collapsed) / section title (expanded)
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.AnchorPoint = Vector2.new(0.5, 0)
	separator.Position = UDim2.new(0.5, 0, 0, PINNED_TOP + ROW_HEIGHT + 9)
	separator.Size = UDim2.fromOffset(32, 2)
	separator.BackgroundColor3 = colors.divider
	separator.BorderSizePixel = 0
	separator.Parent = frame
	corner(separator, UDim.new(1, 0))

	local sectionTitle = newLabel("SectionTitle", frame, {
		Position = UDim2.fromOffset(14, PINNED_TOP + ROW_HEIGHT + 4),
		Size = UDim2.new(1, -28, 0, 14),
		FontFace = FONTS.bold,
		TextSize = 10,
		TextColor3 = colors.timestamp,
		Visible = false,
	})
	Language.bind(sectionTitle, "Text", "sidebar.directMessages", nil, string.upper)

	local list = Instance.new("ScrollingFrame")
	list.Name = "DirectMessages"
	list.Position = UDim2.fromOffset(0, LIST_TOP)
	-- (height set by layoutFooter)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = frame
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list

	-- New message: a round + while collapsed, a "New message" row when expanded
	local newMessage = Instance.new("TextButton")
	newMessage.Name = "NewMessage"
	newMessage.Text = ""
	newMessage.AutoButtonColor = false
	newMessage.BorderSizePixel = 0
	newMessage.BackgroundColor3 = colors.menuItemHover
	newMessage.BackgroundTransparency = 1
	newMessage.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
	newMessage.LayoutOrder = 0
	corner(newMessage, UDim.new(0, 8))
	local newMessageHolder = Instance.new("Frame")
	newMessageHolder.Name = "NewMessageHolder"
	newMessageHolder.BackgroundTransparency = 1
	newMessageHolder.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	newMessageHolder.LayoutOrder = 0
	newMessageHolder.Parent = list
	newMessage.Position = UDim2.fromOffset(6, 0)
	newMessage.Parent = newMessageHolder

	local newMessageCircle = newLabel("Circle", newMessage, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE),
		BackgroundTransparency = 0,
		BackgroundColor3 = colors.menuItemHover,
		TextColor3 = colors.sendButton,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	Icons.apply(newMessageCircle, "newMessage")
	corner(newMessageCircle, UDim.new(1, 0))
	local newMessageLabel = newLabel("NameLabel", newMessage, {
		Position = UDim2.fromOffset(AVATAR_SIZE + 16, 0),
		Size = UDim2.new(1, -(AVATAR_SIZE + 22), 1, 0),
		FontFace = FONTS.semibold,
		TextSize = 14,
		TextColor3 = colors.menuItemText,
		Visible = false,
	})
	Language.bind(newMessageLabel, "Text", "sidebar.newMessage")

	local emptyHint = newLabel("EmptyHint", list, {
		Size = UDim2.new(1, -24, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		FontFace = FONTS.body,
		TextSize = 12,
		TextColor3 = colors.timestamp,
		LayoutOrder = 100000,
		Visible = false,
	})
	Language.bind(emptyHint, "Text", "sidebar.emptyHint")
	local hintPadding = Instance.new("UIPadding")
	hintPadding.PaddingLeft = UDim.new(0, 14)
	hintPadding.Parent = emptyHint

	-- Footer: What's New, Settings and the expand/collapse toggle. Stacked on
	-- the rail, in a row when expanded (see layoutFooter).
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, -8)
	footer.BackgroundTransparency = 1
	footer.Parent = frame
	local footerLayout = Instance.new("UIListLayout")
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	footerLayout.Padding = UDim.new(0, FOOTER_GAP)
	footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	footerLayout.Parent = footer
	local footerPadding = Instance.new("UIPadding")
	footerPadding.Parent = footer

	local footerDivider = Instance.new("Frame")
	footerDivider.Name = "FooterDivider"
	footerDivider.AnchorPoint = Vector2.new(0.5, 1)
	footerDivider.BackgroundColor3 = colors.divider
	footerDivider.BorderSizePixel = 0
	footerDivider.Parent = frame
	corner(footerDivider, UDim.new(1, 0))

	-- Tooltip: next to the rail (names while collapsed, footer buttons), or
	-- above a footer button when expanded
	local tooltip = newLabel("SidebarTooltip", parent, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundTransparency = 0,
		BackgroundColor3 = colors.menuBack,
		TextColor3 = colors.messageText,
		FontFace = FONTS.semibold,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.None,
		RichText = true, -- names can carry the verified badge
		Visible = false,
		ZIndex = 60,
	})
	corner(tooltip, UDim.new(0, 6))
	local tooltipPadding = Instance.new("UIPadding")
	tooltipPadding.PaddingLeft = UDim.new(0, 8)
	tooltipPadding.PaddingRight = UDim.new(0, 8)
	tooltipPadding.Parent = tooltip
	local tooltipStroke = Instance.new("UIStroke")
	tooltipStroke.Color = colors.menuBorder
	tooltipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tooltipStroke.Parent = tooltip

	local hoveredRow: TextButton? = nil

	-- Tooltips appear after hovering for Constants.TOOLTIP_DELAY; hideTooltip
	-- (or another show) before then cancels the pending one
	local tooltipToken = 0
	local function hideTooltip()
		tooltipToken += 1
		tooltip.Visible = false
	end
	local placeTooltip
	local function showTooltip(target: GuiObject, text: string, above: boolean?)
		if self.expanded and not above then
			return
		end -- rows show their names when expanded
		tooltipToken += 1
		local token = tooltipToken
		task.delay(Constants.TOOLTIP_DELAY, function()
			if tooltipToken == token and target.Parent then
				placeTooltip(target, text, above)
			end
		end)
	end
	function placeTooltip(target: GuiObject, text: string, above: boolean?)
		local origin = (parent :: any).AbsolutePosition
		tooltip.Text = text
		if above then
			tooltip.AnchorPoint = Vector2.new(0, 1)
			tooltip.Position =
				UDim2.fromOffset(target.AbsolutePosition.X - origin.X, target.AbsolutePosition.Y - origin.Y - 6)
		else
			tooltip.AnchorPoint = Vector2.new(0, 0.5)
			tooltip.Position = UDim2.fromOffset(
				frame.AbsolutePosition.X - origin.X + frame.AbsoluteSize.X + 4,
				target.AbsolutePosition.Y - origin.Y + target.AbsoluteSize.Y / 2
			)
		end
		tooltip.Visible = true
	end

	local footerButtons: { TextButton } = {}
	local toggle: TextButton? = nil

	local function layoutFooter()
		local expanded = self.expanded
		local count = #footerButtons
		footerLayout.FillDirection = if expanded then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		footerLayout.HorizontalAlignment = if expanded
			then Enum.HorizontalAlignment.Left
			else Enum.HorizontalAlignment.Center
		footerPadding.PaddingLeft = UDim.new(0, if expanded then 12 else 0)
		local footerHeight = if expanded
			then FOOTER_BUTTON_HEIGHT
			else count * FOOTER_BUTTON_HEIGHT + math.max(0, count - 1) * FOOTER_GAP
		footer.Size = UDim2.new(1, 0, 0, footerHeight)
		for _, button in ipairs(footerButtons) do
			button.Size = UDim2.fromOffset(if expanded then 32 else AVATAR_SIZE, FOOTER_BUTTON_HEIGHT)
		end
		footerDivider.Position = UDim2.new(0.5, 0, 1, -(footerHeight + 14))
		footerDivider.Size = if expanded then UDim2.new(1, -24, 0, 1) else UDim2.fromOffset(32, 2)
		list.Size = UDim2.new(1, 0, 1, -(LIST_TOP + footerHeight + 20))
		if toggle then
			toggle:SetAttribute("Tooltip", Language.t(if expanded then "sidebar.collapse" else "sidebar.expand"))
		end
	end

	--!
	-- Adds an icon button to the footer with a tooltip. Lower order = higher
	-- up (or further left); the toggle is last.
	--!
	function self.addFooterButton(
		name: string,
		iconKey: string,
		tooltipText: string,
		onClick: (() -> ())?,
		order: number?
	): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.BackgroundColor3 = colors.menuItemHover
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.TextColor3 = colors.timestamp
		button.TextSize = 18
		button.LayoutOrder = order or (#footerButtons + 1)
		button:SetAttribute("Tooltip", tooltipText)
		Icons.apply(button, iconKey)
		button.Parent = footer
		corner(button, UDim.new(0, 6))
		button.MouseEnter:Connect(function()
			Animation.tween(button, "quick", { BackgroundTransparency = 0 })
			button.TextColor3 = colors.messageText
			showTooltip(button, Icons.escape(button:GetAttribute("Tooltip") or ""), self.expanded)
		end)
		button.MouseLeave:Connect(function()
			Animation.tween(button, "quick", { BackgroundTransparency = 1 })
			button.TextColor3 = colors.timestamp
			hideTooltip()
		end)
		button.MouseButton1Click:Connect(function()
			hideTooltip()
			if onClick then
				onClick()
			end
		end)
		table.insert(footerButtons, button)
		layoutFooter()
		return button
	end

	toggle = self.addFooterButton("Toggle", "sidebar", Language.t("sidebar.expand"), function()
		onToggle(not self.expanded)
	end, 100)
	Language.changed:Connect(function()
		if toggle then
			toggle:SetAttribute("Tooltip", Language.t(if self.expanded then "sidebar.collapse" else "sidebar.expand"))
		end
	end)

	newMessage.MouseEnter:Connect(function()
		newMessage.BackgroundTransparency = if self.expanded then 0.5 else 1
		newMessageCircle.BackgroundColor3 = colors.sendButton
		newMessageCircle.TextColor3 = colors.sendButtonText
		newMessageLabel.TextColor3 = colors.messageText
		showTooltip(newMessage :: any, Language.t("sidebar.newMessage"))
	end)
	newMessage.MouseLeave:Connect(function()
		newMessage.BackgroundTransparency = 1
		newMessageCircle.BackgroundColor3 = colors.menuItemHover
		newMessageCircle.TextColor3 = colors.sendButton
		newMessageLabel.TextColor3 = colors.menuItemText
		hideTooltip()
	end)
	newMessage.MouseButton1Click:Connect(function()
		hideTooltip()
		onNewMessage()
	end)

	local function paintRow(row: TextButton)
		local id = row:GetAttribute("ConversationId")
		local selected = id == self.activeId
		if not row.Parent then
			return -- destroyed (list rebuilt or plugin stopped)
		end
		local unread = (row:GetAttribute("Unread") or 0) > 0
		local hovered = row == hoveredRow

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
	end

	local function layoutRow(row: TextButton)
		local expanded = self.expanded
		row.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
		row:FindFirstChild("NameLabel").Visible = expanded
		row:FindFirstChild("SubLabel").Visible = expanded
		local close = row:FindFirstChild("CloseButton") :: TextButton?
		if close then
			-- Right side of the row when expanded; the avatar's corner on the rail
			close.AnchorPoint = if expanded then Vector2.new(1, 0.5) else Vector2.zero
			close.Position = if expanded then UDim2.new(1, -8, 0.5, 0) else UDim2.fromOffset(2, 2)
		end
	end

	local function createRow(entry): TextButton
		local row = Instance.new("TextButton")
		row.Name = "Conversation"
		row.Text = ""
		row.AutoButtonColor = false
		row.BorderSizePixel = 0
		row.BackgroundTransparency = 1
		row:SetAttribute("ConversationId", entry.id)
		corner(row, UDim.new(0, 8))

		local holder = Instance.new("Frame") -- keeps the pill outside the row's rounded background
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
		-- The pinned game is a rounded square (like Roblox game tiles); people are round.
		corner(avatar, if entry.kind == "place" then UDim.new(0, 12) else UDim.new(1, 0))

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
			Size = UDim2.new(1, -(AVATAR_SIZE + 22), 0, 18),
			FontFace = FONTS.semibold,
			TextSize = 14,
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
				hoveredRow = row
				paintRow(row)
				close.TextColor3 = colors.danger
			end)
			close.MouseButton1Click:Connect(function()
				hideTooltip()
				hoveredRow = nil
				onClose(row:GetAttribute("ConversationId"))
			end)
		end

		row.MouseEnter:Connect(function()
			hoveredRow = row
			paintRow(row)
			showTooltip(row, row:GetAttribute("DisplayName") or "")
		end)
		row.MouseLeave:Connect(function()
			if hoveredRow == row then
				hoveredRow = nil
				hideTooltip()
			end
			paintRow(row)
		end)
		row.MouseButton1Click:Connect(function()
			hideTooltip()
			onSelect(row:GetAttribute("ConversationId"))
		end)

		layoutRow(row)
		return row
	end

	local function fillRow(row: TextButton, entry)
		local unreadBefore = row:GetAttribute("Unread") or 0
		row:SetAttribute("Unread", entry.unread or 0)
		-- DMs: display name or username (Settings) and the verified badge,
		-- from the profile provider ChatWindow sets (self.getProfile)
		local profile = if entry.kind == "dm"
				and entry.userId
				and self.getProfile
			then self.getProfile(entry.userId)
			else nil
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
			-- A new unread message: the badge pops
			Animation.popIn(badge, 0.5, "pop")
		end

		local name = row:FindFirstChild("NameLabel") :: TextLabel
		name.RichText = true
		name.Text = richName
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
		paintRow(row)
	end

	--!
	-- Shows the given entries (from Conversations.list) with activeId selected.
	--!
	function self.update(entries: { table }, activeId: string)
		self.entries = entries
		self.activeId = activeId
		local seen = {}
		local dmCount = 0
		for index, entry in ipairs(entries) do
			seen[entry.id] = true
			local row = self.rows[entry.id]
			if not row then
				row = createRow(entry)
				self.rows[entry.id] = row
			end
			local holder = row.Parent :: Frame
			if entry.kind == "place" then
				holder.Parent = pinnedHolder
			else
				dmCount += 1
				holder.LayoutOrder = index
				holder.Parent = list
			end
			fillRow(row, entry)
		end
		for id, row in pairs(self.rows) do
			if not seen[id] then
				row.Parent:Destroy()
				self.rows[id] = nil
			end
		end
		emptyHint.Visible = dmCount == 0 and self.expanded
	end

	--!
	-- Marks a conversation as open.
	--!
	function self.setActive(activeId: string)
		self.activeId = activeId
		for _, row in pairs(self.rows) do
			paintRow(row)
		end
	end

	--!
	-- Switches between the icon rail and the full list with names.
	--!
	function self.setExpanded(expanded: boolean)
		self.expanded = expanded
		Animation.tween(frame, "smooth", {
			Size = UDim2.new(
				0,
				if expanded then ConversationList.EXPANDED_WIDTH else ConversationList.COLLAPSED_WIDTH,
				1,
				0
			),
		})
		separator.Visible = not expanded
		sectionTitle.Visible = expanded
		layoutFooter()
		newMessageLabel.Visible = expanded
		hideTooltip()
		for _, row in pairs(self.rows) do
			layoutRow(row)
		end
		local dmCount = 0
		for _, entry in ipairs(self.entries) do
			if entry.kind == "dm" then
				dmCount += 1
			end
		end
		emptyHint.Visible = dmCount == 0 and expanded
	end

	-- Raises (or lowers back) every sidebar element above the chat. Each
	-- element's own ZIndex is kept in its BaseZ attribute, so raising is
	-- idempotent: rows moved around inside the sidebar (which fires
	-- DescendantAdded again) aren't raised twice.
	local overlayOn = false
	local function raise(gui: Instance)
		if gui:IsA("GuiObject") then
			local base = gui:GetAttribute("BaseZ")
			if type(base) ~= "number" then
				base = gui.ZIndex
				gui:SetAttribute("BaseZ", base)
			end
			gui.ZIndex = base + ConversationList.OVERLAY_Z_OFFSET
		end
	end
	local function lower(gui: Instance)
		if gui:IsA("GuiObject") then
			local base = gui:GetAttribute("BaseZ")
			if type(base) == "number" then
				gui.ZIndex = base
				gui:SetAttribute("BaseZ", nil)
			end
		end
	end
	frame.DescendantAdded:Connect(function(descendant)
		if overlayOn then
			raise(descendant)
		end
	end)
	function self.setOverlay(on: boolean)
		if on == overlayOn then
			return
		end
		overlayOn = on
		local apply = if on then raise else lower
		apply(frame)
		for _, descendant in ipairs(frame:GetDescendants()) do
			apply(descendant)
		end
		frame:SetAttribute("Overlay", on)
	end

	function self.width(): number
		return if self.expanded then ConversationList.EXPANDED_WIDTH else ConversationList.COLLAPSED_WIDTH
	end

	--!
	-- Re-themes the sidebar.
	--!
	function self.recolor(themeColorsNew)
		colors = themeColorsNew
		frame.BackgroundColor3 = colors.inputFrame
		edge.BackgroundColor3 = colors.divider
		separator.BackgroundColor3 = colors.divider
		sectionTitle.TextColor3 = colors.timestamp
		emptyHint.TextColor3 = colors.timestamp
		footerDivider.BackgroundColor3 = colors.divider
		for _, button in ipairs(footerButtons) do
			button.BackgroundColor3 = colors.menuItemHover
			button.TextColor3 = colors.timestamp
		end
		tooltip.BackgroundColor3 = colors.menuBack
		tooltip.TextColor3 = colors.messageText
		tooltipStroke.Color = colors.menuBorder
		newMessageCircle.BackgroundColor3 = colors.menuItemHover
		newMessageCircle.TextColor3 = colors.sendButton
		newMessageLabel.TextColor3 = colors.menuItemText
		for _, row in pairs(self.rows) do
			local avatar = row:FindFirstChild("Avatar") :: ImageLabel
			local usesInitials = avatar:GetAttribute("Initials") == true
			avatar.BackgroundColor3 = if usesInitials then colors.sendButton else colors.menuItemHover
			avatar.Fallback.TextColor3 = if usesInitials then colors.sendButtonText else colors.timestamp
			avatar.Status.BackgroundColor3 = colors.success
			avatar.Status.Ring.Color = colors.inputFrame
			avatar.Badge.BackgroundColor3 = colors.danger
			avatar.Badge.Ring.Color = colors.inputFrame
			row.SubLabel.TextColor3 = colors.timestamp
			paintRow(row)
		end
	end

	return self
end

return ConversationList
