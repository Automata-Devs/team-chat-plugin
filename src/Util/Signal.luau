--!strict
--[[
	Signal

	A small event for module-to-module notifications (no Instances needed).
	Handlers run in their own thread (task.spawn), so a slow or failing handler
	can't block the others.

	Usage:
		local changed = Signal.new()
		local connection = changed:Connect(function(value) print(value) end)
		changed:Fire(42)
		connection:Disconnect()
		changed:Destroy()   -- disconnects everything
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
	Destroy: (self: Signal) -> (),
	_handlers: { [Connection]: (...any) -> () },
}

local Signal = {}
Signal.__index = Signal

--[=[
	Creates a signal with no handlers.
]=]
function Signal.new(): Signal
	local self = setmetatable({ _handlers = {} }, Signal)
	return (self :: any) :: Signal
end

--[=[
	Adds a handler; returns a connection with Disconnect().
]=]
function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	local handlers = self._handlers
	local connection = { Connected = true } :: any
	function connection.Disconnect(conn: Connection)
		conn.Connected = false
		handlers[conn] = nil
	end
	handlers[connection] = handler
	return connection :: Connection
end

--[=[
	Calls every handler with the given arguments.
]=]
function Signal.Fire(self: Signal, ...: any)
	for connection, handler in pairs(self._handlers) do
		if connection.Connected then
			task.spawn(handler, ...)
		end
	end
end

--[=[
	Removes every handler.
]=]
function Signal.DisconnectAll(self: Signal)
	for connection in pairs(self._handlers) do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

--[=[
	Same as DisconnectAll(); lets a Janitor clean the signal up.
]=]
function Signal.Destroy(self: Signal)
	self:DisconnectAll()
end

return Signal
