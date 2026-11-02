--!strict
--[[
	TypingBar

	The "X is typing..." line above the message box, with three dots that
	ripple like Discord's. The animation only runs while someone is typing and
	stops when the plugin unloads.

	Usage:
		local typing = TypingBar.create({ container = container, getThemeColors = getTheme })
		typing.setUsers({ "Alice" })          -- shows "Alice is typing..."
		typing.frame.Position = ...           -- placed by the composer layout
		typing.recolor()
]]

local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local RichText = require(script.Parent.Parent.Parent.Util.RichText)

local DOT_COUNT = 3
local WAVE_SPEED = 1.1 -- waves per second

type Palette = { [string]: Color3 }

export type TypingBar = {
	frame: Frame,
	setUsers: (names: { string }?) -> (),
	recolor: () -> (),
}

local TypingBar = {}

local function describe(names: { string }): string
	local count = #names
	local function bold(name: string): string
		return "<b>" .. RichText.escape(name) .. "</b>"
	end
	if count == 1 then
		return Language.t("typing.one", { name = bold(names[1]) })
	elseif count == 2 then
		return Language.t("typing.two", { first = bold(names[1]), second = bold(names[2]) })
	end
	return Language.t("typing.many")
end

--[=[
	Builds the (hidden) bar inside `options.container`.
]=]
function TypingBar.create(options: { container: Frame, getThemeColors: () -> Palette }): TypingBar
	local colors = options.getThemeColors

	local frame = Instance.new("Frame")
	frame.Name = "TypingIndicator"
	frame.Size = UDim2.new(1, -20, 0, 16)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.ZIndex = 6
	frame.BorderSizePixel = 0
	frame.Parent = options.container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 1)
	layout.Parent = frame

	local dots: { Frame } = {}
	for index = 1, DOT_COUNT do
		local holder = Instance.new("Frame")
		holder.Name = "DotHolder" .. index
		holder.Size = UDim2.fromOffset(4, 8)
		holder.BackgroundTransparency = 1
		holder.Parent = frame

		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.Size = UDim2.fromOffset(4, 4)
		dot.Position = UDim2.new(0, 0, 1, -4)
		dot.BackgroundColor3 = colors().timestamp
		dot.BorderSizePixel = 0
		dot.Parent = holder

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot

		dots[index] = dot
	end

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(0, 0, 1, 0)
	text.AutomaticSize = Enum.AutomaticSize.X
	text.BackgroundTransparency = 1
	text.FontFace = Theme.FONTS.italic
	text.TextSize = 12
	text.RichText = true
	text.TextColor3 = colors().timestamp
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.BorderSizePixel = 0
	text.Parent = frame

	local textPadding = Instance.new("UIPadding")
	textPadding.PaddingLeft = UDim.new(0, 4)
	textPadding.Parent = text

	-- Each dot follows the same sine motion, phase-shifted so the bump
	-- travels left to right.
	local wave: RBXScriptConnection? = nil
	local function startWave()
		if wave then
			return
		end
		local started = os.clock()
		wave = Lifetime.connect(RunService.Heartbeat, function()
			local elapsed = os.clock() - started
			for index, dot in ipairs(dots) do
				local phase = elapsed * math.pi * 2 * WAVE_SPEED - (index - 1) * (math.pi * 2 / DOT_COUNT)
				dot.Position = UDim2.new(0, 0, 1, -4 - 4 * (math.sin(phase) + 1) / 2)
			end
		end)
	end

	local function stopWave()
		if wave then
			wave:Disconnect()
			wave = nil
		end
		for _, dot in ipairs(dots) do
			dot.Position = UDim2.new(0, 0, 1, -4)
		end
	end

	return {
		frame = frame,
		setUsers = function(names: { string }?)
			local list = names or {}
			frame.Visible = #list > 0
			if frame.Visible then
				text.Text = describe(list)
				startWave()
			else
				stopWave()
			end
		end,
		recolor = function()
			local palette = colors()
			text.TextColor3 = palette.timestamp
			for _, dot in ipairs(dots) do
				dot.BackgroundColor3 = palette.timestamp
			end
		end,
	}
end

return TypingBar
