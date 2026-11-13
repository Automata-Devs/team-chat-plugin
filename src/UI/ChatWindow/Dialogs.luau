--[[
	Dialogs

	The chat window's modal dialogs on their own layer over the whole panel
	(so the backdrop dims the sidebar too): Create a Poll, Checkout, New
	message, and the tabbed Settings window with General, Badges, Admin,
	Developer, What's New and About. After an update it opens What's New
	once; a first install opens About instead.

	Usage:
		local dialogs = Dialogs.create(ctx, hooks)
		dialogs.tabs.open("Badges")
]]

local About = require(script.Parent.Parent.Dialogs.About)
local Admin = require(script.Parent.Parent.Dialogs.Admin)
local Badges = require(script.Parent.Parent.Dialogs.Badges)
local Changelog = require(script.Parent.Parent.Dialogs.Changelog)
local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local CreatePoll = require(script.Parent.Parent.Dialogs.CreatePoll)
local Developer = require(script.Parent.Parent.Dialogs.Developer)
local General = require(script.Parent.Parent.Dialogs.Settings.General)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Messages = require(script.Parent.Parent.Messages)
local ModalKit = require(script.Parent.Parent.Dialogs.Kit.ModalKit)
local NewMessage = require(script.Parent.Parent.Dialogs.NewMessage)
local Purchase = require(script.Parent.Parent.Dialogs.Purchase)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)
local SettingsWindow = require(script.Parent.Parent.Dialogs.Settings)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local PLUGIN_VERSION = Constants.PLUGIN_VERSION

export type Hooks = {
	applyTheme: (paletteName: string) -> (),
	refreshMessages: () -> (),
	notify: (toast: { [string]: any }) -> any,
}

local Dialogs = {}

