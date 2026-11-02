--!strict
--[[
	Lifetime

	Everything that must not outlive this copy of the plugin: the root
	Janitor, plus an `alive` flag for background loops.

	The shared chat folders live in the place (see PlaceStorage), so they
	survive a plugin reload. Without cleanup, an old copy's listeners would keep
	firing on new messages with old code. App.stop() calls Lifetime.stop() on
	plugin.Unloading.

	Usage:
		Lifetime.connect(folder.ChildAdded, onChild)       -- tracked connection
		local frame = Lifetime.add(Instance.new("Frame"))   -- destroyed on unload
		Lifetime.delay(60, remind)                          -- cancelled on unload
		while Lifetime.alive do ... task.wait(1) end        -- loops stop on unload
]]

local Janitor = require(script.Parent.Parent.Util.Janitor)

local Lifetime = {}

-- False once the plugin is unloading; background loops should check it.
Lifetime.alive = true

-- Root janitor; feature janitors can be added to it.
Lifetime.janitor = Janitor.new()

--[=[
	Connects fn to signal and disconnects it when the plugin unloads.
]=]
function Lifetime.connect(signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
	return Lifetime.janitor:Connect(signal, fn)
end

--[=[
	Tracks an instance, connection, thread, callback, Janitor or Signal.
]=]
function Lifetime.add<T>(item: T): T
	return Lifetime.janitor:Add(item)
end

--[=[
	task.delay that is cancelled when the plugin unloads.
]=]
function Lifetime.delay(seconds: number, fn: () -> ()): thread
	return Lifetime.janitor:Delay(seconds, fn)
end

--[=[
	Stops background loops and releases everything tracked.
]=]
function Lifetime.stop()
	Lifetime.alive = false
	Lifetime.janitor:Cleanup()
end

return Lifetime
