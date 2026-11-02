--!
-- SettingsDialog
-- The Settings modal: theme (Auto follows Studio's theme), clock format,
-- timestamps, Enter-to-send and message text size. Choices are saved in
-- plugin settings for this user and restored on load (restore()). ChatUI is
-- told about changes through the callbacks it passes in and applies them.
--!

local Theme = require(script.Parent.Parent.Config.Theme)
local PluginConfig = require(script.Parent.Parent.Config.PluginConfig)
local TimeFormatter = require(script.Parent.Parent.Utils.TimeFormatter)
local Lifetime = require(script.Parent.Parent.Core.Lifetime)

local FONTS = Theme.FONTS

local THEME_OPTIONS = { "Auto", "Light", "Dark" }
local TEXT_SIZE_OPTIONS = { "Small", "Default", "Large" }
-- A Settings close caused by focus loss within this time (e.g. by clicking
-- the toolbar's Settings button) makes toggle() not reopen it
local FOCUS_CLOSE_GRACE = 0.5 -- seconds

local SettingsDialog = {}

--!
-- kit: a ModalKit. opts: {
--   pluginInstance: Plugin,
--   getThemeColors: () -> palette,
--   detectTheme: () -> "Light" | "Dark",      -- Studio's own theme
--   onThemeChanged: (paletteName) -> (),         -- apply a palette
--   onDisplayChanged: () -> (),                  -- clock/timestamps/text size changed
--   onTextSizeChanged: (sizeName) -> (),         -- "Small" | "Default" | "Large"
-- }
-- Returns { open, close, toggle, isVisible, closeFromFocusLoss,
--           onVisibilityChanged, isEnterToSendEnabled, resolveTheme,
--           restore, recolor }
--!
function SettingsDialog.create(kit, opts)
	local modal = kit.createModal({ name = "SettingsDialog", title = "Settings", iconKey = "settings", zIndex = 24 })
	local card = modal.card
	local z = modal.contentZIndex

	-- Preferences (defaults until restore() loads the saved ones)
	local themePreference = "Auto"
	local clockPreference = "24h"
	local showTimestampsPreference = true
	local enterToSendPreference = true
	local textSizePreference = "Default"

	local visibilityCallback: ((boolean) -> ())? = nil
	local closedByFocusAt = 0
	local headings: {TextLabel} = {}
	local optionRows = {} -- { buttons = { [optionName] = TextButton }, isSelected = (optionName) -> boolean }

	local function loadSetting(key: string): any
		local ok, value = pcall(function()
			return opts.pluginInstance:GetSetting(key)
		end)
		return if ok then value else nil
	end

	local function saveSetting(key: string, value: any)
		pcall(function()
			opts.pluginInstance:SetSetting(key, value)
		end)
	end

	--!
	-- Adds a "HEADING" label and a row of option buttons to the card.
	-- isSelected(optionName) decides which button is highlighted.
	--!
	local function createOptionRow(name: string, headingText: string, order: number, optionNames: {string}, isSelected: (string) -> boolean)
		local colors = opts.getThemeColors()

		local heading = Instance.new("TextLabel")
		heading.Name = name .. "Heading"
		heading.Size = UDim2.new(1, 0, 0, 18)
		heading.BackgroundTransparency = 1
		heading.Text = string.upper(headingText)
		heading.TextColor3 = colors.messageText
		heading.FontFace = FONTS.bold
		heading.TextSize = 12
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.LayoutOrder = order
		heading.ZIndex = z
		heading.BorderSizePixel = 0
		heading.Parent = card
		table.insert(headings, heading)

		local row = Instance.new("Frame")
		row.Name = name .. "ButtonsRow"
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order + 1
		row.ZIndex = z
		row.Parent = card

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.Parent = row

		local buttons = {}
		for i, optionName in ipairs(optionNames) do
			local btn = Instance.new("TextButton")
			btn.Name = if name == "Theme" then "Theme" .. optionName else "Option_" .. optionName
			btn.Size = UDim2.new(1 / #optionNames, -6, 1, 0)
			btn.BackgroundColor3 = colors.dialogSecondary
			btn.Text = optionName
			btn.TextColor3 = colors.menuItemText or colors.messageText
			btn.FontFace = FONTS.medium
			btn.TextSize = 13
			btn.AutoButtonColor = true
			btn.BorderSizePixel = 0
			btn.LayoutOrder = i
			btn.ZIndex = z + 1
			btn.Parent = row

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 6)
			btnCorner.Parent = btn

			buttons[optionName] = btn
		end

		local entry = { buttons = buttons, isSelected = isSelected }
		table.insert(optionRows, entry)
		return entry
	end

	-- Highlights the selected button of every row
	local function refreshOptionRows()
		local colors = opts.getThemeColors()
		for _, entry in ipairs(optionRows) do
			for optionName, btn in pairs(entry.buttons) do
				if entry.isSelected(optionName) then
					btn.BackgroundColor3 = colors.dialogButton
					btn.TextColor3 = colors.dialogButtonText
				else
					btn.BackgroundColor3 = colors.dialogSecondary
					btn.TextColor3 = colors.menuItemText or colors.messageText
				end
			end
		end
	end

	local themeRow = createOptionRow("Theme", "Theme", 2, THEME_OPTIONS, function(optionName)
		return optionName == themePreference
	end)
	local clockRow = createOptionRow("Clock Format", "Clock Format", 4, { "24h", "12h" }, function(optionName)
		return optionName == clockPreference
	end)
	local timestampsRow = createOptionRow("Timestamps", "Timestamps", 6, { "Show", "Hide" }, function(optionName)
		return (optionName == "Show") == showTimestampsPreference
	end)
	local sendRow = createOptionRow("Send Messages", "Send Messages", 8, { "Enter to Send", "Button Only" }, function(optionName)
		return (optionName == "Enter to Send") == enterToSendPreference
	end)
	local textSizeRow = createOptionRow("Text Size", "Text Size", 10, TEXT_SIZE_OPTIONS, function(optionName)
		return optionName == textSizePreference
	end)

	local self = {}

	--!
	-- The palette to use: Studio's own theme for "Auto", otherwise the choice.
	--!
	function self.resolveTheme(): string
		return if themePreference == "Auto" then opts.detectTheme() else themePreference
	end

	function self.open()
		modal.open()
		if visibilityCallback then
			visibilityCallback(true)
		end
	end

	modal.onClose = function()
		if visibilityCallback then
			visibilityCallback(false)
		end
	end

	function self.close()
		modal.close()
	end

	function self.isVisible(): boolean
		return modal.isVisible()
	end

	--!
	-- Closes Settings because focus left the chat panel, and remembers when,
	-- so the click that caused it (e.g. the toolbar button) doesn't reopen it.
	--!
	function self.closeFromFocusLoss()
		if modal.isVisible() then
			closedByFocusAt = os.clock()
			modal.close()
		end
	end

	--!
	-- Opens or closes Settings (toolbar button). Returns true if it opened.
	--!
	function self.toggle(): boolean
		if modal.isVisible() then
			modal.close()
			return false
		end
		if os.clock() - closedByFocusAt < FOCUS_CLOSE_GRACE then
			return false -- this click already closed it via focus loss
		end
		self.open()
		return true
	end

	function self.onVisibilityChanged(fn: (boolean) -> ())
		visibilityCallback = fn
	end

	function self.isEnterToSendEnabled(): boolean
		return enterToSendPreference
	end

	--!
	-- Re-applies the current palette to the dialog's content (the shell is
	-- recolored by the ModalKit).
	--!
	function self.recolor()
		local colors = opts.getThemeColors()
		for _, heading in ipairs(headings) do
			heading.TextColor3 = colors.messageText
		end
		refreshOptionRows()
	end

	--!
	-- Loads the saved preferences (invalid or missing values keep the
	-- defaults) and applies the non-theme ones. The caller then applies
	-- resolveTheme().
	--!
	function self.restore()
		local savedTheme = loadSetting(PluginConfig.SETTING_KEY_THEME)
		if table.find(THEME_OPTIONS, savedTheme) then
			themePreference = savedTheme
		end
		local savedClock = loadSetting(PluginConfig.SETTING_KEY_CLOCK)
		if savedClock == "24h" or savedClock == "12h" then
			clockPreference = savedClock
		end
		local savedTimestamps = loadSetting(PluginConfig.SETTING_KEY_TIMESTAMPS)
		if type(savedTimestamps) == "boolean" then
			showTimestampsPreference = savedTimestamps
		end
		local savedEnterToSend = loadSetting(PluginConfig.SETTING_KEY_ENTER_TO_SEND)
		if type(savedEnterToSend) == "boolean" then
			enterToSendPreference = savedEnterToSend
		end
		local savedTextSize = loadSetting(PluginConfig.SETTING_KEY_TEXT_SIZE)
		if table.find(TEXT_SIZE_OPTIONS, savedTextSize) then
			textSizePreference = savedTextSize
		end

		TimeFormatter.setClockFormat(clockPreference)
		TimeFormatter.setShowTimestamps(showTimestampsPreference)
		opts.onTextSizeChanged(textSizePreference)
		refreshOptionRows()
	end

	-- Option clicks: update the preference, save it, apply it, re-highlight
	local function onOptionClicked(entry, handler: (string) -> ())
		for optionName, btn in pairs(entry.buttons) do
			btn.MouseButton1Click:Connect(function()
				handler(optionName)
				refreshOptionRows()
			end)
		end
	end

	onOptionClicked(themeRow, function(optionName)
		themePreference = optionName
		saveSetting(PluginConfig.SETTING_KEY_THEME, optionName)
		opts.onThemeChanged(self.resolveTheme())
	end)
	onOptionClicked(clockRow, function(optionName)
		clockPreference = optionName
		TimeFormatter.setClockFormat(optionName)
		saveSetting(PluginConfig.SETTING_KEY_CLOCK, optionName)
		opts.onDisplayChanged()
	end)
	onOptionClicked(timestampsRow, function(optionName)
		showTimestampsPreference = optionName == "Show"
		TimeFormatter.setShowTimestamps(showTimestampsPreference)
		saveSetting(PluginConfig.SETTING_KEY_TIMESTAMPS, showTimestampsPreference)
		opts.onDisplayChanged()
	end)
	onOptionClicked(sendRow, function(optionName)
		enterToSendPreference = optionName == "Enter to Send"
		saveSetting(PluginConfig.SETTING_KEY_ENTER_TO_SEND, enterToSendPreference)
	end)
	onOptionClicked(textSizeRow, function(optionName)
		textSizePreference = optionName
		saveSetting(PluginConfig.SETTING_KEY_TEXT_SIZE, optionName)
		opts.onTextSizeChanged(optionName)
		opts.onDisplayChanged()
	end)

	-- "Auto" follows Studio when its theme changes
	pcall(function()
		Lifetime.connect(settings().Studio.ThemeChanged, function()
			if themePreference == "Auto" then
				opts.onThemeChanged(self.resolveTheme())
			end
		end)
	end)

	return self
end

return SettingsDialog