function Dialogs.create(ctx, hooks: Hooks)
	local getPalette = ctx.getPalette

	local modalLayer = Instance.new("Frame")
	modalLayer.Name = "Modals"
	modalLayer.Size = UDim2.fromScale(1, 1)
	modalLayer.BackgroundTransparency = 1
	modalLayer.Parent = ctx.widget
	local modalKit = ModalKit.new({
		container = modalLayer,
		getThemeColors = getPalette,
		isInside = ctx.pointer.isInside,
		mousePosition = ctx.pointer.mousePosition,
	})

	local pollHandler: ((string, { string }) -> ())? = nil
	local badges -- the Badges dialog (made below; Settings opens it for Premium themes)
	local badgeHandlers = nil
	local newMessageHandlers = nil

	local pollDialog = CreatePoll.create(modalKit, {
		getThemeColors = getPalette,
		maxOptions = function()
			return if badgeHandlers and badgeHandlers.pollOptions
				then badgeHandlers.pollOptions()
				else Theme.MAX_POLL_OPTIONS
		end,
		onSubmit = function(question, options)
			if pollHandler then
				pollHandler(question, options)
			end
		end,
	})

	local general = General.create(modalKit, {
		getThemeColors = getPalette,
		detectTheme = Theme.detect,
		onThemeChanged = hooks.applyTheme,
		isPremium = function()
			return badgeHandlers ~= nil and badgeHandlers.isPremium ~= nil and badgeHandlers.isPremium()
		end,
		onPremiumNeeded = function()
			hooks.notify({
				title = Language.t("premium.themeLocked"),
				text = Language.t("premium.themeLockedText"),
				icon = "badges",
			})
			if badges then
				badges.open()
			end
		end,
		onDisplayChanged = hooks.refreshMessages,
		onTextSizeChanged = function(pixels)
			Messages.setTextSize(pixels)
		end,
	})

	-- Closing What's New marks this version's notes as seen
	local changelog = Changelog.create(modalKit, {
		getThemeColors = getPalette,
		onClosed = function()
			if PLUGIN_VERSION then
				Settings.set(Constants.SETTING_KEY_LAST_SEEN_VERSION, PLUGIN_VERSION)
			end
		end,
	})

	local purchase
	badges = Badges.create(modalKit, {
		getThemeColors = getPalette,
		getHandlers = function()
			return badgeHandlers
		end,
		onBuy = function(item)
			purchase.open(item)
		end,
	})
	purchase = Purchase.create(modalKit, {
		getThemeColors = getPalette,
		getHandlers = function()
			return badgeHandlers
		end,
		onPurchased = function()
			badges.reload()
			hooks.notify({
				title = Language.t("notify.badgeUnlocked"),
				text = Language.t("notify.badgeUnlockedText"),
				icon = "badges",
			})
		end,
	})

	local about = About.create(modalKit, {
		getThemeColors = getPalette,
	})

	local function openScript(module: LuaSourceContainer)
		ctx.plugin:OpenScript(module)
	end

	local admin = Admin.create(modalKit, {
		getThemeColors = getPalette,
		services = ctx.services,
		openScript = openScript,
	})

	local developer = Developer.create(modalKit, {
		getThemeColors = getPalette,
		services = ctx.services,
		openScript = openScript,
	})

	local newMessage = NewMessage.create(modalKit, {
		getThemeColors = getPalette,
		getHandlers = function()
			return newMessageHandlers
		end,
	})

	local self = {}
	self.general = general
	self.badges = badges
	self.purchase = purchase
	self.admin = admin
	self.developer = developer
	self.tabs = nil :: any

	function self.recolor()
		modalKit.recolor()
		newMessage.recolor()
		pollDialog.recolor()
		general.recolor()
		changelog.recolor()
		badges.recolor()
		purchase.recolor()
		about.recolor()
		if self.tabs then
			self.tabs.recolor()
		end
	end

	--[=[
		Re-draws the text built by code (after a language change).
	]=]
	function self.retranslate()
		badges.recolor()
		purchase.recolor()
		changelog.recolor()
	end

	function self.openPoll()
		pollDialog.open()
	end

	function self.onCreatePoll(fn)
		pollHandler = fn
	end

	function self.openNewMessage(query: string?)
		newMessage.open(query)
	end

	--[=[
		{ getFriends, resolveUser, onPick } for the New message dialog.
	]=]
	function self.setNewMessageHandlers(handlers)
		newMessageHandlers = handlers
	end

	function self.setBadgeHandlers(handlers)
		badgeHandlers = handlers
		general.premiumChanged() -- a saved Premium theme applies once Premium is known
	end

	--[=[
		My badges changed: Premium themes apply, or stop applying.
	]=]
	function self.premiumChanged()
		general.premiumChanged()
	end

	-- The saved settings pick the theme, which is applied before the
	-- Settings window is built
	general.restore()
	hooks.applyTheme(general.resolveTheme())
	self.recolor()

	self.tabs = SettingsWindow.create({
		{
			name = "General",
			icon = "settings",
			labelKey = "tab.general",
			titleKey = "title.settings",
			group = "chat",
			dialog = general,
		},
		{
			name = "Badges",
			icon = "badges",
			labelKey = "tab.badges",
			titleKey = "title.badges",
			group = "chat",
			dialog = badges,
		},
		{
			name = "Admin",
			icon = "admin",
			labelKey = "tab.admin",
			titleKey = "title.admin",
			group = "manage",
			dialog = admin,
		},
		{
			name = "Developer",
			icon = "developer",
			labelKey = "tab.developer",
			titleKey = "title.developer",
			group = "manage",
			dialog = developer,
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
			dialog = about,
		},
	}, getPalette)

	--[=[
		Opens What's New once per version that has notes (small version bumps
		have none), or About on a first install. The panel is opened too, so
		the popup is seen.
	]=]
	function self.showStartupPopup()
		local tabs = self.tabs
		local lastSeenVersion = Settings.get(Constants.SETTING_KEY_LAST_SEEN_VERSION)
		if Settings.firstRun and Settings.get(Constants.SETTING_KEY_ABOUT_SEEN) == nil then
			Settings.set(Constants.SETTING_KEY_ABOUT_SEEN, true)
			if PLUGIN_VERSION then
				Settings.set(Constants.SETTING_KEY_LAST_SEEN_VERSION, PLUGIN_VERSION)
			end
			task.defer(function()
				ctx.widget.Enabled = true
				tabs.open("About")
			end)
		elseif PLUGIN_VERSION and changelog.hasNotesFor(PLUGIN_VERSION) and lastSeenVersion ~= PLUGIN_VERSION then
			task.defer(function()
				ctx.widget.Enabled = true
				tabs.open("What's New", PLUGIN_VERSION)
			end)
		end
	end

	return self
end

return Dialogs
