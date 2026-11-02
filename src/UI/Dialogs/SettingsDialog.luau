--!
-- SettingsDialog
-- The General page of Settings, in the Roblox style: a search box, then
-- sections of setting cards (title, control on the right, description)
-- with toggles, sliders and dropdowns (UI/Components/Controls).
--
-- Settings it owns (theme, clock, timestamps, Enter to send, text size) are
-- saved in plugin settings and applied through the callbacks ChatUI passes
-- in; the display preferences (names, badges, animations, notifications...)
-- live in UI/Preferences. Everything is listed in SECTIONS below.
--!

local Controls = require(script.Parent.Parent.Components.Controls)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local PluginConfig = require(script.Parent.Parent.Parent.Config.Constants)
local Preferences = require(script.Parent.Parent.Preferences)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local TimeFormatter = require(script.Parent.Parent.Parent.Util.TimeFormat)

local FONTS = Theme.FONTS

-- Text sizes saved by older versions (named) and what they mean in pixels
local LEGACY_TEXT_SIZES = { Small = 12, Default = 14, Large = 16 }

-- Every setting on the page. kind: "toggle" | "dropdown" | "slider".
-- `own = true`: saved and applied here; otherwise it's a UI/Preferences key
-- ("language" is Core/Language). Titles and descriptions are translated:
-- "setting.<key>.title" / "setting.<key>.description" in Config/Languages,
-- section headings "section.<id>", dropdown choices OPTION_KEYS below.
local SECTIONS = {
	{
		heading = "appearance",
		items = {
			{
				key = "language",
				kind = "dropdown",
				options = {}, -- filled from Config/Languages when the page is built
			},
			{
				key = "theme",
				own = true,
				kind = "dropdown",
				options = { "Auto", "Light", "Dark" },
			},
			{
				key = "textSize",
				own = true,
				kind = "slider",
				min = 11,
				max = 20,
				step = 1,
				unit = "px",
			},
			{
				key = "names",
				kind = "dropdown",
				options = Preferences.NAME_OPTIONS,
			},
			{
				key = "clock",
				own = true,
				kind = "dropdown",
				options = { "24h", "12h" },
			},
			{
				key = "timestamps",
				own = true,
				kind = "toggle",
			},
			{
				key = "animations",
				kind = "toggle",
			},
		},
	},
	{
		heading = "chat",
		items = {
			{
				key = "enterToSend",
				own = true,
				kind = "toggle",
			},
			{
				key = "linkPreviews",
				kind = "toggle",
			},
			{
				key = "typingIndicator",
				kind = "toggle",
			},
			{
				key = "badges",
				kind = "toggle",
			},
			{
				key = "badgeTooltips",
				kind = "toggle",
			},
		},
	},
	{
		heading = "notifications",
		items = {
			{
				key = "notifications",
				kind = "dropdown",
				options = Preferences.NOTIFICATION_OPTIONS,
			},
			{
				key = "notificationDuration",
				kind = "slider",
				min = 2,
				max = 10,
				step = 1,
				unit = "s",
			},
		},
	},
}

-- Dropdown choices -> their translation keys
local OPTION_KEYS = {
	auto = "option.auto",
	Auto = "option.auto",
	Light = "option.light",
	Dark = "option.dark",
	["Display name"] = "option.displayName",
	Username = "option.username",
	["24h"] = "option.24h",
	["12h"] = "option.12h",
	All = "option.all",
	["DMs only"] = "option.dmsOnly",
	Off = "option.off",
}

-- Language choices: "auto" then every language, shown in its own name
local function languageOptions(): { string }
	local list = { Language.AUTO }
	for _, info in ipairs(Language.list()) do
		table.insert(list, info.code)
	end
	return list
end
local function optionLabel(option: string): string
	if OPTION_KEYS[option] then
		return Language.t(OPTION_KEYS[option])
	end
	for _, info in ipairs(Language.list()) do
		if info.code == option then
			return info.name
		end
	end
	return option
end

local SettingsDialog = {}

