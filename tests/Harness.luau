--[[
	Harness (tests only)

	Boots a complete copy of the plugin inside Studio's edit DataModel without
	touching the real chat: the copy stores its data in ServerStorage.__TeamChatDataTest,
	uses an in-memory plugin settings table, and shows its "dock widget" as a
	ScreenGui under CoreGui (DockWidgetPluginGuis can only be made by a real plugin).

	Usage (from the command bar or a Runner spec):
		local app = Harness.boot()
		app.chat.sendMessage("hi")
		...
		app.stop()
]]

local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TEST_DATA_FOLDER = "__TeamChatDataTest"

local Harness = {}

local function patch(module: ModuleScript, pattern: string, replacement: string, expected: number?)
	local source, count = string.gsub(module.Source, pattern, function()
		return replacement
	end)
	if expected and count ~= expected then
		error(
			("Harness: patch for %s matched %d times (expected %d): %s"):format(module.Name, count, expected, pattern),
			2
		)
	end
	module.Source = source
end

local function fakeButton()
	local click = Instance.new("BindableEvent")
	local button = { Click = click.Event, ClickableWhenViewportHidden = false, active = false, _click = click }
	function button:SetActive(active: boolean)
		self.active = active
	end
	return button
end

--[=[
	Boots a copy of ReplicatedStorage.TeamChatPlugin. Options:
	  settings: table      -- initial plugin settings (shared across boots to test persistence)
	  narrow: boolean      -- treat the panel as too narrow for the expanded sidebar (overlay)
	  keepData: boolean    -- keep the test data folder from a previous boot
	Returns { app, ui, chat, commands, gui, settings, plugin, copy, hooks, stop() }.
]=]
function Harness.boot(options: { settings: { [string]: any }?, keepData: boolean?, narrow: boolean? }?)
	local opts = options or {}
	local source = ReplicatedStorage:FindFirstChild("TeamChatPlugin")
	assert(source, "ReplicatedStorage.TeamChatPlugin missing: is Rojo (dev.project.json) connected?")

	if not opts.keepData then
		local old = ServerStorage:FindFirstChild(TEST_DATA_FOLDER)
		if old then
			old:Destroy()
		end
	end

	-- Copies left by a boot that failed partway (it never reached stop())
	for _, stale in ipairs(ServerStorage:GetChildren()) do
		if stale.Name == "__TeamChatUnderTest" then
			stale:Destroy()
		end
	end

	local copy = source:Clone()
	copy.Name = "__TeamChatUnderTest"
	copy.Parent = ServerStorage

	patch(
		copy.Config.Constants,
		'PLACE_DATA_FOLDER_NAME = "TeamChatData"',
		('PLACE_DATA_FOLDER_NAME = "%s"'):format(TEST_DATA_FOLDER),
		1
	)
	-- Only warnings and errors from test copies: no "Loaded" line per boot (the
	-- Smoke spec still sees every warning and error)
	-- (whatever level the source has: someone debugging may have set "debug")
	patch(copy.Config.Constants, 'LOG_LEVEL = "%a+"', 'LOG_LEVEL = "warn"', 1)

	-- A fake signal per widget event (hooks.events.WindowFocusReleased:Fire(), ...)
	local hooks = { events = {} :: { [string]: BindableEvent } }
	_G.__TeamChatTest = hooks
	function hooks.makeWidget()
		local gui = Instance.new("ScreenGui")
		gui.Name = "__TeamChatTestWidget"
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Global -- like DockWidgetPluginGui
		gui.Parent = CoreGui
		hooks.gui = gui
		return gui
	end

	local window = copy.UI.ChatWindow
	patch(
		window,
		'pluginInstance:CreateDockWidgetPluginGui%("TeamChatWidget", widgetInfo%)',
		"_G.__TeamChatTest.makeWidget()",
		1
	)
	for _, event in ipairs({ "PluginDragEntered", "PluginDragLeft", "PluginDragDropped", "WindowFocusReleased" }) do
		hooks.events[event] = Instance.new("BindableEvent")
		patch(window, "widget%." .. event, "_G.__TeamChatTest.events." .. event .. ".Event")
	end
	patch(window, "widget%.Title = ", "_G.__TeamChatTest.title = ")
	-- The test window is a ScreenGui: no GetRelativeMousePosition
	for _, module in ipairs({ window, window:FindFirstChild("ContextMenu"), window:FindFirstChild("Pointer") }) do
		if module then
			patch(module :: ModuleScript, "widget:GetRelativeMousePosition%(%)", "Vector2.zero")
		end
	end

	-- Expose message editing and the context menu (right-clicks can't be simulated)
	patch(
		window,
		"contextMenu%.handlers%.edit = editing%.start",
		"contextMenu.handlers.edit = editing.start; _G.__TeamChatTest.editing = editing; _G.__TeamChatTest.contextMenu = contextMenu",
		1
	)

	-- Settings buttons: record their click handlers so tests can "click" them
	-- (GuiButton clicks can't be simulated from a script).
	hooks.clicks = {}
	function hooks.onClick(button: GuiButton, handler: () -> ())
		hooks.clicks[button] = handler
		return button.MouseButton1Click:Connect(handler)
	end
	patch(
		copy.UI.Dialogs.Purchase,
		"continueButton%.MouseButton1Click:Connect%(",
		"_G.__TeamChatTest.onClick(continueButton, ",
		1
	)
	-- Autocomplete rows: pick one by number, as a click would
	patch(
		window,
		"\tlocal function renderAutocompleteItems%(%)\n",
		"\t_G.__TeamChatTest.pickAutocomplete = function(i) applyAutocompleteItem(autocompleteItems[i]) end\n\tlocal function renderAutocompleteItems()\n",
		1
	)
	-- Panel buttons (the admin dashboard, the developer portal)
	patch(
		copy.UI.Dialogs.Kit.PanelKit,
		"button%.MouseButton1Click:Connect%(onClick%)",
		"_G.__TeamChatTest.onClick(button, onClick)",
		1
	)
	-- The sidebar overlay: expose its toggle and scrim, and fake a narrow panel
	patch(
		window,
		"scrim%.MouseButton1Click:Connect%(",
		"_G.__TeamChatTest.setSidebarExpanded = setExpanded; _G.__TeamChatTest.onClick(scrim, ",
		1
	)
	if opts.narrow then
		patch(window, "local MIN_CHAT_WIDTH = 360", "local MIN_CHAT_WIDTH = 100000", 1)
	end
	-- Never open the real browser from tests: record the link instead
	patch(
		copy.Core.Browser,
		"function Browser%.open%(url: string%): boolean\n",
		"function Browser.open(url: string): boolean\n\tif _G.__TeamChatTest then _G.__TeamChatTest.opened = url return true end\n",
		1
	)

	local settings = opts.settings or {}
	if settings.TeamChatAnimations_v1 == nil then
		settings.TeamChatAnimations_v1 = false -- instant UI, so checks don't race tweens
	end
	if settings.TeamChatLanguage_v1 == nil then
		settings.TeamChatLanguage_v1 = "en" -- checks expect English, whatever Studio's language is
	end
	local toolbarButtons = {}
	local fakePlugin = {
		GetSetting = function(_, key)
			return settings[key]
		end,
		SetSetting = function(_, key, value)
			settings[key] = value
		end,
		CreateToolbar = function()
			return {
				CreateButton = function(_, name)
					local button = fakeButton()
					toolbarButtons[name] = button
					return button
				end,
			}
		end,
		StartDrag = function() end,
		OpenScript = function(_, opened)
			hooks.openedScript = opened
		end,
		Unloading = Instance.new("BindableEvent").Event,
	}

	local App = require(copy.App) :: any
	local built = App.start(fakePlugin)

	local app = {
		app = App,
		ui = built.ui,
		chat = built.chat,
		commands = built.commands,
		gui = hooks.gui,
		settings = settings,
		plugin = fakePlugin,
		toolbarButtons = toolbarButtons,
		copy = copy,
		hooks = hooks,
		dataFolder = function()
			return ServerStorage:FindFirstChild(TEST_DATA_FOLDER)
		end,
	}

	--[=[
		Changes a setting as if picked in Settings (e.g. "theme", "Light").
	]=]
	function app.setSetting(key: string, value: any)
		built.ui.applySetting(key, value)
	end

	function app.stop(keepData: boolean?)
		pcall(App.stop)
		if hooks.gui then
			hooks.gui:Destroy()
		end
		copy:Destroy()
		if not keepData then
			local data = ServerStorage:FindFirstChild(TEST_DATA_FOLDER)
			if data then
				data:Destroy()
			end
		end
		if _G.__TeamChatTest == hooks then
			_G.__TeamChatTest = nil
		end
	end

	return app
end

--[=[
	Waits a few frames so deferred signals and layout settle.
]=]
function Harness.settle(frames: number?)
	for _ = 1, frames or 4 do
		task.wait()
	end
end

return Harness
