--!
-- Lifetime
-- Tracks connections that must not outlive this copy of the plugin.
--
-- The shared folders live in the place (ServerStorage, see PlaceStorage), so
-- they survive a plugin reload. Without cleanup, an old copy's listeners keep
-- firing on new messages with old code. Connect through Lifetime.connect
-- and the main script calls Lifetime.stop() on plugin.Unloading.
--!

local Lifetime = {}

-- False once the plugin is unloading; background loops should check it.
Lifetime.alive = true

local connections: {RBXScriptConnection} = {}

--!
-- Connects fn to signal and disconnects it when the plugin unloads.
--!
function Lifetime.connect(signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
	local connection = signal:Connect(fn)
	table.insert(connections, connection)
	return connection
end

--!
-- Disconnects every tracked connection and stops background loops.
--!
function Lifetime.stop()
	Lifetime.alive = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

return Lifetime