--!
-- kit: a ModalKit. opts: {
--   getThemeColors: () -> palette,
--   detectTheme: () -> "Light" | "Dark",      -- Studio's own theme
--   onThemeChanged: (paletteName) -> (),         -- apply a palette
--   onDisplayChanged: () -> (),                  -- clock/timestamps/text size changed
--   onTextSizeChanged: (pixels) -> (),           -- message text size
-- }
-- Returns { open, close, toggle, isVisible,
--           onVisibilityChanged, isEnterToSendEnabled, resolveTheme,
--           restore, recolor, set(key, value), get(key), modal }
--!
function SettingsDialog.create(kit, opts)
	local modal = kit.createModal({ name = "SettingsDialog", title = "Settings", iconKey = "settings", zIndex = 24 })
	local card = modal.card
	local z = modal.contentZIndex
	local colors = opts.getThemeColors()

	-- Values of the settings this page owns (defaults until restore())
	local own = {
		theme = "Auto",
		clock = "24h",
		timestamps = true,
		enterToSend = true,
		textSize = LEGACY_TEXT_SIZES.Default,
	}
	local OWN_KEYS = {
		theme = PluginConfig.SETTING_KEY_THEME,
		clock = PluginConfig.SETTING_KEY_CLOCK,
		timestamps = PluginConfig.SETTING_KEY_TIMESTAMPS,
		enterToSend = PluginConfig.SETTING_KEY_ENTER_TO_SEND,
		textSize = PluginConfig.SETTING_KEY_TEXT_SIZE,
	}

	local visibilityCallback: ((boolean) -> ())? = nil
	local self = { modal = modal } -- modal: joined into the Settings tabs

	local controls = {} -- [key] = control
	self.controls = controls -- by key, for tests and other code that drives the page
	local cards = {} -- { card, section }
	local headings = {} -- { label, section }

	local function get(key: string): any
		if key == "language" then
			return Language.getChoice()
		end
		if own[key] ~= nil then
			return own[key]
		end
		return (Preferences.values :: any)[key]
	end

	-- Applies an owned setting's effect
	local function applyOwn(key: string)
		if key == "theme" then
			opts.onThemeChanged(self.resolveTheme())
		elseif key == "clock" then
			TimeFormatter.setClockFormat(own.clock)
			opts.onDisplayChanged()
		elseif key == "timestamps" then
			TimeFormatter.setShowTimestamps(own.timestamps)
			opts.onDisplayChanged()
		elseif key == "textSize" then
			opts.onTextSizeChanged(own.textSize)
			opts.onDisplayChanged()
		end
	end

	--!
	-- Changes a setting as if picked on the page: saves it, applies it and
	-- moves its control. Keys are the ones in SECTIONS.
	--!
	function self.set(key: string, value: any)
		if key == "language" then
			Language.set(value) -- saved; everything re-labels
		elseif own[key] ~= nil then
			own[key] = value
			Settings.set(OWN_KEYS[key], value)
			applyOwn(key)
		else
			Preferences.set(key, value) -- saved; the chat re-renders
		end
		local control = controls[key]
		if control then
			control.set(value)
		end
	end

	function self.get(key: string): any
		return get(key)
	end

	-- Search box: filters the cards by title and description
	local search = Instance.new("Frame")
	search.Name = "Search"
	search.Size = UDim2.new(1, 0, 0, 34)
	search.BorderSizePixel = 0
	search.LayoutOrder = 2
	search.ZIndex = z
	search.Parent = card
	local searchCorner = Instance.new("UICorner")
	searchCorner.CornerRadius = UDim.new(0, 6)
	searchCorner.Parent = search
	local searchStroke = Instance.new("UIStroke")
	searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	searchStroke.Parent = search
	local searchIcon = Instance.new("TextLabel")
	searchIcon.Name = "Icon"
	searchIcon.Size = UDim2.fromOffset(32, 34)
	searchIcon.BackgroundTransparency = 1
	searchIcon.TextSize = 15
	searchIcon.ZIndex = z + 1
	Icons.apply(searchIcon, "search")
	searchIcon.Parent = search
	local searchBox = Instance.new("TextBox")
	searchBox.Name = "SearchBox"
	searchBox.Position = UDim2.fromOffset(32, 0)
	searchBox.Size = UDim2.new(1, -40, 1, 0)
	searchBox.BackgroundTransparency = 1
	searchBox.ClearTextOnFocus = false
	searchBox.FontFace = FONTS.body
	searchBox.TextSize = 13
	searchBox.Text = ""
	Language.bind(searchBox, "PlaceholderText", "settings.search")
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.ZIndex = z + 1
	searchBox.Parent = search

	local noResults = Instance.new("TextLabel")
	noResults.Name = "NoResults"
	noResults.Size = UDim2.new(1, 0, 0, 40)
	noResults.BackgroundTransparency = 1
	noResults.FontFace = FONTS.body
	noResults.TextSize = 13
	noResults.Visible = false
	noResults.LayoutOrder = 9999
	noResults.ZIndex = z
	noResults.Parent = card

	-- Sections of cards
	local order = 10
	for sectionIndex, section in ipairs(SECTIONS) do
		order += 10
		local heading = Instance.new("TextLabel")
		heading.Name = string.upper(string.sub(section.heading, 1, 1)) .. string.sub(section.heading, 2) .. "Section"
		Language.bind(heading, "Text", "section." .. section.heading, nil, string.upper)
		heading.Size = UDim2.new(1, 0, 0, 26)
		heading.BackgroundTransparency = 1
		heading.FontFace = FONTS.bold
		heading.TextSize = 12
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.TextYAlignment = Enum.TextYAlignment.Bottom
		heading.LayoutOrder = order
		heading.ZIndex = z
		heading.Parent = card
		table.insert(headings, { label = heading, section = sectionIndex })

		for _, item in ipairs(section.items) do
			order += 1
			local key = item.key
			local settingCard = Controls.card(card, {
				key = key,
				title = Language.t("setting." .. key .. ".title"),
				description = Language.t("setting." .. key .. ".description"),
				order = order,
			}, colors)
			local cardFrame = settingCard.frame
			Language.bind(cardFrame:FindFirstChild("Title", true) :: TextLabel, "Text", "setting." .. key .. ".title")
			Language.bind(
				cardFrame:FindFirstChild("Description") :: TextLabel,
				"Text",
				"setting." .. key .. ".description"
			)
			local function onChange(value: any)
				self.set(key, value)
			end
			local control
			if item.kind == "toggle" then
				control = Controls.toggle(settingCard.control, { value = get(key), onChange = onChange }, colors)
			elseif item.kind == "dropdown" then
				control = Controls.dropdown(settingCard.control, {
					options = if key == "language" then languageOptions() else item.options,
					labels = optionLabel,
					value = get(key),
					onChange = onChange,
					overlay = modal.overlay,
				}, colors)
			else
				local unit = item.unit or ""
				control = Controls.slider(settingCard.below, {
					min = item.min,
					max = item.max,
					step = item.step,
					value = get(key),
					format = function(value: number): string
						return tostring(value) .. unit
					end,
					onChange = onChange,
					overlay = modal.overlay,
					labelParent = settingCard.control,
				}, colors)
			end
			controls[key] = control
			table.insert(cards, { card = settingCard, section = sectionIndex, control = control })
		end
	end

	local function applySearch()
		local query = string.lower(searchBox.Text)
		local shownPerSection = {}
		local shown = 0
		for _, entry in ipairs(cards) do
			local text = entry.card.frame:GetAttribute("SearchText") or ""
			local match = query == "" or string.find(text, query, 1, true) ~= nil
			entry.card.frame.Visible = match
			if match then
				shownPerSection[entry.section] = true
				shown += 1
			end
		end
		for _, heading in ipairs(headings) do
			heading.label.Visible = shownPerSection[heading.section] == true
		end
		noResults.Visible = shown == 0
		noResults.Text = Language.t("settings.noResults", { query = searchBox.Text })
	end
	searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch)

	-- A new language: search matches the new words, dropdowns show new labels
	local function relabel()
		for _, entry in ipairs(cards) do
			local frame = entry.card.frame
			local key = string.gsub(frame.Name, "^Setting_", "")
			frame:SetAttribute(
				"SearchText",
				string.lower(
					Language.t("setting." .. key .. ".title") .. " " .. Language.t("setting." .. key .. ".description")
				)
			)
			entry.control.recolor(colors)
		end
		applySearch()
	end
	Lifetime.add(Language.changed:Connect(relabel))

	-- Open dropdowns close when the page scrolls or the window closes
	local function closeDropdowns()
		for _, entry in ipairs(cards) do
			if entry.control.close then
				entry.control.close()
			end
		end
	end
	card:GetPropertyChangedSignal("CanvasPosition"):Connect(closeDropdowns)

	--!
	-- The palette to use: Studio's own theme for "Auto", otherwise the choice.
	--!
	function self.resolveTheme(): string
		return if own.theme == "Auto" then opts.detectTheme() else own.theme
	end

	function self.open()
		modal.open()
		if visibilityCallback then
			visibilityCallback(true)
		end
	end

	modal.onClose = function()
		closeDropdowns()
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
	-- Opens or closes Settings (toolbar button). Returns true if it opened.
	--!
	function self.toggle(): boolean
		if modal.isVisible() then
			modal.close()
			return false
		end
		self.open()
		return true
	end

	function self.onVisibilityChanged(fn: (boolean) -> ())
		visibilityCallback = fn
	end

	function self.isEnterToSendEnabled(): boolean
		return own.enterToSend
	end

	--!
	-- Re-applies the current palette to the page (the shell is recolored by
	-- the ModalKit).
	--!
	function self.recolor()
		colors = opts.getThemeColors()
		for _, heading in ipairs(headings) do
			heading.label.TextColor3 = colors.timestamp
		end
		for _, entry in ipairs(cards) do
			entry.card.recolor(colors)
			entry.control.recolor(colors)
		end
		search.BackgroundColor3 = colors.dialogInput
		searchStroke.Color = colors.dialogBorder
		searchIcon.TextColor3 = colors.timestamp
		searchBox.TextColor3 = colors.messageText
		searchBox.PlaceholderColor3 = colors.timestamp
		noResults.TextColor3 = colors.timestamp
	end
	self.recolor()

	--!
	-- Loads the saved settings (invalid or missing values keep the defaults)
	-- and applies the non-theme ones. The caller then applies resolveTheme().
	--!
	function self.restore()
		local savedTheme = Settings.get(OWN_KEYS.theme)
		if savedTheme == "Auto" or savedTheme == "Light" or savedTheme == "Dark" then
			own.theme = savedTheme
		end
		local savedClock = Settings.get(OWN_KEYS.clock)
		if savedClock == "24h" or savedClock == "12h" then
			own.clock = savedClock
		end
		for _, key in ipairs({ "timestamps", "enterToSend" }) do
			local saved = Settings.get(OWN_KEYS[key])
			if type(saved) == "boolean" then
				own[key] = saved
			end
		end
		local savedSize = Settings.get(OWN_KEYS.textSize)
		if type(savedSize) == "number" then
			own.textSize = math.clamp(math.floor(savedSize), 11, 20)
		elseif LEGACY_TEXT_SIZES[savedSize] then
			own.textSize = LEGACY_TEXT_SIZES[savedSize]
		end
		Preferences.load()

		TimeFormatter.setClockFormat(own.clock)
		TimeFormatter.setShowTimestamps(own.timestamps)
		opts.onTextSizeChanged(own.textSize)
		for key, control in pairs(controls) do
			control.set(get(key))
		end
	end

	-- "Auto" follows Studio when its theme changes
	pcall(function()
		Lifetime.connect(settings().Studio.ThemeChanged, function()
			if own.theme == "Auto" then
				opts.onThemeChanged(self.resolveTheme())
			end
		end)
	end)

	return self
end

return SettingsDialog
