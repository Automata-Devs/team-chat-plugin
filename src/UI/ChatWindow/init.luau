--!
-- ChatUI
-- Builds and manages the dock widget GUI for the TeamChat plugin.
-- Adaptive theme: matches Roblox Studio's light/dark mode automatically.
-- Supports image attachments via local file picker (StudioService:PromptImportFile).
-- Images are uploaded as permanent Roblox assets so they sync across Team Create.
-- Supports drag-and-drop of attachments via PluginGui.PluginDrag* events and Plugin:StartDrag().
--!

local StudioService = game:GetService("StudioService")
local AssetService = game:GetService("AssetService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UsernameColors = require(script.Parent.Parent.Util.UsernameColors)
local Theme = require(script.Parent.Parent.Config.Theme)
local MentionPills = require(script.Parent.MentionPills)
local ComposerText = require(script.Parent.ComposerText)
local SpellingMarks = require(script.Parent.SpellingMarks)
local SpellCheck = require(script.Parent.Parent.Util.SpellCheck)
local MessageText = require(script.Parent.MessageText)
local ObjectTags = require(script.Parent.Parent.Services.ObjectTags)
local Markdown = require(script.Parent.Parent.Util.Markdown)
local CommandEmbed = require(script.Parent.Embeds.Providers.CommandEmbed)
local Components = require(script.Parent.Embeds.Components)
local Bots = require(script.Parent.Parent.Services.Bots)
local UsageTracker = require(script.Parent.Parent.Services.Usage)
local Browser = require(script.Parent.Parent.Core.Browser)
local ContextMenu = require(script.ContextMenu)
local EmojiPicker = require(script.EmojiPicker)
local Pointer = require(script.Pointer)
local TypingBar = require(script.TypingBar)
local Header = require(script.Header)
local PinsPanel = require(script.PinsPanel)
local TeamCreateNotice = require(script.TeamCreateNotice)
local Messages = require(script.Parent.Messages)
local EmbedManager = require(script.Parent.Embeds.EmbedManager)
local Autocomplete = require(script.Parent.Components.Autocomplete)
local PluginConfig = require(script.Parent.Parent.Config.Constants)
local Icons = require(script.Parent.Parent.Config.Icons)
local GifPlayer = require(script.Parent.Components.GifPlayer)
local Tooltip = require(script.Parent.Components.Tooltip)
local Toasts = require(script.Parent.Components.Toasts)
local Animation = require(script.Parent.Animation)
local BadgeIcons = require(script.Parent.Components.BadgeIcons)
local Preferences = require(script.Parent.Preferences)
local Language = require(script.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local ConversationList = require(script.Parent.Components.ConversationList)
local EmojiData = require(script.Parent.Parent.Util.EmojiData)
local Mentions = require(script.Parent.Parent.Util.Mentions)
local Settings = require(script.Parent.Parent.Core.Settings)
local AboutDialog = require(script.Parent.Dialogs.AboutDialog)
local AdminDialog = require(script.Parent.Dialogs.AdminDialog)
local DeveloperDialog = require(script.Parent.Dialogs.DeveloperDialog)
local Author = require(script.Parent.Messages.Author)
local BadgesDialog = require(script.Parent.Dialogs.BadgesDialog)
local PurchaseDialog = require(script.Parent.Dialogs.PurchaseDialog)
local ChangelogDialog = require(script.Parent.Dialogs.ChangelogDialog)
local ModalKit = require(script.Parent.Dialogs.ModalKit)
local SettingsDialog = require(script.Parent.Dialogs.SettingsDialog)
local SettingsTabs = require(script.Parent.Dialogs.SettingsTabs)
local CreatePollDialog = require(script.Parent.Dialogs.CreatePollDialog)
local NewMessageDialog = require(script.Parent.Dialogs.NewMessageDialog)
local Logger = require(script.Parent.Parent.Core.Logger)

local log = Logger.scope("Chat")

-- Local aliases for theme and config constants (kept for readability)
local PLUGIN_VERSION = PluginConfig.PLUGIN_VERSION

local THEMES = Theme.PALETTES
local FONT = Theme.FONT
local FONTS = Theme.FONTS
local IMAGE_FILTER = Theme.IMAGE_FILTER
local FILE_EXTENSIONS = Theme.FILE_EXTENSIONS
local INPUT_HEIGHT = Theme.INPUT_HEIGHT
local PREVIEW_HEIGHT = Theme.PREVIEW_HEIGHT
local MENU_WIDTH = Theme.MENU_WIDTH

-- Layout and timing constants used inside ChatUI.create
local ATTACHMENT_MIME_TYPE = "application/x-teamchat-attachment"
local JUMP_SCROLL_TIME = 0.3
local FLASH_HOLD_TIME = 0.6
local FLASH_FADE_TIME = 1.2
local FLASH_START_TRANSPARENCY = 0.75
local SCROLL_BOTTOM_THRESHOLD = 24
local MAX_INPUT_HEIGHT = 240
local REPLY_BAR_HEIGHT = 30
-- When the sidebar is expanded in a narrow panel the chat would be squeezed
-- below this width; the sidebar slides over the chat instead (overlay)
local MIN_CHAT_WIDTH = 360

local ChatUI = {}

local toHex = Theme.toHex

--!
-- Creates the dock widget and returns the UI elements.
-- @param pluginInstance The plugin global
--!
function ChatUI.create(pluginInstance)
	Preferences.load() -- animations and display settings apply from the first frame
	local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Left, true, false, 300, 500, 250, 300)

	local widget = pluginInstance:CreateDockWidgetPluginGui("TeamChatWidget", widgetInfo)
	-- The version (and a Development Mode tag) is in the widget's title
	local titleTag = PluginConfig.PLUGIN_VERSION
	if PluginConfig.DEVELOPMENT_MODE then
		titleTag ..= " \u{00B7} Development Mode"
	end
	local baseTitle = PluginConfig.PLUGIN_TITLE .. (if titleTag ~= "" then " " .. titleTag else "")
	widget.Title = baseTitle

	-- Clean up any old children from previous plugin load
	for _, child in ipairs(widget:GetChildren()) do
		child:Destroy()
	end

	local currentThemeName = Theme.detect()
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
	local conversationSidebar = {}
	do
		local sidebar
		local manualExpanded: boolean? = nil
		-- Dims the chat while the sidebar lies over it; clicking it closes the sidebar
		local scrim = Instance.new("TextButton")
		scrim.Name = "SidebarScrim"
		scrim.Text = ""
		scrim.AutoButtonColor = false
		scrim.BackgroundColor3 = Color3.new(0, 0, 0)
		scrim.BackgroundTransparency = 0.5
		scrim.BorderSizePixel = 0
		scrim.Position = UDim2.fromOffset(ConversationList.EXPANDED_WIDTH, 0)
		scrim.Size = UDim2.new(1, -ConversationList.EXPANDED_WIDTH, 1, 0)
		scrim.ZIndex = ConversationList.OVERLAY_Z_OFFSET -- above the chat, below the raised sidebar
		scrim.Visible = false
		scrim.Parent = widget

		-- The chat fills the rest of the panel. Expanding the sidebar in a
		-- narrow panel would squeeze the chat, so the sidebar slides over it
		-- instead (like a drawer) and the chat keeps its size.
		local function applyWidth()
			local overlay = sidebar.expanded
				and widget.AbsoluteSize.X - ConversationList.EXPANDED_WIDTH < MIN_CHAT_WIDTH
			local width = if overlay then ConversationList.COLLAPSED_WIDTH else sidebar.width()
			Animation.tween(container, "smooth", {
				Position = UDim2.fromOffset(width, 0),
				Size = UDim2.new(1, -width, 1, 0),
			})
			sidebar.setOverlay(overlay)
			if overlay and not scrim.Visible then
				scrim.BackgroundTransparency = 1
				Animation.tween(scrim, "smooth", { BackgroundTransparency = 0.5 })
			end
			scrim.Visible = overlay
			conversationSidebar.overlay = overlay
		end
		local function setExpanded(expanded: boolean)
			sidebar.setExpanded(expanded)
			applyWidth()
		end
		scrim.MouseButton1Click:Connect(function()
			manualExpanded = false
			setExpanded(false)
		end)
		-- Picking a conversation from the overlay closes it
		conversationSidebar.closeOverlay = function()
			if conversationSidebar.overlay then
				manualExpanded = false
				setExpanded(false)
			end
		end
		sidebar = ConversationList.create(themeColors, widget, function(id)
			conversationSidebar.closeOverlay()
			if conversationSidebar.selectCallback then
				conversationSidebar.selectCallback(id)
			end
		end, function(expanded)
			manualExpanded = expanded
			setExpanded(expanded)
		end, function(query)
			if conversationSidebar.newMessageDialog then
				conversationSidebar.newMessageDialog.open(query)
			end
		end, function(id)
			if conversationSidebar.closeCallback then
				conversationSidebar.closeCallback(id)
			end
		end)
		local function autoExpand()
			if manualExpanded ~= nil then
				return
			end
			local wide = widget.AbsoluteSize.X >= 600
			if wide ~= sidebar.expanded then
				setExpanded(wide)
			end
		end
		widget:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			autoExpand()
			applyWidth()
		end)
		applyWidth()
		task.defer(autoExpand)
		conversationSidebar.list = sidebar
	end

	-- Tooltip for the badges next to names (shown above the hovered badge)
	local badgeTooltip = Tooltip.create(widget, themeColors)
	Author.tooltip = badgeTooltip

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

	-- Header bar: the open conversation's title and the pinned messages button
	local pinsPanel
	local header = Header.create({
		container = container,
		getThemeColors = function()
			return themeColors
		end,
		onPins = function()
			pinsPanel.toggle()
		end,
	})

	-- "Only you can see this chat" while the place isn't in Team Create. It
	-- pushes the messages down; relayout is set once the composer exists.
	local relayout = function() end
	local teamCreateNotice = TeamCreateNotice.create({
		container = container,
		top = Header.HEIGHT,
		getThemeColors = function()
			return themeColors
		end,
		onResize = function()
			relayout()
		end,
	})
	-- Space above the messages: the header and the notice
	local function topSpace(): number
		return Header.HEIGHT + teamCreateNotice.height()
	end

	-- Colors the red "New" line above the first unread message
	local function colorUnreadDivider(unreadDivider: Instance)
		for _, part in ipairs(unreadDivider:GetDescendants()) do
			if part.Name == "Line" then
				(part :: Frame).BackgroundColor3 = themeColors.danger
			elseif part.Name == "Tag" then
				(part :: TextLabel).BackgroundColor3 = themeColors.danger;
				(part :: TextLabel).TextColor3 = Color3.new(1, 1, 1)
			end
		end
	end

	-- One Settings button at the bottom of the sidebar, above its
	-- expand/collapse toggle; it opens the tabbed Settings window (General,
	-- Badges, What's New, About), wired further down
	local sidebarSettingsButton =
		conversationSidebar.list.addFooterButton("SettingsButton", "settings", Language.t("sidebar.settings"))

	-- Scrolling frame for messages (below the header)
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "MessageList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -(INPUT_HEIGHT + topSpace()))
	scrollFrame.Position = UDim2.new(0, 0, 0, topSpace())
	scrollFrame.BackgroundColor3 = themeColors.scrollBack
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = themeColors.scrollBar
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	scrollFrame.Parent = container
	-- A badge tooltip would stay behind while the messages scroll away
	scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		badgeTooltip.hide()
	end)

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
	scrollButtonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- the button, not its arrow
	scrollButtonStroke.Parent = scrollButton

	-- Soft drop shadow so the button stands out over the message list
	local scrollButtonShadow = Instance.new("UIShadow")
	scrollButtonShadow.BlurRadius = UDim.new(0, 8)
	scrollButtonShadow.Color = Color3.fromRGB(0, 0, 0)
	scrollButtonShadow.Transparency = 0.55
	scrollButtonShadow.Parent = scrollButton

	-- Right-click menu on messages (Reply, Copy, Delete) and pointer helpers
	local pointer = Pointer.new(widget)
	local isInside = pointer.isInside
	local mousePosition = pointer.mousePosition
	local contextMenu = ContextMenu.create({
		container = container,
		widget = widget,
		getThemeColors = function()
			return themeColors
		end,
	})
	local hideContextMenu = contextMenu.hide
	local recolorContextMenu = contextMenu.recolor
	local createContextMenuItem = contextMenu.createItem

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
		local fadeInfo =
			TweenInfo.new(FLASH_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, FLASH_HOLD_TIME)
		local tween
		if target:GetAttribute("HoverHighlight") then
			-- Plain messages: tint the hover surface, then fade it out. A message
			-- that mentions you gets its gold look back afterwards.
			local mentionGradient = target:FindFirstChild("MentionGradient") :: UIGradient?
			if mentionGradient then
				mentionGradient.Enabled = false
			end
			target.BackgroundColor3 = themeColors.sendButton
			target.BackgroundTransparency = FLASH_START_TRANSPARENCY
			tween = TweenService:Create(target, fadeInfo, { BackgroundTransparency = 1 })
			tween.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					target.BackgroundColor3 = themeColors.menuItemHover
					if target:GetAttribute("Mentioned") then
						Messages.applyMention(target, themeColors, target:GetAttribute("Content"))
					end
				end
			end)
		else
			-- Poll / announcement cards: light up the card's outline instead
			local stroke = target:FindFirstChildOfClass("UIStroke")
			if not stroke then
				return
			end
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

	local function jumpToMessage(timestamp: number)
		local target
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("GuiObject") and child:GetAttribute("Timestamp") == timestamp then
				target = child
				break
			end
		end
		if not target then
			return
		end -- original was deleted or isn't loaded

		local top = target.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y + scrollFrame.CanvasPosition.Y
		local y = math.clamp(top - (scrollFrame.AbsoluteSize.Y - target.AbsoluteSize.Y) / 2, 0, getMaxScroll())
		TweenService:Create(
			scrollFrame,
			TweenInfo.new(JUMP_SCROLL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CanvasPosition = Vector2.new(0, y) }
		):Play()
		flashMessage(target)
	end
	Messages.setJumpHandler(jumpToMessage)

	-- Pinned messages: the panel under the header's pin button, and which
	-- messages are pinned (for the right-click menu)
	local pinnedTimestamps: { [number]: boolean } = {}
	local pinHandler: ((timestamp: number, pinned: boolean) -> ())? = nil
	pinsPanel = PinsPanel.create({
		container = container,
		top = Header.HEIGHT,
		getThemeColors = function()
			return themeColors
		end,
		onJump = jumpToMessage,
		onUnpin = function(timestamp: number)
			if pinHandler then
				pinHandler(timestamp, false)
			end
		end,
		onVisibility = header.setPinsOpen,
		ignoreClicksOn = { header.pinButton },
	})

	-- Emoji reactions: the picker (from Add Reaction, or the button after a
	-- message's reactions) and what picking or clicking a reaction does
	-- A message is its saved name (MessageId on its row) or, for rows shown
	-- without one, its timestamp
	local reactHandler: ((target: string | number, emoji: string) -> ())? = nil
	local emojiPicker = EmojiPicker.create({
		container = container,
		widget = widget,
		getThemeColors = function()
			return themeColors
		end,
		getMousePosition = function()
			return widget:GetRelativeMousePosition()
		end,
		getScore = function(entry)
			return UsageTracker.getCount("emoji", entry.name)
		end,
	})
	local function pickReaction(target: string | number)
		hideContextMenu()
		emojiPicker.open(function(entry)
			UsageTracker.record("emoji", entry.name)
			if reactHandler then
				reactHandler(target, entry.emoji)
			end
		end)
	end
	contextMenu.handlers.react = function(timestamp: number, messageId: string?)
		pickReaction(messageId or timestamp)
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
		scrollFadeTween = TweenService:Create(
			scrollFrame,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ ScrollBarImageTransparency = 1 }
		)
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
	emptyState.Size = UDim2.new(1, 0, 1, -(INPUT_HEIGHT + topSpace()))
	emptyState.Position = UDim2.new(0, 0, 0, topSpace())
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
	emptyTitleLabel.Text = Language.t("empty.title")
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
	emptySubtitle.Text = Language.t("empty.subtitle")
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

	local menuItemPoll = createContextMenuItem("Create Poll", "createPoll", 1, false, menuFrame, "composer.createPoll")
	menuItemPoll.Name = "MenuItemPoll"

	local menuItemFile =
		createContextMenuItem("Attach File(s)", "attachFile", 2, false, menuFrame, "composer.attachFiles")
	menuItemFile.Name = "MenuItemFile"

	-- Text box for typing messages
	local textBox = Instance.new("TextBox")
	textBox.Name = "InputBox"
	textBox.Size = UDim2.new(1, -98, 0, 33)
	textBox.Position = UDim2.new(0, 49, 0, 8)
	textBox.BackgroundColor3 = themeColors.inputBox
	textBox.TextColor3 = themeColors.textBoxText
	textBox.PlaceholderText = Language.t("composer.placeholder")
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
	-- @mentions get the same rounded tint while you type (a TextBox can't
	-- colour its own text)
	MentionPills.attach(textBox, themeColors)

	-- Markdown styled in the box as you type, like Discord (UI/ComposerText)
	local composerText = ComposerText.attach(textBox, {
		getPalette = function()
			return themeColors
		end,
	})

	-- Spell check: red wavy lines under misspelled words (Settings > Chat)
	local spelling = SpellingMarks.attach(textBox, {
		getPalette = function()
			return themeColors
		end,
		isEnabled = function()
			return Preferences.values.spellCheck
		end,
	})
	-- Words added with "Add to dictionary", and the names of people here
	SpellCheck.addWords(Settings.getJson(PluginConfig.SETTING_KEY_DICTIONARY, {}) or {})
	local function addPlayerNames(player: Player)
		SpellCheck.addWords({ player.Name, player.DisplayName })
	end
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		addPlayerNames(player)
	end
	Lifetime.connect(game:GetService("Players").PlayerAdded, addPlayerNames)
	local function addToDictionary(word: string)
		SpellCheck.addWords({ word })
		local saved = Settings.getJson(PluginConfig.SETTING_KEY_DICTIONARY, {})
		if type(saved) ~= "table" then
			saved = {}
		end
		if not table.find(saved, string.lower(word)) then
			table.insert(saved, string.lower(word))
			Settings.setJson(PluginConfig.SETTING_KEY_DICTIONARY, saved)
		end
		spelling.refresh()
	end

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
	local autocompleteMode = nil -- "command" | "emoji" | "args" | "member" | "object" | "choice" | "spelling"
	local emojiMatchStart = nil -- 1-based index of the ":" currently being typed
	local mentionMatchStart = nil -- 1-based index of the "@" currently being typed
	local tagMatchStart = nil -- 1-based index of the "#" currently being typed
	local choiceMatchStart = nil -- where the bot option value being typed starts

	--!
	-- A "#name" being typed at the end of the text (not a "# " header, not in
	-- the middle of a word): where its "#" is and the name so far.
	--!
	local function typingTag(text: string): (number?, string?)
		local hashPos, partial = string.match(text, "()#([%w_%-]*)$")
		if not hashPos then
			return nil, nil
		end
		local before = if hashPos > 1 then string.sub(text, hashPos - 1, hashPos - 1) else ""
		if before ~= "" and string.match(before, "[%w_#%[]") then
			return nil, nil
		end
		return hashPos, partial
	end

	--!
	-- People to @mention whose username or display name starts with `partial`:
	-- everyone editing the place (online) and your DM contacts, online first,
	-- then @everyone when it matches.
	--!
	local function mentionCandidates(partial: string)
		local query = string.lower(partial)
		local byId = {}
		local function add(userId: number?, username: string?, displayName: string?, online: boolean)
			if type(userId) ~= "number" or userId <= 0 or type(username) ~= "string" or username == "" then
				return
			end
			local known = byId[userId]
			if known then
				known.online = known.online or online
				return
			end
			byId[userId] = { userId = userId, username = username, displayName = displayName, online = online }
		end
		for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
			add(player.UserId, player.Name, player.DisplayName, true)
		end
		for _, entry in ipairs(conversationSidebar.entries or {}) do
			if entry.kind == "dm" then
				local profile = if Author.getProfile then Author.getProfile(entry.userId) else nil
				add(entry.userId, entry.name, profile and profile.displayName, entry.online == true)
			end
		end
		local members = {}
		for _, member in pairs(byId) do
			local username = string.lower(member.username)
			local displayName = string.lower(member.displayName or "")
			if
				query == ""
				or string.sub(username, 1, #query) == query
				or string.sub(displayName, 1, #query) == query
			then
				table.insert(members, member)
			end
		end
		table.sort(members, function(a, b)
			if a.online ~= b.online then
				return a.online
			end
			return string.lower(a.displayName or a.username) < string.lower(b.displayName or b.username)
		end)
		while #members > Autocomplete.MAX_ITEMS - 1 do
			table.remove(members)
		end
		if string.sub(Mentions.EVERYONE, 1, #query) == query then
			table.insert(members, { everyone = true, username = Mentions.EVERYONE })
		end
		return members
	end

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

		-- Spelling: replace the misspelled word, or add it to the dictionary
		if item.type == "spelling" or item.type == "addWord" then
			local word = item.word
			if item.type == "spelling" then
				local text = textBox.Text
				textBox.Text = string.sub(text, 1, word.start - 1)
					.. item.suggestion
					.. string.sub(text, word.finish + 1)
				textBox.CursorPosition = word.start + #item.suggestion
			else
				addToDictionary(word.word)
			end
			hideAutocomplete()
			return
		end

		if item.type == "command" then
			textBox.Text = "/" .. item.name .. " "
		elseif item.type == "emoji" and emojiMatchStart then
			textBox.Text = string.sub(textBox.Text, 1, emojiMatchStart - 1) .. item.emoji .. " "
		elseif item.type == "member" and mentionMatchStart then
			textBox.Text = string.sub(textBox.Text, 1, mentionMatchStart - 1) .. "@" .. item.member.username .. " "
		elseif item.type == "choice" and choiceMatchStart then
			textBox.Text = string.sub(textBox.Text, 1, choiceMatchStart - 1) .. item.choice.name .. " "
		elseif item.type == "object" and tagMatchStart then
			-- Saved as #[full path] (shown as #Name), so it still finds the right one
			textBox.Text = string.sub(textBox.Text, 1, tagMatchStart - 1)
				.. "#["
				.. ObjectTags.pathOf(item.instance)
				.. "] "
		end
		textBox.CursorPosition = #textBox.Text + 1 -- keep typing after the suggestion

		hideAutocomplete()
	end

	--!
	-- Shows autocompleteItems in the dropdown (or hides it when there are none).
	--!
	local function renderAutocompleteItems()
		Autocomplete.setHint(autocompleteFrame, Autocomplete.defaultHint())

		if #autocompleteItems > 0 then
			for i, item in ipairs(autocompleteItems) do
				local btn
				if item.type == "command" then
					btn = Autocomplete.createItem(i, item.cmd, themeColors, function(rank)
						return Language.tOr(
							"rank." .. tostring(rank),
							PluginConfig.RANK_NAMES[rank] or PluginConfig.RANK_NAMES[0]
						)
					end)
				elseif item.type == "member" then
					btn = Autocomplete.createMemberItem(i, item.member, themeColors)
				elseif item.type == "object" then
					btn = Autocomplete.createObjectItem(i, item.instance, themeColors)
				elseif item.type == "choice" then
					btn = Autocomplete.createEmojiItem(i, { emoji = "\u{2022}", name = item.choice.name }, themeColors)
					local label = btn:FindFirstChild("CmdName") :: TextLabel
					label.Text = item.choice.name
					label.FontFace = Theme.FONTS.semibold
				elseif item.type == "spelling" or item.type == "addWord" then
					local adding = item.type == "addWord"
					btn = Autocomplete.createEmojiItem(
						i,
						{ emoji = if adding then "+" else "\u{2022}", name = "" },
						themeColors
					)
					local label = btn:FindFirstChild("CmdName") :: TextLabel
					label.Text = if adding
						then Language.t("spelling.add", { word = item.word.word })
						else item.suggestion
					label.FontFace = if adding then Theme.FONTS.body else Theme.FONTS.semibold
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

			Autocomplete.setTitle(autocompleteFrame, Language.t("autocomplete." .. autocompleteMode))
			autocompleteFrame.Visible = true
			updateAutocompleteSelection()
		else
			autocompleteFrame.Visible = false
		end
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
		mentionMatchStart = nil
		tagMatchStart = nil
		choiceMatchStart = nil

		local text = textBox.Text

		local argCommand, argIndex = nil, 0 -- set while a command's arguments are typed

		if commandProviderFn and text:sub(1, 1) == "/" and not text:find("%s") then
			-- Command suggestions: "/partial" with no space typed yet.
			local query = text:sub(2):lower()

			for _, cmd in ipairs(commandProviderFn()) do
				if #autocompleteItems >= Autocomplete.MAX_ITEMS then
					break
				end

				local matches = query == "" or cmd.name:lower():sub(1, #query) == query

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
			-- Member suggestions: a trailing "@name" still being typed
			local atPos, partial = Mentions.typing(text)
			if atPos and partial then
				for _, member in ipairs(mentionCandidates(partial)) do
					table.insert(autocompleteItems, { type = "member", member = member })
				end
				autocompleteMode = "member"
				mentionMatchStart = atPos
			end

			-- Object suggestions: a trailing "#name" still being typed
			local hashPos, tagPartial = nil, nil
			if not atPos then
				hashPos, tagPartial = typingTag(text)
				if hashPos and tagPartial then
					for _, instance in ipairs(ObjectTags.search(tagPartial, Autocomplete.MAX_ITEMS)) do
						table.insert(autocompleteItems, { type = "object", instance = instance })
					end
					autocompleteMode = "object"
					tagMatchStart = hashPos
				end
			end

			-- Emoji suggestions: a trailing ":shortcode" still being typed.
			local colonPos = if atPos or hashPos then nil else text:match(".*():")

			if colonPos then
				local typed = text:sub(colonPos + 1)

				if typed:match("^[%w_+-]*$") and EmojiData.isValidBoundary(text:sub(1, colonPos - 1)) then
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

			-- No emoji being typed: "/command args" lists the command's arguments
			local typedName, rest = text:match("^/(%S+)%s(.*)$")
			if #autocompleteItems == 0 and commandProviderFn and typedName then
				typedName = typedName:lower()
				for _, cmd in ipairs(commandProviderFn()) do
					local matches = cmd.name:lower() == typedName
					for _, alias in ipairs(cmd.aliases or {}) do
						matches = matches or alias:lower() == typedName
					end
					if matches then
						if cmd.args and #cmd.args > 0 then
							argCommand = cmd
							-- The argument being typed: a finished word moves on to the next
							local words = 0
							for _ in rest:gmatch("%S+") do
								words += 1
							end
							if rest == "" or rest:match("%s$") then
								words += 1
							end
							argIndex = math.clamp(words, 1, #cmd.args)
						end
						break
					end
				end
			end
		end

		-- A bot option with choices: list the choices that match what's typed
		local currentArg = argCommand and argCommand.args[argIndex]
		if currentArg and type(currentArg.choices) == "table" and #currentArg.choices > 0 then
			local partial = if string.match(text, "%s$") then "" else (string.match(text, "(%S+)$") or "")
			choiceMatchStart = #text - #partial + 1
			for _, choice in ipairs(currentArg.choices) do
				if string.sub(string.lower(choice.name), 1, #partial) == string.lower(partial) then
					table.insert(autocompleteItems, { type = "choice", choice = choice })
				end
			end
			if #autocompleteItems > 0 then
				autocompleteMode = "choice"
				argCommand = nil
			end
		end

		if argCommand then
			autocompleteMode = "args"
			for i, arg in ipairs(argCommand.args) do
				if i > Autocomplete.MAX_ITEMS then
					break
				end
				Autocomplete.createArgItem(i, arg, themeColors).Parent = autocompleteFrame
			end
			Autocomplete.setTitle(autocompleteFrame, Language.t("autocomplete.options", { command = argCommand.name }))
			Autocomplete.setHint(
				autocompleteFrame,
				Icons.escape(argCommand.usage or "") .. "  ·  " .. Icons.escape(argCommand.description or "")
			)
			autocompleteFrame.Visible = true
			Autocomplete.setSelected(autocompleteFrame, argIndex)
			return
		end
		renderAutocompleteItems()
	end

	textBox:GetPropertyChangedSignal("Text"):Connect(updateAutocomplete)

	-- Spelling suggestions: clicking into (or moving the cursor onto) a word
	-- with a red line lists what it might be, and "Add to dictionary"
	local lastTextChange = 0
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		lastTextChange = os.clock()
	end)
	local function showSpellingSuggestions()
		-- Only when the cursor moved on its own (not while typing), and never
		-- over other suggestions
		if not Preferences.values.spellCheck or os.clock() - lastTextChange < 0.1 then
			return
		end
		if autocompleteFrame.Visible and autocompleteMode ~= "spelling" then
			return
		end
		local word = spelling.wordAt(textBox.CursorPosition)
		if not word then
			if autocompleteMode == "spelling" then
				autocompleteMode = nil
				hideAutocomplete()
			end
			return
		end
		clearAutocompleteItems()
		autocompleteItems = {}
		autocompleteSelectedIndex = 1
		autocompleteMode = "spelling"
		for _, suggestion in ipairs(SpellCheck.suggest(word.word, Autocomplete.MAX_ITEMS - 1)) do
			table.insert(autocompleteItems, { type = "spelling", word = word, suggestion = suggestion })
		end
		table.insert(autocompleteItems, { type = "addWord", word = word })
		renderAutocompleteItems()
	end
	textBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
		task.defer(showSpellingSuggestions)
	end)

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

	-- "X is typing..." above the message box
	local typingBar = TypingBar.create({
		container = container,
		getThemeColors = function()
			return themeColors
		end,
	})
	local typingLabel = typingBar.frame
	-- "x is typing" can be turned off in Settings
	local lastTypingUsers = {}
	local function setTypingUsers(users)
		lastTypingUsers = users
		typingBar.setUsers(if Preferences.values.typingIndicator then users else {})
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

	local function updateComposerLayout()
		-- Measure the wrapped text at the box's inner width (inside its padding).
		-- (TextBounds can't be used: it is clipped to the box's current height.)
		local horizontalPadding = textBoxPadding.PaddingLeft.Offset + textBoxPadding.PaddingRight.Offset
		local verticalPadding = textBoxPadding.PaddingTop.Offset + textBoxPadding.PaddingBottom.Offset
		local availableWidth = math.max(60, textBox.AbsoluteSize.X - horizontalPadding)
		local measuredHeight = textBox.TextSize
		local ok, bounds = pcall(function()
			local measuredText = textBox.Text == "" and " " or textBox.Text
			return TextService:GetTextSize(
				measuredText,
				textBox.TextSize,
				textBox.Font,
				Vector2.new(availableWidth, 100000)
			)
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
		scrollFrame.Size = UDim2.new(1, 0, 1, -(composerHeight + totalBarSpace + topSpace()))
		scrollFrame.Position = UDim2.new(0, 0, 0, topSpace())
		emptyState.Size = UDim2.new(1, 0, 1, -(composerHeight + totalBarSpace + topSpace()))
		emptyState.Position = UDim2.new(0, 0, 0, topSpace())
		divider.Position = UDim2.new(0, 0, 1, -(composerHeight + totalBarSpace))
		previewBar.Position = UDim2.new(0, 0, 1, -(composerHeight + PREVIEW_HEIGHT))
		replyBar.Position = UDim2.new(0, 0, 1, -(composerHeight + previewSpace + REPLY_BAR_HEIGHT))
		scrollButton.Position = UDim2.new(1, -14, 1, -(composerHeight + totalBarSpace + 14))
		typingLabel.Position = UDim2.new(0, 10, 1, -(composerHeight + totalBarSpace + 20))
		if autocompleteFrame then
			autocompleteFrame.Position = UDim2.new(0, 5, 1, -(composerHeight + 8))
		end
	end
	relayout = updateComposerLayout
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
	local pendingFile: { fileName: string, fileUrl: string, fileType: string }? = nil

	-- Callbacks set by the main plugin script
	local onVoteCallback: ((number, number) -> ())? = nil
	local onCreatePollCallback: ((string, { string }) -> ())? = nil

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
						label.TextSize = Messages.getTextSize()
					end
				end
				Messages.recolor(child, themeColors)
			end
		end
	end

	-- Modal dialogs: a shared ModalKit shell, each dialog in its own module
	-- Modals get their own layer over the whole plugin (sidebar included), so
	-- the backdrop dims everything and windows center in the full panel
	local modalLayer = Instance.new("Frame")
	modalLayer.Name = "Modals"
	modalLayer.Size = UDim2.fromScale(1, 1)
	modalLayer.BackgroundTransparency = 1
	modalLayer.Parent = widget
	local modalKit = ModalKit.new({
		container = modalLayer,
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
		getThemeColors = getThemeColors,
		detectTheme = Theme.detect,
		onThemeChanged = function(paletteName)
			applyTheme(paletteName)
		end,
		onDisplayChanged = refreshMessages,
		onTextSizeChanged = function(pixels)
			Messages.setTextSize(pixels)
		end,
	})

	-- "What's New"; closing it marks this version's notes as seen
	local changelog = ChangelogDialog.create(modalKit, {
		getThemeColors = getThemeColors,
		onClosed = function()
			if PLUGIN_VERSION then
				Settings.set(PluginConfig.SETTING_KEY_LAST_SEEN_VERSION, PLUGIN_VERSION)
			end
		end,
	})

	-- Badges: yours and the ones for sale (handlers set by the controller)
	local badgeHandlers = nil
	local purchaseDialog -- the checkout, opened from the Badges dialog's Buy
	local badgesDialog = BadgesDialog.create(modalKit, {
		getThemeColors = getThemeColors,
		getHandlers = function()
			return badgeHandlers
		end,
		onBuy = function(item)
			purchaseDialog.open(item)
		end,
	})
	purchaseDialog = PurchaseDialog.create(modalKit, {
		getThemeColors = getThemeColors,
		getHandlers = function()
			return badgeHandlers
		end,
		onPurchased = function()
			badgesDialog.reload()
			if conversationSidebar.notify then
				conversationSidebar.notify({
					title = Language.t("notify.badgeUnlocked"),
					text = Language.t("notify.badgeUnlockedText"),
					icon = "badges",
				})
			end
		end,
	})

	-- About: plugin info, the not-affiliated-with-Roblox disclaimer and terms
	local aboutDialog = AboutDialog.create(modalKit, {
		getThemeColors = getThemeColors,
	})

	-- Admin: the dashboard for moderators and up
	local adminDialog = AdminDialog.create(modalKit, {
		getThemeColors = getThemeColors,
		openScript = function(module)
			pluginInstance:OpenScript(module)
		end,
	})

	-- Developer: make and manage your bots
	local developerDialog = DeveloperDialog.create(modalKit, {
		getThemeColors = getThemeColors,
		openScript = function(module)
			pluginInstance:OpenScript(module)
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
	local replyReferenceSenderId: number? = nil
	local replyReferenceContent: string? = nil
	local replyOriginalDeleted = false
	local renderReplyText -- assigned below, forward-declared for removeMessage

	-- Editing your own messages (right-click > Edit Message): the text goes into
	-- the message box and the reply bar says "Editing message" until it's saved
	-- (MessageController) or cancelled with the bar's ×. One table so create()
	-- stays under Luau's 200-local limit.
	local editing = {
		timestamp = nil :: number?,
		myUserId = 0,
	}

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
	-- Returns the current reply reference (timestamp, sender, content, senderId),
	-- or nil when no reply is pending.
	--!
	local function getReplyReference()
		if replyReferenceTimestamp then
			return replyReferenceTimestamp, replyReferenceSender, replyReferenceContent, replyReferenceSenderId
		end
		return nil
	end

	--!
	-- Replaces a reply's quoted preview with "Original message deleted".
	--!
	local function markReplyDeleted(msgContainer)
		msgContainer:SetAttribute("ReplyOriginalDeleted", true)
		local ref = msgContainer:FindFirstChild("ReplyReference")
		if not ref then
			return
		end
		local label = ref:FindFirstChild("ReplyLabel", true)
		if label and label:IsA("TextLabel") then
			label.RichText = true
			label.Text =
				string.format('<font color="%s"><i>Original message deleted</i></font>', toHex(themeColors.timestamp))
		end
	end

	--!
	-- After a reply is added, marks it as deleted if the message it replies to
	-- is not in the chat (e.g. it was deleted before the plugin loaded).
	--!
	local function checkReplyTarget(msgContainer, replyRef)
		if not replyRef or not replyRef.timestamp then
			return
		end
		task.delay(1, function()
			if not msgContainer.Parent then
				return
			end
			for _, child in ipairs(scrollFrame:GetChildren()) do
				if child ~= msgContainer and child:GetAttribute("Timestamp") == replyRef.timestamp then
					-- Older replies don't store the original author's id: use the original's
					if not replyRef.senderId then
						Messages.setReplyAvatar(msgContainer, child:GetAttribute("SenderId"), themeColors)
					end
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
		if editing.timestamp then
			replyText.Text = Icons.inline("edit", false, 13) .. "  " .. Icons.escape(Language.t("reply.editing"))
			return
		end
		if replyOriginalDeleted and replyReferenceTimestamp then
			replyText.Text = string.format(
				'<font color="%s"><i>%s</i></font>',
				toHex(themeColors.timestamp),
				Icons.escape(Language.t("reply.originalDeleted"))
			)
			return
		end
		if not replyReferenceSender then
			replyText.Text = ""
			return
		end
		-- Their display name (per Settings); the plugin's own messages say Team Chat
		local escapedName = Icons.escape(Author.nameOf(replyReferenceSender, replyReferenceSenderId))
		replyText.Text = Language.t("reply.replyingTo", {
			name = string.format(
				'<font color="%s"><b>%s</b></font>',
				toHex(UsernameColors.getNameColor(replyReferenceSender)),
				escapedName
			),
		})
	end

	--!
	-- Sets the reply reference and shows the reply bar.
	--!
	local function setReplyReference(timestamp: number, sender: string, content: string, senderId: number?)
		replyReferenceTimestamp = timestamp
		replyReferenceSender = sender
		replyReferenceSenderId = senderId
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
		editing.timestamp = nil
		replyReferenceTimestamp = nil
		replyReferenceSender = nil
		replyReferenceSenderId = nil
		replyReferenceContent = nil
		replyOriginalDeleted = false
		replyBar.Visible = false
		updateComposerLayout()
	end

	-- Connect reply close button
	replyCloseButton.MouseButton1Click:Connect(function()
		if editing.timestamp then
			textBox.Text = "" -- cancelling an edit drops the edited text
		end
		hideReplyReference()
	end)

	--[=[
		Starts editing one of your messages: its text goes into the message box.
	]=]
	function editing.start(timestamp: number)
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:GetAttribute("Timestamp") == timestamp and child:FindFirstChild("TextContent") then
				hideReplyReference()
				editing.timestamp = timestamp
				textBox.Text = child:GetAttribute("Content") or ""
				renderReplyText()
				replyBar.Visible = true
				updateComposerLayout()
				pcall(function()
					textBox:CaptureFocus()
				end)
				textBox.CursorPosition = #textBox.Text + 1
				return
			end
		end
	end
	contextMenu.handlers.edit = editing.start

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
				log.warn("Could not upload image as permanent asset. Using temporary ID (local only).")
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
					previewLabel.Text = Icons.inline("attachFile", false, 14)
						.. " "
						.. Icons.escape(fileName)
						.. " (local only)"
					log.warn(
						""
							.. fileName
							.. " is shared as a local-only file: plugins can't upload "
							.. fileType
							.. " files as Roblox assets, so collaborators won't be able to open it."
					)
				else
					hidePreview()
					log.warn("Could not attach file: " .. fileName)
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
			if isUploading then
				return
			end

			task.spawn(function()
				local ok, files = pcall(function()
					return StudioService:PromptImportFilesAsync(ATTACH_FILE_FILTER)
				end)
				if not ok then
					log.warn("Could not open the file picker: " .. tostring(files))
					return
				end
				local file = files and files[1]
				if not file then
					return
				end -- picker cancelled

				local extension = string.lower(string.match(file.Name, "%.([^.]+)$") or "")
				if extension == "gif" then
					-- Decode the GIF into an animated sprite sheet (GifPlayer)
					pendingImage = nil
					pendingFile = nil
					previewThumbnail.Visible = false
					previewLabel.Text = Icons.inline("attachFile", false, 14)
						.. " Processing "
						.. Icons.escape(file.Name)
						.. "..."
					previewBar.Visible = true
					updateComposerLayout()
					isUploading = true
					local gifOk, url, uploaded = pcall(GifPlayer.fromFile, file)
					isUploading = false
					if gifOk then
						showPreview(url, if uploaded then "GIF attached" else "GIF attached (local only)")
					else
						hidePreview()
						log.warn("Could not read " .. file.Name .. ": " .. tostring(url))
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
		-- Dragging anything else over the widget (Explorer items, files) comes
		-- with no drag data at all.
		--!

		local function isAttachmentDrag(dragData): boolean
			return type(dragData) == "table" and dragData.MimeType == ATTACHMENT_MIME_TYPE
		end

		widget.PluginDragEntered:Connect(function(dragData)
			if isAttachmentDrag(dragData) then
				dropOverlay.Visible = true
			end
		end)
		widget.PluginDragLeft:Connect(function()
			dropOverlay.Visible = false
		end)
		widget.PluginDragDropped:Connect(function(dragData)
			dropOverlay.Visible = false
			if not isAttachmentDrag(dragData) or type(dragData.Data) ~= "string" then
				return
			end

			local fileName, fileUrl, fileType = string.match(dragData.Data, "^(.-)|(.-)|(.-)$")
			if not fileUrl or fileUrl == "" then
				return
			end

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
		emojiPicker.recolor()
		divider.BackgroundColor3 = themeColors.divider
		inputFrame.BackgroundColor3 = themeColors.inputFrame
		header.recolor()
		pinsPanel.recolor()
		teamCreateNotice.recolor()
		local unreadDivider = scrollFrame:FindFirstChild("UnreadDivider")
		if unreadDivider then
			colorUnreadDivider(unreadDivider)
		end
		conversationSidebar.list.recolor(themeColors)
		conversationSidebar.newMessageDialog.recolor()
		textBox.BackgroundColor3 = themeColors.inputBox
		MentionPills.recolor(textBox, themeColors)
		composerText.recolor()
		spelling.recolor()
		textBox.TextColor3 = themeColors.textBoxText
		textBox.PlaceholderColor3 = themeColors.placeholder
		sendButton.BackgroundColor3 = themeColors.sendButton
		sendButton.TextColor3 = themeColors.sendButtonText
		attachButton.BackgroundColor3 = themeColors.attachButton
		attachButton.TextColor3 = themeColors.attachIcon
		typingBar.recolor()

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
		badgesDialog.recolor()
		purchaseDialog.recolor()
		aboutDialog.recolor()
		if conversationSidebar.settingsTabs then
			conversationSidebar.settingsTabs.recolor()
		end
		for _, toasts in ipairs(conversationSidebar.toasts or {}) do
			toasts.recolor(themeColors)
		end

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
		badgeTooltip.recolor(themeColors)

		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") and child.Name ~= "UnreadDivider" then
				Messages.recolor(child, themeColors)
			end
		end
	end

	-- Forward declaration: addMessage needs to report link-open failures but
	-- addSystemMessage is defined further below.
	local addSystemMessageRef

	local function addMessage(sender, timestamp, content, imageUrl, replyRef, senderId)
		hideEmptyState()
		local msgContainer = Messages.text(sender, timestamp, content, imageUrl, themeColors, replyRef, senderId)
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
			-- Links, spoilers and #tags are clickable (UI/MessageText)
			MessageText.attachClicks(textLabel, function(url)
				if addSystemMessageRef then
					addSystemMessageRef(Language.t("links.copied", { url = url }))
				end
			end)
			local urls = MessageText.urls(textLabel)
			if #urls > 0 then
				if Preferences.values.linkPreviews then
					EmbedManager.attach(msgContainer, urls, themeColors, { plugin = pluginInstance })
				end
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
				-- Edit and Delete only on your own messages; a public bot message can
				-- be deleted by whoever ran its command
				local isMine = editing.myUserId > 0 and senderId == editing.myUserId and sender ~= "System"
				local ranIt = editing.myUserId > 0
					and msgContainer:GetAttribute("BotMessage") == true
					and (
						msgContainer:GetAttribute("SaidBy") == editing.myUserId
						or msgContainer:GetAttribute("BotOwner") == editing.myUserId
					)
				-- Anyone signed in can pin, except answers only they can see
				local canPin = editing.myUserId > 0 and not msgContainer:GetAttribute("Ephemeral")
				contextMenu.show(timestamp, {
					canEdit = isMine,
					canDelete = isMine or ranIt,
					canPin = canPin,
					pinned = pinnedTimestamps[timestamp] == true,
					canReact = canPin,
					messageId = msgContainer:GetAttribute("MessageId"),
				})
			end
		end)
		return msgContainer
	end

	--[=[
		Shows a message's new text after it was edited (here or by its author
		elsewhere): text, "(edited)", clickable links and link previews.
	]=]
	function editing.update(timestamp: number, content: string, edited: boolean)
		for _, child in ipairs(scrollFrame:GetChildren()) do
			local label = child:FindFirstChild("TextContent")
			if child:GetAttribute("Timestamp") == timestamp and label and child:FindFirstChild("Author") then
				child:SetAttribute("Content", content)
				child:SetAttribute("Edited", edited)
				Messages.setBody(child, themeColors)
				for _, embed in ipairs(child:GetChildren()) do
					if embed.Name == "Embed" then
						embed:Destroy()
					end
				end
				local urls = MessageText.urls(label)
				if #urls > 0 then
					if Preferences.values.linkPreviews then
						EmbedManager.attach(child, urls, themeColors, { plugin = pluginInstance })
					end
				end
				return
			end
		end
	end

	local function addAnnouncementMessage(sender, timestamp, content, replyRef)
		hideEmptyState()
		local msgContainer = Messages.announcement(sender, timestamp, content, themeColors, replyRef)
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
				contextMenu.show(timestamp, {
					canReact = editing.myUserId > 0,
					messageId = msgContainer:GetAttribute("MessageId"),
				})
			end
		end)
	end

	--!
	-- Adds a poll message to the scroll frame with interactive vote bars.
	--!
	local pollContainers = {}

	local function addPollMessage(sender, timestamp, pollData, replyRef)
		hideEmptyState()
		local msgContainer = Messages.poll(sender, timestamp, pollData, themeColors, replyRef)
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

		Messages.updatePollVotes(msgContainer, pollData, themeColors)

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
				contextMenu.show(timestamp, {
					canReact = editing.myUserId > 0,
					messageId = msgContainer:GetAttribute("MessageId"),
				})
			end
		end)
	end

	--!
	-- Updates a poll message with new vote data.
	--!
	local function updatePollMessage(timestamp, pollData)
		local msgContainer = pollContainers[timestamp]
		if msgContainer then
			Messages.updatePollVotes(msgContainer, pollData, themeColors)
		end
	end

	--!
	-- Adds a file message to the scroll frame with a file card.
	--!
	local function addFileMessage(sender, timestamp, fileName, fileUrl, fileType, content, replyRef, senderId)
		hideEmptyState()
		local msgContainer =
			Messages.file(sender, timestamp, content, fileName, fileUrl, fileType, themeColors, replyRef, senderId)
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
		local draggableCard = msgContainer:FindFirstChild("FileCard") or msgContainer:FindFirstChild("AudioPlayerCard")
		if draggableCard and draggableCard:IsA("Frame") then
			draggableCard.Active = true
			draggableCard.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					for _, controlName in ipairs({ "PlayPauseButton", "Waveform", "DownloadButton" }) do
						local control = draggableCard:FindFirstChild(controlName, true)
						if control and isInside(control, Vector2.new(input.Position.X, input.Position.Y)) then
							return
						end
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
				contextMenu.show(timestamp, {
					canReact = editing.myUserId > 0,
					messageId = msgContainer:GetAttribute("MessageId"),
				})
			end
		end)
	end

	--!
	-- Adds a system message to the chat.
	--!
	local function addSystemMessage(text)
		hideEmptyState()
		local msgContainer = Messages.text("System", os.time(), text, nil, themeColors)
		msgContainer:SetAttribute("Sender", "System")
		msgContainer:SetAttribute("Content", text)
		msgContainer:SetAttribute("Timestamp", os.time())
		msgContainer:SetAttribute("IsSystem", true)
		-- Only you see it (it isn't saved): say so, with a way to dismiss it
		Messages.addOnlyYouNote(msgContainer, themeColors, function()
			msgContainer:Destroy()
		end)
		msgContainer.Parent = scrollFrame
		return msgContainer
	end
	addSystemMessageRef = addSystemMessage

	-- Clicking a #tag: select the object and glide the camera to it
	MessageText.onTag = function(path: string)
		local instance = ObjectTags.resolve(path)
		if instance then
			ObjectTags.focus(instance, Animation.enabled())
		else
			addSystemMessage(Language.t("tag.notFound", { name = Markdown.tagName(path) }))
		end
	end

	--!
	-- A command's reply as a card (see Embeds/Providers/CommandEmbed for the
	-- spec): a Team Chat message with the card instead of text.
	--!
	local function addSystemEmbed(spec)
		local msgContainer = addSystemMessage("")
		msgContainer:SetAttribute("HasCommandEmbed", true)
		local embed = CommandEmbed.fromSpec(spec, themeColors)
		embed.LayoutOrder = 2
		embed.Parent = msgContainer
		return msgContainer
	end

	--!
	-- A bot message everyone sees (saved in the conversation): Team Chat's
	-- text and/or card, under a "<name> used /command" line, like a Discord
	-- bot's reply to a slash command.
	-- entry: { timestamp, content, saidBy, saidByName, command, embed? (spec) }
	--!
	local function addBotMessage(entry)
		local usedBy = if entry.saidByName
			then {
				sender = entry.saidByName,
				senderId = entry.saidBy,
				content = Language.t("bot.used", { command = entry.command or "" }),
			}
			else nil
		-- A deferred answer that hasn't arrived: "<bot> is thinking…"
		local content = if entry.thinking
			then "*" .. Language.t("bot.thinking", { bot = entry.botName or PluginConfig.PLUGIN_TITLE }) .. "*"
			else entry.content or ""
		local msgContainer = addMessage(entry.botName or "System", entry.timestamp, content, nil, usedBy, 0)
		msgContainer:SetAttribute("Thinking", entry.thinking == true)
		msgContainer:SetAttribute("SaidBy", entry.saidBy or 0)
		msgContainer:SetAttribute("BotMessage", true)
		if entry.botId then
			-- A user-made bot: its own avatar and an (unverified) BOT tag
			msgContainer:SetAttribute("BotOwner", entry.botOwner or 0)
			Messages.markBot(msgContainer, entry.botAvatar, themeColors)
		end
		if entry.embed then
			msgContainer:SetAttribute("HasCommandEmbed", true)
			local embed = CommandEmbed.fromSpec(entry.embed, themeColors)
			embed.LayoutOrder = 2
			embed.Parent = msgContainer
		end
		-- Buttons: links open, the others send an interaction to the bot
		if entry.components and entry.botId then
			local buttons = Components.build(entry.components, themeColors, function(button)
				if button.url then
					if not Browser.open(button.url) then
						addSystemMessage(Language.t("links.copied", { url = button.url }))
					end
					return
				end
				Bots.clickButton({
					botId = entry.botId,
					customId = button.customId,
					message = entry.instance or msgContainer,
				})
			end)
			buttons.LayoutOrder = 3
			buttons.Parent = msgContainer
		end
		-- Ephemeral: only you see it (saved for you only, or never saved)
		if entry.ephemeralLocal or entry.visibleTo then
			msgContainer:SetAttribute("Ephemeral", true)
			Messages.addOnlyYouNote(msgContainer, themeColors, function()
				if entry.onDismiss then
					entry.onDismiss()
				else
					msgContainer:Destroy()
				end
			end)
		end
		return msgContainer
	end

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
		if editing.timestamp then
			textBox.Text = ""
		end
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
		conversationSidebar.info = info
		local isDm = info.kind == "dm"
		-- DMs show the display name (or username, per Settings), the verified
		-- badge and the @username
		local profile = if isDm and info.userId and Author.getProfile then Author.getProfile(info.userId) else nil
		local verified = profile ~= nil and profile.verified
		local shown = if isDm
			then Preferences.nameFor(info.name, profile and profile.displayName)
			else PluginConfig.PLUGIN_TITLE
		header.setTitle(shown, {
			verified = verified,
			subtitle = if isDm and shown ~= info.name then "@" .. info.name else nil,
		})
		textBox.PlaceholderText = if isDm
			then Language.t("composer.placeholderDm", { name = shown })
			else Language.t("composer.placeholder")
		Icons.apply(emptyIcon, if isDm then "directMessages" else "emptyChat")
		emptyTitleLabel.RichText = true
		emptyTitleLabel.Text = if isDm
			then Icons.escape(shown) .. BadgeIcons.verifiedSuffix(verified, 16)
			else Language.t("empty.title")
		emptySubtitle.Text = if isDm
			then Language.t("empty.dmSubtitle", { name = shown })
			else Language.t("empty.subtitle")
		emptySubtitle.Size = UDim2.new(1, -30, 0, if isDm then 36 else 20)
		conversationSidebar.list.setActive(info.id)
	end

	function conversationSidebar.setConversations(entries, activeId)
		conversationSidebar.entries = entries
		conversationSidebar.activeId = activeId
		conversationSidebar.list.update(entries, activeId)
		-- All unread messages in the widget's title, like "Team Chat 1.26.0 (3)",
		-- so they show while the chat is a tab or out of view
		local total = 0
		for _, entry in ipairs(entries) do
			total += entry.unread or 0
		end
		widget.Title = if total > 0
			then string.format("%s (%s)", baseTitle, if total > 99 then "99+" else tostring(total))
			else baseTitle
	end

	--[=[
		The red "New" line above the first unread message of the open
		conversation (nil removes it). It goes when you switch conversations.
	]=]
	function conversationSidebar.showUnreadDivider(timestamp: number?)
		local old = scrollFrame:FindFirstChild("UnreadDivider")
		if old then
			old:Destroy()
		end
		if not timestamp then
			return
		end
		local unreadDivider = Instance.new("Frame")
		unreadDivider.Name = "UnreadDivider"
		unreadDivider.BackgroundTransparency = 1
		unreadDivider.Size = UDim2.new(1, 0, 0, 18)
		-- Message rows are ordered by timestamp: this sits just before the first unread one
		unreadDivider.LayoutOrder = math.floor(timestamp) - 1
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.new(0, 12, 0.5, 0)
		line.Size = UDim2.new(1, -24, 0, 1)
		line.BorderSizePixel = 0
		line.Parent = unreadDivider
		local tag = Instance.new("TextLabel")
		tag.Name = "Tag"
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -12, 0.5, 0)
		tag.Size = UDim2.fromOffset(0, 14)
		tag.AutomaticSize = Enum.AutomaticSize.X
		tag.BorderSizePixel = 0
		tag.FontFace = Theme.FONTS.bold
		tag.TextSize = 10
		tag.Parent = unreadDivider
		Language.bind(tag, "Text", "unread.new", nil, string.upper)
		local tagCorner = Instance.new("UICorner")
		tagCorner.CornerRadius = UDim.new(0, 4)
		tagCorner.Parent = tag
		local tagPadding = Instance.new("UIPadding")
		tagPadding.PaddingLeft = UDim.new(0, 5)
		tagPadding.PaddingRight = UDim.new(0, 5)
		tagPadding.Parent = tag
		colorUnreadDivider(unreadDivider)
		unreadDivider.Parent = scrollFrame
	end

	-- Re-draws the header and sidebar (names or verified badges changed)
	function conversationSidebar.rerender()
		if conversationSidebar.entries then
			conversationSidebar.list.update(conversationSidebar.entries, conversationSidebar.activeId)
		end
		if conversationSidebar.info then
			conversationSidebar.setConversation(conversationSidebar.info)
		end
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
	-- Sets the widget visibility (the Enabled listener below notifies callbacks).
	--!
	local function setVisible(visible)
		widget.Enabled = visible
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
		contextMenu.handlers.reply = fn
	end

	--!
	-- Registers a callback for message deletion.
	--!
	--!
	-- Registers a callback for pinning and unpinning: fn(timestamp, pinned).
	--!
	local function onPin(fn)
		pinHandler = fn
		contextMenu.handlers.pin = fn
	end

	--!
	-- Shows the open conversation's pinned messages (Services/Chat/Pins.list).
	--!
	local function setPins(list)
		table.clear(pinnedTimestamps)
		for _, entry in ipairs(list) do
			pinnedTimestamps[entry.timestamp] = true
		end
		pinsPanel.setPins(list)
	end

	local function onDelete(fn)
		contextMenu.handlers.delete = fn
	end

	--!
	-- Registers what reacting does: fn(timestamp, emoji) adds or removes yours.
	--!
	local function onReact(fn)
		reactHandler = fn
	end

	-- "builderman and Roblox reacted with 👍" (at most 3 names)
	local function describeReaction(reaction): string
		local names = reaction.names or {}
		local shown = {}
		for index = 1, math.min(3, #names) do
			table.insert(shown, names[index])
		end
		local list = table.concat(shown, ", ")
		if #names > 3 then
			return Language.t("reactions.whoMore", { names = list, count = #names - 3, emoji = reaction.emoji })
		end
		return Language.t("reactions.who", { names = list, emoji = reaction.emoji })
	end

	-- A saved message's row: by its name (MessageId) or, failing that, the
	-- newest row with its timestamp
	local function rowOf(target: string | number, untaggedOnly: boolean?): Frame?
		local found = nil
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") and not child:GetAttribute("IsSystem") and not child:GetAttribute("Ephemeral") then
				local id = child:GetAttribute("MessageId")
				if type(target) == "string" then
					if id == target then
						return child
					end
				elseif child:GetAttribute("Timestamp") == target and not (untaggedOnly and id) then
					found = child
				end
			end
		end
		return found
	end

	--!
	-- Marks the row just shown for a saved message with the message's name,
	-- so reactions find the right one when messages share a second.
	--!
	local function tagMessage(timestamp: number, messageId: string)
		local row = rowOf(timestamp, true)
		if row then
			row:SetAttribute("MessageId", messageId)
		end
	end

	--!
	-- Shows a message's reactions (Services/Chat/Reactions.read) under it.
	-- target: the message's name (or its timestamp).
	--!
	local function setReactions(target: string | number, reactions)
		local row = rowOf(target)
		if not row then
			return
		end
		Messages.setReactions(row, reactions, themeColors, {
			toggle = function(emoji: string)
				if reactHandler then
					reactHandler(target, emoji)
				end
			end,
			add = function()
				pickReaction(target)
			end,
			hover = function(button, reaction)
				if not button then
					badgeTooltip.hide()
				elseif reaction then
					badgeTooltip.show(button, describeReaction(reaction))
				else
					badgeTooltip.show(button, Language.t("menu.addReaction"))
				end
			end,
		})
	end

	--!
	-- Registers a callback for message copy.
	--!
	local function onCopy(fn)
		contextMenu.handlers.copy = fn
	end

	-- Restore the saved settings, then apply the theme they pick
	settingsDialog.restore()
	applyTheme(settingsDialog.resolveTheme())

	-- The Settings window, its tabs in groups: Team Chat (General, Badges),
	-- Manage (Admin, Developer) and Info (What's New, About)
	local settingsTabs = SettingsTabs.create({
		{
			name = "General",
			icon = "settings",
			labelKey = "tab.general",
			titleKey = "title.settings",
			group = "chat",
			dialog = settingsDialog,
		},
		{
			name = "Badges",
			icon = "badges",
			labelKey = "tab.badges",
			titleKey = "title.badges",
			group = "chat",
			dialog = badgesDialog,
		},
		{
			name = "Admin",
			icon = "admin",
			labelKey = "tab.admin",
			titleKey = "title.admin",
			group = "manage",
			dialog = adminDialog,
		},
		{
			name = "Developer",
			icon = "developer",
			labelKey = "tab.developer",
			titleKey = "title.developer",
			group = "manage",
			dialog = developerDialog,
		},
		{
			name = "What's New",
			icon = "whatsNew",
			labelKey = "tab.whatsNew",
			titleKey = "title.whatsNew",
			group = "info",
			dialog = changelog,
		},
		{
			name = "About",
			icon = "about",
			labelKey = "tab.about",
			titleKey = "title.about",
			group = "info",
			dialog = aboutDialog,
		},
	}, getThemeColors)
	conversationSidebar.settingsTabs = settingsTabs

	-- Notifications: toasts at the bottom-centre of the plugin panel
	local panelToasts = Toasts.create(widget, themeColors, { bottomOffset = INPUT_HEIGHT + 20 })
	function conversationSidebar.notify(toast)
		toast.duration = toast.duration or Preferences.values.notificationDuration
		return panelToasts.show(toast)
	end
	conversationSidebar.toasts = { panelToasts }

	-- Live messages fade in (history loading in stays instant)
	scrollFrame.ChildAdded:Connect(function(child)
		task.defer(function()
			local timestamp = child:GetAttribute("Timestamp")
			if child.Parent and type(timestamp) == "number" and os.time() - timestamp <= 5 then
				Animation.fadeIn(child, "smooth")
			end
		end)
	end)
	-- Menus and bars fade in when they appear
	for _, gui in ipairs({ autocompleteFrame, typingLabel, replyBar }) do
		gui:GetPropertyChangedSignal("Visible"):Connect(function()
			if gui.Visible then
				Animation.fadeIn(gui, "quick")
			end
		end)
	end

	-- Pop up once per published version. Only big updates get a changelog
	-- entry; small version bumps have none, so nothing pops up for them.
	-- A first install (nothing saved yet) shows About instead, once.
	local lastSeenVersion = Settings.get(PluginConfig.SETTING_KEY_LAST_SEEN_VERSION)
	if Settings.firstRun and Settings.get(PluginConfig.SETTING_KEY_ABOUT_SEEN) == nil then
		Settings.set(PluginConfig.SETTING_KEY_ABOUT_SEEN, true)
		if PLUGIN_VERSION then
			Settings.set(PluginConfig.SETTING_KEY_LAST_SEEN_VERSION, PLUGIN_VERSION) -- no What's New for it
		end
		task.defer(function()
			widget.Enabled = true
			settingsTabs.open("About")
		end)
	elseif PLUGIN_VERSION and changelog.hasNotesFor(PLUGIN_VERSION) and lastSeenVersion ~= PLUGIN_VERSION then
		task.defer(function()
			widget.Enabled = true -- the chat panel may be closed; open it so the popup is seen
			settingsTabs.open("What's New", PLUGIN_VERSION)
		end)
	end

	-- The sidebar gear button opens (or closes) the Settings window
	sidebarSettingsButton.MouseButton1Click:Connect(settingsTabs.toggle)

	-- Clicking anywhere outside the widget (3D view, Explorer, another
	-- panel, another app...) moves focus away from it: menus close, but open
	-- windows (Settings, a poll...) stay open
	widget.WindowFocusReleased:Connect(function()
		hideContextMenu()
		hideAutocomplete()
		setAttachMenuOpen(false)
	end)

	--!
	-- Re-renders the author line of every message from userId (their badges
	-- changed), and the Badges dialog when it's your own.
	--!
	local function refreshBadges(userId: number)
		for _, row in ipairs(scrollFrame:GetChildren()) do
			if row:GetAttribute("SenderId") == userId and row:FindFirstChild("Author") then
				Author.render(row, themeColors)
			end
		end
		if userId == editing.myUserId then
			badgesDialog.recolor()
		end
	end

	-- A display name or verified flag came in: re-render everything showing it
	-- (messages, reply lines, the header and the sidebar). Batched per frame.
	local profileRefreshQueued = false
	local function refreshProfiles()
		if profileRefreshQueued then
			return
		end
		profileRefreshQueued = true
		task.defer(function()
			profileRefreshQueued = false
			if not container.Parent then
				return
			end
			refreshMessages()
			conversationSidebar.rerender()
		end)
	end

	-- A new language: re-draw the text that's built by code (bound labels
	-- update by themselves)
	Lifetime.add(Language.changed:Connect(function()
		sidebarSettingsButton:SetAttribute("Tooltip", Language.t("sidebar.settings"))
		badgesDialog.recolor()
		purchaseDialog.recolor()
		changelog.recolor()
		setTypingUsers(lastTypingUsers)
		renderReplyText()
		conversationSidebar.rerender()
		if not conversationSidebar.info then
			emptyTitleLabel.Text = Language.t("empty.title")
			emptySubtitle.Text = Language.t("empty.subtitle")
			textBox.PlaceholderText = Language.t("composer.placeholder")
		end
	end))

	-- Settings that change how messages and names look
	Lifetime.add(Preferences.changed:Connect(function(key)
		if key == "typingIndicator" then
			setTypingUsers(lastTypingUsers)
		elseif key == "spellCheck" then
			if Preferences.values.spellCheck then
				task.spawn(SpellCheck.load)
			end
			spelling.refresh()
		else
			refreshProfiles()
		end
	end))

	-- Sync widget visibility changes back to callbacks
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if visibilityCallback then
			visibilityCallback(widget.Enabled)
		end
	end)

	return {
		widget = widget,
		teamCreateNotice = teamCreateNotice,
		textBox = textBox,
		sendButton = sendButton,
		addMessage = addMessage,
		addAnnouncementMessage = addAnnouncementMessage,
		addPollMessage = addPollMessage,
		addFileMessage = addFileMessage,
		addSystemMessage = addSystemMessage,
		addSystemEmbed = addSystemEmbed,
		addBotMessage = addBotMessage,
		-- Opens a script in Studio's editor (/bot create)
		openScript = function(script: LuaSourceContainer)
			pluginInstance:OpenScript(script)
		end,
		updatePollMessage = updatePollMessage,
		setReplyReference = setReplyReference,
		getReplyReference = getReplyReference,
		clearReplyReference = hideReplyReference,
		-- Editing your own messages
		setCurrentUserId = function(userId: number)
			editing.myUserId = userId
		end,
		getEditingMessage = function(): number?
			return editing.timestamp
		end,
		clearEditing = hideReplyReference,
		updateMessage = editing.update,
		removeMessage = removeMessage,
		clearChat = clearChat,
		resetMessages = conversationSidebar.reset,
		setConversation = conversationSidebar.setConversation,
		setConversations = conversationSidebar.setConversations,
		showUnreadDivider = conversationSidebar.showUnreadDivider,
		onConversationSelected = conversationSidebar.onSelect,
		setNewMessageHandlers = conversationSidebar.setNewMessageHandlers,
		onConversationClosed = conversationSidebar.onClose,
		setVisible = setVisible,
		onVisibilityChanged = onVisibilityChanged,
		-- The tabbed Settings window
		openSettings = function(tab: string?)
			settingsTabs.open(tab or "General")
		end,
		closeSettings = settingsTabs.close,
		-- Change or read a setting by its key (as if picked on the page)
		applySetting = settingsDialog.set,
		getSetting = settingsDialog.get,
		getSettingControls = function()
			return settingsDialog.controls
		end,
		openChangelog = function(version: string?)
			settingsTabs.open("What's New", version)
		end,
		openBadges = function()
			settingsTabs.open("Badges")
		end,
		openPurchase = function(item)
			purchaseDialog.open(item)
		end,
		openAbout = function()
			settingsTabs.open("About")
		end,
		-- Toast notification: { title, text?, userId?, icon?, onClick? }
		notify = conversationSidebar.notify,
		-- Badges next to names: provider(userId) -> badges; handlers for the dialog
		setBadgeProvider = function(provider)
			Author.getBadges = provider
		end,
		-- Display names and verified flags: provider(userId) -> { displayName?, verified }
		setProfileProvider = function(provider)
			Author.getProfile = provider
			conversationSidebar.list.getProfile = provider
		end,
		refreshProfiles = refreshProfiles,
		setBadgeHandlers = function(handlers)
			badgeHandlers = handlers
		end,
		refreshBadges = refreshBadges,
		-- Toolbar button: from another tab it switches to General
		toggleSettings = function(): boolean
			local tab = settingsTabs.current()
			if tab ~= nil and tab ~= "General" then
				settingsTabs.open("General")
				return true
			end
			return settingsDialog.toggle()
		end,
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
		onPin = onPin,
		setPins = setPins,
		onReact = onReact,
		setReactions = setReactions,
		tagMessage = tagMessage,
		emojiPicker = emojiPicker,
		pinsPanel = pinsPanel,
		developerDialog = developerDialog,
		adminDialog = adminDialog,
		spelling = spelling,
		onCopy = onCopy,
		setTypingUsers = setTypingUsers,
		onTypingActivity = onTypingActivity,
	}
end

return ChatUI
