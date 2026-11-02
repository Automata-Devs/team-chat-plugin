--!strict
--[[
	TeamCreateNotice

	A bar under the header, shown when nobody else can see this chat: the
	place isn't published or isn't in Team Create. Messages are stored in the
	place, so they only reach people editing this same place in Team Create.

	In Team Create, Studio adds everyone editing the place to Players (you
	included); in a place that isn't, Players stays empty while editing.

	Usage:
		local notice = TeamCreateNotice.create({
			container = container,
			top = Header.HEIGHT,
			getThemeColors = getTheme,
			onResize = relayout, -- the notice appeared, went away or changed height
		})
		notice.height()   -- pixels it takes up (0 while hidden)
		notice.recolor()
]]

local Players = game:GetService("Players")

local Language = require(script.Parent.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS

type Palette = { [string]: Color3 }

export type Notice = {
	frame: Frame,
	height: () -> number,
	-- Re-checks Team Create; `shared` overrides the check (tests)
	refresh: (shared: boolean?) -> (),
	recolor: () -> (),
}

local TeamCreateNotice = {}

--[=[
	Whether other people can see this place's chat: it's published and open
	in Team Create.
]=]
function TeamCreateNotice.isShared(): boolean
	return game.PlaceId ~= 0 and Players.LocalPlayer ~= nil
end

function TeamCreateNotice.create(options: {
	container: Frame,
	top: number,
	getThemeColors: () -> Palette,
	onResize: () -> (),
}): Notice
	local colors = options.getThemeColors

	local frame = Instance.new("Frame")
	frame.Name = "TeamCreateNotice"
	frame.Position = UDim2.fromOffset(0, options.top)
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 5
	frame.Parent = options.container

	-- Amber stripe on the left, like a callout
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.Size = UDim2.new(0, 3, 1, 0)
	stripe.BorderSizePixel = 0
	stripe.ZIndex = 6
	stripe.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Position = UDim2.fromOffset(13, 0)
	label.Size = UDim2.new(1, -25, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.RichText = true
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.FontFace = FONTS.body
	label.TextSize = 12
	label.ZIndex = 6
	label.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 7)
	padding.PaddingBottom = UDim.new(0, 7)
	padding.Parent = label

	local function setText()
		label.Text = string.format(
			'<font weight="bold">%s</font> %s',
			Language.t("teamCreate.title"),
			Language.t("teamCreate.text")
		)
	end

	local notice = {} :: Notice
	notice.frame = frame

	function notice.height(): number
		return if frame.Visible then frame.AbsoluteSize.Y else 0
	end

	function notice.refresh(shared: boolean?)
		local show = not (if shared == nil then TeamCreateNotice.isShared() else shared)
		if frame.Visible ~= show then
			frame.Visible = show
			options.onResize()
		end
	end

	function notice.recolor()
		local palette = colors()
		frame.BackgroundColor3 = palette.inputFrame
		stripe.BackgroundColor3 = palette.warning
		label.TextColor3 = palette.messageText
	end

	setText()
	notice.recolor()
	notice.refresh()

	Lifetime.add(Language.changed:Connect(setText))
	Lifetime.add(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if frame.Visible then
			options.onResize()
		end
	end))
	-- Joining Team Create adds you to Players; publishing sets the PlaceId
	local function recheck()
		notice.refresh()
	end
	Lifetime.add(Players.ChildAdded:Connect(recheck))
	Lifetime.add(Players.ChildRemoved:Connect(recheck))
	Lifetime.add(game:GetPropertyChangedSignal("PlaceId"):Connect(recheck))

	return notice
end

return TeamCreateNotice
