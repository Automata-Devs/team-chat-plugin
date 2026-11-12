--!strict
--[[
	App

	Composition root: starts the core pieces and services, builds the chat
	window and wires the controllers together. Called once by the entry script.

	Usage:
		App.start(plugin)   -- on load
		App.stop()          -- on plugin.Unloading
]]

local Constants = require(script.Parent.Config.Constants)
local Identity = require(script.Parent.Core.Identity)
local Language = require(script.Parent.Core.Language)
local Lifetime = require(script.Parent.Core.Lifetime)
local Logger = require(script.Parent.Core.Logger)
local Settings = require(script.Parent.Core.Settings)
local AdminNetwork = require(script.Parent.Services.Admin)
local ChatNetwork = require(script.Parent.Services.Chat)
local Bots = require(script.Parent.Services.Bots)
local ObjectTags = require(script.Parent.Services.ObjectTags)
local StudioCollab = require(script.Parent.Services.StudioCollab)
local Usage = require(script.Parent.Services.Usage)
local CommandRegistry = require(script.Parent.Commands.Registry)
local ChatWindow = require(script.Parent.UI.ChatWindow)
local PluginController = require(script.Parent.Controllers.PluginController)
local MessageController = require(script.Parent.Controllers.MessageController)

export type Started = {
	ui: any,
	chat: any,
	commands: any,
}

local App = {}

--[=[
	Starts the plugin: core pieces, services, then the UI and the controllers
	that connect them. Returns what it built (used by the tests).
]=]
function App.start(plugin: Plugin): Started
	Settings.init(plugin)
	-- Nothing saved yet means a first install (checked before anything saves)
	Settings.firstRun = Settings.get(Constants.SETTING_KEY_LAST_SEEN_VERSION) == nil
		and Settings.get(Constants.SETTING_KEY_ABOUT_SEEN) == nil
		and Settings.get(Constants.SETTING_KEY_ADMIN) == nil
		and Settings.get(Constants.SETTING_KEY_USAGE) == nil
		and Settings.get(Constants.SETTING_KEY_THEME) == nil
	Language.init() -- the saved language, before any UI is built
	Identity.init()

	AdminNetwork.init() -- ranks, mutes, lists
	StudioCollab.init() -- claims and camera sharing (/claim, /goto)
	Usage.init() -- command/emoji usage counts (autocomplete order)
	CommandRegistry.init() -- discovers every command module under Commands/
	ChatNetwork.init() -- chat folders, typing, conversations
	Bots.init() -- runs the bots you own; others' bots answer through requests

	-- The UI never requires Services: it gets the ones it uses here
	local ui = ChatWindow.create(plugin, {
		admin = AdminNetwork,
		bots = Bots,
		chat = ChatNetwork,
		objectTags = ObjectTags,
		usage = Usage,
	})
	PluginController.init(plugin, ui, ChatNetwork, CommandRegistry)
	MessageController.init(ui, ChatNetwork, CommandRegistry)

	Logger.info("Loaded v%s. Plugin made by @%s", Constants.PLUGIN_VERSION, Constants.PLUGIN_AUTHOR)
	return { ui = ui, chat = ChatNetwork, commands = CommandRegistry }
end

--[=[
	Tears everything down. The shared chat folders live in the place and
	outlive this copy of the plugin, so every listener must be dropped.
]=]
function App.stop()
	Lifetime.stop()
end

return App
