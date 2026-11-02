--!
-- TeamChatPlugin
-- A Studio plugin that enables real-time chat between developers
-- working on the same place via Team Create.
--!

-- Guard: ensure we're running as a plugin
if not plugin then
	warn("[TeamChatPlugin] This script must be run as a plugin (no `plugin` global available).")
	return
end

-- Module references
local src = script.src
local AdminNetwork = require(src.Networking.AdminNetwork)
local ChatNetwork = require(src.Networking.ChatNetwork)
local ChatUI = require(src.UI.ChatUI)
local CommandHandler = require(src.Commands.CommandHandler)
local UsageTracker = require(src.Utils.UsageTracker)
local PluginController = require(src.Core.PluginController)
local MessageController = require(src.Core.MessageController)
local Lifetime = require(src.Core.Lifetime)

-- The shared chat folders live in the place and outlive this copy of the
-- plugin, so drop our listeners when Studio unloads/reloads it.
plugin.Unloading:Connect(Lifetime.stop)

-- Initialize admin system (ranks, blacklists, whitelists, etc.)
AdminNetwork.init(plugin)

-- Load saved command/emoji usage counts (drives autocomplete ordering)
UsageTracker.init(plugin)

-- Initialize command handler (auto-discovers all commands in src/Commands)
CommandHandler.init()

-- Initialize networking and load message history
local history = ChatNetwork.init(plugin)

-- Create the dock widget UI
local ui = ChatUI.create(plugin)

-- Wire up plugin UI: toolbar, widget toggle, history loading, and ChatNetwork <-> ChatUI events
PluginController.init(plugin, ui, history, ChatNetwork, CommandHandler)

-- Wire up message sending, command parsing, and keyboard input handling
MessageController.init(ui, ChatNetwork, CommandHandler)

print("Team chat plugin loaded successfully! Plugin made by @" .. ChatNetwork.getPluginAuthor())