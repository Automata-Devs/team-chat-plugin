--[[
	Unit tests for the foundation modules (Util/Janitor, Util/Signal,
	Core/Settings) and the admin persistence fix. Uses a fresh copy of the
	plugin so module state doesn't leak between runs.
]]

local ServerStorage = game:GetService("ServerStorage")

return function(t)
	local copy = game.ReplicatedStorage.TeamChatPlugin:Clone()
	copy.Name = "__TeamChatFoundations"
	copy.Parent = ServerStorage
	-- This spec feeds Settings bad data on purpose; keep its expected warnings out of Output
	copy.Config.Constants.Source = string.gsub(copy.Config.Constants.Source, 'LOG_LEVEL = "%a+"', 'LOG_LEVEL = "error"')

	local ok, err = pcall(function()
		local Janitor = require(copy.Util.Janitor) :: any
		local Signal = require(copy.Util.Signal) :: any
		local Settings = require(copy.Core.Settings) :: any

		-- Janitor
		local order = {}
		local janitor = Janitor.new()
		local part = janitor:Add(Instance.new("Folder"))
		part.Parent = copy
		janitor:Add(function()
			table.insert(order, "first")
		end)
		janitor:Add(function()
			table.insert(order, "second")
		end)
		local fired = 0
		local bindable = janitor:Add(Instance.new("BindableEvent"))
		janitor:Connect(bindable.Event, function()
			fired += 1
		end)
		local timerRan = false
		janitor:Delay(0.05, function()
			timerRan = true
		end)
		bindable:Fire()
		task.wait()
		janitor:Cleanup()
		task.wait(0.1)
		t.equal("janitor releases callbacks newest first", table.concat(order, ","), "second,first")
		t.check("janitor destroys instances", part.Parent == nil)
		t.check("janitor disconnects connections", fired == 1)
		t.check("janitor cancels delayed calls", not timerRan)

		-- Signal
		local signal = Signal.new()
		local received
		local connection = signal:Connect(function(value)
			received = value
		end)
		signal:Fire(42)
		task.wait()
		t.equal("signal delivers", received, 42)
		connection:Disconnect()
		signal:Fire(7)
		task.wait()
		t.equal("disconnected handler isn't called", received, 42)

		-- Settings
		local store = {}
		Settings.init({
			GetSetting = function(_, key)
				return store[key]
			end,
			SetSetting = function(_, key, value)
				store[key] = value
			end,
		})
		t.equal("missing setting returns the default", Settings.get("nope", "fallback"), "fallback")
		Settings.setJson("json", { a = 1 })
		t.equal("json round trip", Settings.getJson("json").a, 1)
		store.bad = "{not json"
		t.equal("invalid json returns the default", Settings.getJson("bad", "default"), "default")
		Settings.init({
			GetSetting = function()
				error("settings unavailable")
			end,
			SetSetting = function()
				error("settings unavailable")
			end,
		})
		t.equal("failing GetSetting returns the default", Settings.get("x", 5), 5)
		t.equal("failing SetSetting reports false", Settings.set("x", 1), false)

		-- Admin: ranks of other users survive a save/restore (JSON makes keys strings)
		Settings.init({
			GetSetting = function(_, key)
				return store[key]
			end,
			SetSetting = function(_, key, value)
				store[key] = value
			end,
		})
		local AdminState = require(copy.Services.Admin.AdminState) :: any
		AdminState.userRanks[156] = 2
		AdminState.save()
		AdminState.userRanks = {}
		AdminState.restore()
		t.equal("rank for another user survives a reload", AdminState.userRanks[156], 2)
	end)
	copy:Destroy()
	if not ok then
		error(err, 0)
	end
end
