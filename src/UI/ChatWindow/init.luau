--[[
	ChatWindow

	The Team Chat dock widget. Builds the window from its parts and returns
	the API the controllers use: messages, conversations, the composer,
	settings and the dialogs. The UI never requires Services; App passes the
	ones it needs in.

	Parts share one context table:
		plugin, widget, container   the plugin and the window's frames
		palette, getPalette()       the current theme's colors
		services                    { admin, bots, chat, objectTags, usage }
		tooltip, pointer            the shared tooltip and mouse helpers
		userId                      the signed-in user (0 until known)
		topSpace()                  height of the header and the Team Create notice
		relayout()                  re-fits the chat around the composer

	Parts are created in this order on purpose: siblings with the same
	ZIndex draw in the order they were added.

	Usage:
		local ui = ChatWindow.create(plugin, services)
		ui.addMessage(sender, timestamp, content)
]]

local Attachments = require(script.Attachments)
local Author = require(script.Parent.Messages.Author)
local Autocomplete = require(script.Parent.Components.Autocomplete)
local Composer = require(script.Composer)
local Constants = require(script.Parent.Parent.Config.Constants)
local ContextMenu = require(script.ContextMenu)
local Dialogs = require(script.Dialogs)
local EmojiPicker = require(script.EmojiPicker)
local Feed = require(script.Feed)
local Header = require(script.Header)
local Language = require(script.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)
local PinsPanel = require(script.PinsPanel)
local Pointer = require(script.Pointer)
local Preferences = require(script.Parent.Common.Preferences)
local Sidebar = require(script.Sidebar)
local SpellCheck = require(script.Parent.Parent.Util.SpellCheck)
local Suggestions = require(script.Suggestions)
local TeamCreateNotice = require(script.TeamCreateNotice)
local Theme = require(script.Parent.Parent.Config.Theme)
local Toasts = require(script.Parent.Components.Toasts)
local Tooltip = require(script.Parent.Components.Tooltip)

local THEMES = Theme.PALETTES
local INPUT_HEIGHT = Theme.INPUT_HEIGHT

local ChatWindow = {}

