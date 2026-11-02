--!strict
--[[
	Animation

	The plugin's animation controller: every UI animation goes through here,
	so they share timings and easing, and turning Animations off in Settings
	makes them all instant. Built on TweenService.

	Presets:
		quick  - hovers and small state changes (0.12s)
		smooth - movement and resizing (0.24s, quint out)
		pop    - things appearing: dialogs, menus, toasts (0.3s, back out)
		exit   - things leaving (0.16s, quad in)

	Usage:
		Animation.tween(frame, "smooth", { Size = UDim2.fromOffset(220, 0) })
		Animation.fadeIn(card)                       -- text, images, backgrounds 1 -> their value
		Animation.fadeOut(toast, "exit", function() toast:Destroy() end)
		Animation.popIn(card, 0.94)                  -- UIScale 0.94 -> 1
		Animation.slideIn(toast, Vector2.new(0, 16)) -- from 16px lower to its position
]]

local TweenService = game:GetService("TweenService")

local Preferences = require(script.Parent.Preferences)

export type Preset = "quick" | "smooth" | "pop" | "exit"

local Animation = {}

Animation.PRESETS = {
	quick = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	smooth = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	pop = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	exit = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
} :: { [Preset]: TweenInfo }

-- The tween running on each instance; a new tween on it cancels the old one
local running: { [Instance]: Tween } = setmetatable({}, { __mode = "k" }) :: any

-- Transparency properties fadeIn/fadeOut animate, per class
local FADE_PROPERTIES = {
	TextLabel = { "TextTransparency", "BackgroundTransparency", "TextStrokeTransparency" },
	TextButton = { "TextTransparency", "BackgroundTransparency" },
	TextBox = { "TextTransparency", "BackgroundTransparency" },
	ImageLabel = { "ImageTransparency", "BackgroundTransparency" },
	ImageButton = { "ImageTransparency", "BackgroundTransparency" },
	Frame = { "BackgroundTransparency" },
	ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	UIStroke = { "Transparency" },
}

--[=[
	Whether animations are on (Settings > Animations).
]=]
function Animation.enabled(): boolean
	return Preferences.values.animations ~= false
end

--[=[
	Tweens `props` on `instance` with a preset. With animations off (or the
	instance gone) the values are set right away. Returns the tween, if any.
]=]
function Animation.tween(instance: Instance, preset: Preset, props: { [string]: any }): Tween?
	local previous = running[instance]
	if previous then
		previous:Cancel()
		running[instance] = nil
	end
	if not Animation.enabled() or not instance.Parent then
		for key, value in pairs(props) do
			(instance :: any)[key] = value
		end
		return nil
	end
	local tween = TweenService:Create(instance, Animation.PRESETS[preset], props)
	running[instance] = tween
	tween.Completed:Connect(function()
		if running[instance] == tween then
			running[instance] = nil
		end
	end)
	tween:Play()
	return tween
end

-- Every fadeable part of gui (itself included) with its resting values
local function collect(gui: Instance): { { instance: Instance, values: { [string]: number } } }
	local parts = {}
	local function add(instance: Instance)
		local properties = FADE_PROPERTIES[instance.ClassName]
		if not properties then
			return
		end
		local values = {}
		for _, property in ipairs(properties) do
			-- Resting value: what it was before any fade started
			local stored = instance:GetAttribute("Fade_" .. property)
			values[property] = if type(stored) == "number" then stored else (instance :: any)[property]
		end
		table.insert(parts, { instance = instance, values = values })
	end
	add(gui)
	for _, descendant in ipairs(gui:GetDescendants()) do
		add(descendant)
	end
	return parts
end

--[=[
	Fades gui and everything in it in from invisible to how it looks now.
]=]
function Animation.fadeIn(gui: Instance, preset: Preset?)
	if not Animation.enabled() then
		return
	end
	for _, part in ipairs(collect(gui)) do
		local target = {}
		for property, value in pairs(part.values) do
			part.instance:SetAttribute("Fade_" .. property, value);
			(part.instance :: any)[property] = 1
			target[property] = value
		end
		local tween = Animation.tween(part.instance, preset or "smooth", target)
		local instance = part.instance
		local function clear()
			for property in pairs(target) do
				instance:SetAttribute("Fade_" .. property, nil)
			end
		end
		if tween then
			tween.Completed:Connect(clear)
		else
			clear()
		end
	end
end

--[=[
	Fades gui out, then calls `done` (e.g. to hide or destroy it) and puts
	the transparencies back so it looks right when shown again.
]=]
function Animation.fadeOut(gui: Instance, preset: Preset?, done: (() -> ())?)
	if not Animation.enabled() then
		if done then
			done()
		end
		return
	end
	local parts = collect(gui)
	local last: Tween? = nil
	for _, part in ipairs(parts) do
		local target = {}
		for property in pairs(part.values) do
			target[property] = 1
		end
		last = Animation.tween(part.instance, preset or "exit", target) or last
	end
	local function finish()
		for _, part in ipairs(parts) do
			for property, value in pairs(part.values) do
				pcall(function()
					(part.instance :: any)[property] = value
				end)
			end
		end
		if done then
			done()
		end
	end
	if last then
		task.delay(Animation.PRESETS[preset or "exit"].Time, finish)
	else
		finish()
	end
end

-- The UIScale animations use (made on first use)
local function scaleOf(gui: Instance): UIScale
	local scale = gui:FindFirstChild("AnimationScale") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "AnimationScale"
		made.Parent = gui
		scale = made
	end
	return scale :: UIScale
end

--[=[
	Grows gui from `from` (e.g. 0.94) to full size.
]=]
function Animation.popIn(gui: Instance, from: number?, preset: Preset?)
	local scale = scaleOf(gui)
	if not Animation.enabled() then
		scale.Scale = 1
		return
	end
	scale.Scale = from or 0.94
	Animation.tween(scale, preset or "pop", { Scale = 1 })
end

--[=[
	Shrinks gui towards `to` (e.g. 0.96); the caller hides it afterwards.
]=]
function Animation.popOut(gui: Instance, to: number?)
	Animation.tween(scaleOf(gui), "exit", { Scale = to or 0.96 })
end

--[=[
	Moves gui in from `offset` pixels away to its current position.
]=]
function Animation.slideIn(gui: GuiObject, offset: Vector2, preset: Preset?)
	if not Animation.enabled() then
		return
	end
	local target = gui.Position
	gui.Position = target + UDim2.fromOffset(offset.X, offset.Y)
	Animation.tween(gui, preset or "smooth", { Position = target })
end

return Animation
