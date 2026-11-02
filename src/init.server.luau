--!strict
--[[
	Team Chat (plugin entry point)

	The only Script in the plugin. It starts the app and stops it when Studio
	unloads the plugin; everything else lives in ModuleScripts (see App).
]]

if not plugin then
	warn("[Team Chat] This script only runs as a Roblox Studio plugin.")
	return
end

local App = require(script.App)

App.start(plugin)
plugin.Unloading:Connect(App.stop)
