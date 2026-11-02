--!strict
--[[
	Janitor

	Collects things that must be cleaned up together: connections, instances,
	threads, callbacks, and anything with a Destroy/Disconnect method
	(including other Janitors). Cleanup() releases them in reverse order.

	Usage:
		local janitor = Janitor.new()
		janitor:Connect(button.Activated, onClick)
		local frame = janitor:Add(Instance.new("Frame"))
		janitor:Add(function() print("bye") end)
		janitor:Cleanup()   -- disconnects, destroys, calls, cancels
]]

export type Janitor = {
	Add: <T>(self: Janitor, item: T) -> T,
	Connect: (self: Janitor, signal: RBXScriptSignal, callback: (...any) -> ()) -> RBXScriptConnection,
	Delay: (self: Janitor, seconds: number, callback: () -> ()) -> thread,
	Cleanup: (self: Janitor) -> (),
	Destroy: (self: Janitor) -> (),
	_items: { any },
	_cleaning: boolean,
}

local Janitor = {}
Janitor.__index = Janitor

--[=[
	Creates an empty Janitor.
]=]
function Janitor.new(): Janitor
	local self = setmetatable({ _items = {}, _cleaning = false }, Janitor)
	return (self :: any) :: Janitor
end

local function release(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			task.cancel(item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

--[=[
	Tracks an item and returns it, so creation and tracking fit on one line.
	Adding while Cleanup() runs releases the item immediately.
]=]
function Janitor.Add<T>(self: Janitor, item: T): T
	if self._cleaning then
		release(item)
	else
		table.insert(self._items, item)
	end
	return item
end

--[=[
	Connects a callback and tracks the connection.
]=]
function Janitor.Connect(self: Janitor, signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
	return self:Add(signal:Connect(callback))
end

--[=[
	Like task.delay, but the timer is cancelled on Cleanup().
]=]
function Janitor.Delay(self: Janitor, seconds: number, callback: () -> ()): thread
	return self:Add(task.delay(seconds, callback))
end

--[=[
	Releases every tracked item (newest first). One failing item doesn't stop
	the others. The Janitor can be reused afterwards.
]=]
function Janitor.Cleanup(self: Janitor)
	self._cleaning = true
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		local ok, err = pcall(release, items[index])
		if not ok then
			warn("[Team Chat] Cleanup error: " .. tostring(err))
		end
	end
	self._cleaning = false
end

--[=[
	Alias of Cleanup(), so a Janitor can be added to another Janitor.
]=]
function Janitor.Destroy(self: Janitor)
	self:Cleanup()
end

return Janitor