--[=[
	Creates the dock widget (reusing it after a reload) and returns its API.
	services: { admin, bots, chat, objectTags, usage }
]=]
function ChatWindow.create(pluginInstance: Plugin, services)
	Preferences.load() -- animations and display settings apply from the first frame
	local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Left, true, false, 300, 500, 250, 300)

	local widget = pluginInstance:CreateDockWidgetPluginGui("TeamChatWidget", widgetInfo)
	local titleTag = Constants.PLUGIN_VERSION
	if Constants.DEVELOPMENT_MODE then
		titleTag ..= " \u{00B7} Development Mode"
	end
	local baseTitle = Constants.PLUGIN_TITLE .. (if titleTag ~= "" then " " .. titleTag else "")
	widget.Title = baseTitle

	-- A reload reuses the widget: clear what the previous load built
	for _, child in ipairs(widget:GetChildren()) do
		child:Destroy()
	end

	local palette = THEMES[Theme.detect()]

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.Position = UDim2.new(0, 0, 0, 0)
	container.BackgroundColor3 = palette.scrollBack
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Parent = widget

	local ctx = {
		plugin = pluginInstance,
		widget = widget,
		container = container,
		palette = palette,
		services = services,
		pointer = Pointer.new(widget),
		userId = 0,
		relayout = function() end,
	}
	function ctx.getPalette()
		return ctx.palette
	end

	local dialogs
	local sidebar = Sidebar.create(ctx, {
		baseTitle = baseTitle,
		onNewMessage = function(query)
			if dialogs then
				dialogs.openNewMessage(query)
			end
		end,
	})

	-- Tooltip for the badges next to names (and reactions)
	local tooltip = Tooltip.create(widget, ctx.palette)
	Author.tooltip = tooltip
	ctx.tooltip = tooltip

	-- Before the pins panel: both sit at ZIndex 15
	local suggestionFrame = Autocomplete.create(ctx.palette, container)

	local pinsPanel
	local header = Header.create({
		container = container,
		getThemeColors = ctx.getPalette,
		onPins = function()
			pinsPanel.toggle()
		end,
	})

	-- "Only you can see this chat" while the place isn't in Team Create
	local teamCreateNotice = TeamCreateNotice.create({
		container = container,
		top = Header.HEIGHT,
		getThemeColors = ctx.getPalette,
		onResize = function()
			ctx.relayout()
		end,
	})
	function ctx.topSpace(): number
		return Header.HEIGHT + teamCreateNotice.height()
	end

	local settingsButton = sidebar.list.addFooterButton("SettingsButton", "settings", Language.t("sidebar.settings"))

	local contextMenu
	local reactHandler: ((target: string | number, emoji: string) -> ())? = nil
	local pickReaction
	local feed = Feed.create(ctx, {
		showMenu = function(timestamp, options)
			contextMenu.show(timestamp, options)
		end,
		toggleReaction = function(target, emoji)
			if reactHandler then
				reactHandler(target, emoji)
			end
		end,
		addReaction = function(target)
			pickReaction(target)
		end,
	})

	contextMenu = ContextMenu.create({
		container = container,
		widget = widget,
		getThemeColors = ctx.getPalette,
	})

	local pinHandler: ((timestamp: number, pinned: boolean) -> ())? = nil
	pinsPanel = PinsPanel.create({
		container = container,
		top = Header.HEIGHT,
		getThemeColors = ctx.getPalette,
		onJump = feed.jumpTo,
		onUnpin = function(timestamp: number)
			if pinHandler then
				pinHandler(timestamp, false)
			end
		end,
		onVisibility = header.setPinsOpen,
		ignoreClicksOn = { header.pinButton },
	})

	local emojiPicker = EmojiPicker.create({
		container = container,
		widget = widget,
		getThemeColors = ctx.getPalette,
		getMousePosition = function()
			return widget:GetRelativeMousePosition()
		end,
		getScore = function(entry)
			return services.usage.getCount("emoji", entry.name)
		end,
	})
	-- A message is its saved name (MessageId) or, for rows without one, its timestamp
	function pickReaction(target: string | number)
		contextMenu.hide()
		emojiPicker.open(function(entry)
			services.usage.record("emoji", entry.name)
			if reactHandler then
				reactHandler(target, entry.emoji)
			end
		end)
	end
	contextMenu.handlers.react = function(timestamp: number, messageId: string?)
		pickReaction(messageId or timestamp)
	end

	local attachments
	local composer = Composer.create(ctx, {
		createMenuItem = contextMenu.createItem,
		contentOf = feed.contentOf,
		onCreatePoll = function()
			dialogs.openPoll()
		end,
		onAttachFiles = function()
			attachments.pick()
		end,
	})
	attachments = Attachments.create(ctx)
	local suggestions = Suggestions.create(ctx, {
		frame = suggestionFrame,
		composer = composer,
		getConversations = sidebar.entries,
	})

	function ctx.relayout()
		local composerHeight = composer.resize()
		local previewSpace = attachments.place(composerHeight)
		local bottom = composer.placeBars(composerHeight, previewSpace)
		feed.place(ctx.topSpace(), bottom)
		suggestions.place(composerHeight)
	end

	contextMenu.handlers.edit = composer.startEdit

	local toasts
	local function applyTheme(name: string)
		local colors = THEMES[name]
		ctx.palette = colors
		container.BackgroundColor3 = colors.scrollBack
		feed.recolor()
		contextMenu.recolor()
		emojiPicker.recolor()
		header.recolor()
		pinsPanel.recolor()
		teamCreateNotice.recolor()
		sidebar.recolor()
		composer.recolor()
		attachments.recolor()
		if dialogs then
			dialogs.recolor()
		end
		if toasts then
			toasts.recolor(colors)
		end
		suggestions.recolor()
		tooltip.recolor(colors)
		feed.recolorMessages()
	end

	local function notify(toast)
		toast.duration = toast.duration or Preferences.values.notificationDuration
		return toasts.show(toast)
	end

	local conversationInfo = nil
	-- DMs show the display name (or username, per Settings), the verified
	-- badge and the @username
	local function setConversation(info)
		conversationInfo = info
		local isDm = info.kind == "dm"
		local profile = if isDm and info.userId and Author.getProfile then Author.getProfile(info.userId) else nil
		local verified = profile ~= nil and profile.verified
		local shown = if isDm
			then Preferences.nameFor(info.name, profile and profile.displayName)
			else Constants.PLUGIN_TITLE
		header.setTitle(shown, {
			verified = verified,
			subtitle = if isDm and shown ~= info.name then "@" .. info.name else nil,
			icon = if isDm then "dmHeader" else "channel",
		})
		composer.setPlaceholder(
			if isDm then Language.t("composer.placeholderDm", { name = shown }) else Language.t("composer.placeholder")
		)
		feed.setEmptyState(isDm, shown, verified)
		sidebar.list.setActive(info.id)
	end

	-- Re-draws the sidebar and the header (names or verified badges changed)
	local function rerenderConversations()
		sidebar.rerender()
		if conversationInfo then
			setConversation(conversationInfo)
		end
	end

	dialogs = Dialogs.create(ctx, {
		applyTheme = applyTheme,
		refreshMessages = feed.refresh,
		notify = notify,
	})

	toasts = Toasts.create(widget, ctx.palette, { bottomOffset = INPUT_HEIGHT + 20 })

	dialogs.showStartupPopup()

	settingsButton.MouseButton1Click:Connect(dialogs.tabs.toggle)

	-- Focus moving away from the panel closes menus; open windows stay open
	widget.WindowFocusReleased:Connect(function()
		contextMenu.hide()
		suggestions.hide()
		composer.setAttachMenuOpen(false)
	end)

	-- A display name or verified flag came in: re-render everything showing
	-- it, batched per frame
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
			feed.refresh()
			rerenderConversations()
		end)
	end

	-- Bound labels follow a language change by themselves; this re-draws
	-- the text built by code
	Lifetime.add(Language.changed:Connect(function()
		settingsButton:SetAttribute("Tooltip", Language.t("sidebar.settings"))
		dialogs.retranslate()
		composer.retranslate()
		rerenderConversations()
		if not conversationInfo then
			feed.retranslateEmptyState()
			composer.setPlaceholder(Language.t("composer.placeholder"))
		end
	end))

	Lifetime.add(Preferences.changed:Connect(function(key)
		if key == "typingIndicator" then
			composer.refreshTyping()
		elseif key == "spellCheck" then
			if Preferences.values.spellCheck then
				task.spawn(SpellCheck.load)
			end
			composer.spelling.refresh()
		else
			refreshProfiles()
		end
	end))

	local visibilityCallback
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if visibilityCallback then
			visibilityCallback(widget.Enabled)
		end
	end)

	local general = dialogs.general
	local tabs = dialogs.tabs

	return {
		widget = widget,
		teamCreateNotice = teamCreateNotice,
		textBox = composer.textBox,
		sendButton = composer.sendButton,
		emojiPicker = emojiPicker,
		pinsPanel = pinsPanel,
		developerDialog = dialogs.developer,
		adminDialog = dialogs.admin,
		spelling = composer.spelling,

		-- Messages
		addMessage = feed.addMessage,
		addAnnouncementMessage = feed.addAnnouncement,
		addPollMessage = feed.addPoll,
		addFileMessage = feed.addFile,
		addSystemMessage = feed.addSystemMessage,
		addSystemEmbed = feed.addSystemEmbed,
		addBotMessage = feed.addBotMessage,
		updatePollMessage = feed.updatePoll,
		updateMessage = feed.updateMessage,
		removeMessage = function(timestamp: number)
			feed.removeMessage(timestamp)
			composer.markReplyDeleted(timestamp)
		end,
		clearChat = feed.clear,
		resetMessages = function()
			composer.reset()
			feed.reset()
		end,
		showUnreadDivider = feed.showUnreadDivider,
		tagMessage = feed.tagMessage,
		setReactions = feed.setReactions,
		setPins = function(list)
			feed.setPinned(list)
			pinsPanel.setPins(list)
		end,

		-- Message actions
		onVote = feed.onVote,
		onCreatePoll = dialogs.onCreatePoll,
		onReply = function(fn)
			contextMenu.handlers.reply = fn
		end,
		onDelete = function(fn)
			contextMenu.handlers.delete = fn
		end,
		onCopy = function(fn)
			contextMenu.handlers.copy = fn
		end,
		onPin = function(fn)
			pinHandler = fn
			contextMenu.handlers.pin = fn
		end,
		onReact = function(fn)
			reactHandler = fn
		end,

		-- Composer
		setReplyReference = composer.setReply,
		getReplyReference = composer.getReply,
		clearReplyReference = composer.clearReply,
		setCurrentUserId = function(userId: number)
			ctx.userId = userId
		end,
		getEditingMessage = composer.editingTimestamp,
		clearEditing = composer.clearReply,
		setCommandProvider = suggestions.setCommandProvider,
		isAutocompleteVisible = suggestions.isVisible,
		getPendingImage = attachments.getPendingImage,
		clearPendingImage = attachments.clearPendingImage,
		getPendingFile = attachments.getPendingFile,
		clearPendingFile = attachments.clearPendingFile,
		isUploading = attachments.isUploading,
		setTypingUsers = composer.setTypingUsers,
		onTypingActivity = composer.onTypingActivity,

		-- Conversations
		setConversation = setConversation,
		setConversations = sidebar.setConversations,
		onConversationSelected = sidebar.onSelect,
		onConversationClosed = sidebar.onClose,
		setNewMessageHandlers = dialogs.setNewMessageHandlers,

		-- The panel
		setVisible = function(visible: boolean)
			widget.Enabled = visible
		end,
		onVisibilityChanged = function(fn)
			visibilityCallback = fn
		end,
		openScript = function(script: LuaSourceContainer)
			pluginInstance:OpenScript(script)
		end,
		-- Toast notification: { title, text?, userId?, icon?, onClick? }
		notify = notify,

		-- Settings and the other dialogs
		openSettings = function(tab: string?)
			tabs.open(tab or "General")
		end,
		closeSettings = tabs.close,
		-- Toolbar button: from another tab it switches to General
		toggleSettings = function(): boolean
			local tab = tabs.current()
			if tab ~= nil and tab ~= "General" then
				tabs.open("General")
				return true
			end
			return general.toggle()
		end,
		isSettingsVisible = general.isVisible,
		onSettingsVisibilityChanged = general.onVisibilityChanged,
		-- Change or read a setting by its key, as if picked on the page
		applySetting = general.set,
		getSetting = general.get,
		getSettingControls = function()
			return general.controls
		end,
		isEnterToSendEnabled = general.isEnterToSendEnabled,
		openChangelog = function(version: string?)
			tabs.open("What's New", version)
		end,
		openBadges = function()
			tabs.open("Badges")
		end,
		openPurchase = function(item)
			dialogs.purchase.open(item)
		end,
		openAbout = function()
			tabs.open("About")
		end,

		-- Names and badges: provider(userId) -> badges / { displayName?, verified }
		setBadgeProvider = function(provider)
			Author.getBadges = provider
		end,
		setProfileProvider = function(provider)
			Author.getProfile = provider
			sidebar.list.getProfile = provider
		end,
		refreshProfiles = refreshProfiles,
		setBadgeHandlers = dialogs.setBadgeHandlers,
		-- Re-renders userId's names (their badges changed), and the Badges page when it's you
		refreshBadges = function(userId: number)
			feed.refreshBadges(userId)
			if userId == ctx.userId then
				dialogs.badges.recolor()
				dialogs.premiumChanged()
			end
		end,
	}
end

return ChatWindow
