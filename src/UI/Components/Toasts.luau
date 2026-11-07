--!strict
--[[
	Toasts

	Notifications that pop up at the bottom-centre of a GUI (the plugin
	panel): an avatar or icon, a
	bold title and one line of text. They slide up, stack (newest at the
	bottom, at most MAX_SHOWN), and fade away after a few seconds or when
	clicked. Animated by UI/Animation.

	Usage:
		local toasts = Toasts.create(widget, palette, { bottomOffset = 70 })
		toasts.show({ title = "builderman", text = "hey!", userId = 156, onClick = open })
		toasts.recolor(palette)
]]

local Animation = require(script.Parent.Parent.Animation)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

type Palette = { [string]: Color3 }

export type Toast = {
	title: string,
	text: string?,
	userId: number?, -- shows their headshot
	icon: string?, -- Icons key, when there's no user
	duration: number?, -- seconds (default DURATION)
	onClick: (() -> ())?,
}

local FONTS = Theme.FONTS
local WIDTH = 320
local HEIGHT = 56
local GAP = 8
local MAX_SHOWN = 3
local DURATION = 5
local Z = 70 -- above everything in the panel

local Toasts = {}

function Toasts.create(parent: Instance, palette: Palette, options: { bottomOffset: number? }?)
	local colors = palette
	local stack = Instance.new("Frame")
	stack.Name = "Toasts"
	stack.AnchorPoint = Vector2.new(0.5, 1)
	stack.Position = UDim2.new(0.5, 0, 1, -((options and options.bottomOffset) or 16))
	stack.Size = UDim2.new(0, WIDTH, 0, 0)
	stack.AutomaticSize = Enum.AutomaticSize.Y
	stack.BackgroundTransparency = 1
	stack.ZIndex = Z
	stack.Parent = parent
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(WIDTH, math.huge)
	sizeLimit.Parent = stack
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = stack

	local shown: { Frame } = {}
	local order = 0
	local self = { frame = stack }

	local function dismiss(toast: Frame)
		local index = table.find(shown, toast)
		if not index then
			return
		end
		table.remove(shown, index)
		Animation.fadeOut(toast, "exit", function()
			toast:Destroy()
		end)
	end

	--[=[
		Shows a notification. Returns its frame.
	]=]
	function self.show(toast: Toast): Frame
		order += 1
		local frame = Instance.new("TextButton")
		frame.Name = "Toast"
		frame.Text = ""
		frame.AutoButtonColor = false
		frame.Size = UDim2.new(1, 0, 0, HEIGHT)
		frame.BackgroundColor3 = colors.menuBack
		frame.BorderSizePixel = 0
		frame.LayoutOrder = order
		frame.ZIndex = Z
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Color = colors.menuBorder
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		local shadow = Instance.new("UIShadow")
		shadow.BlurRadius = UDim.new(0, 14)
		shadow.Color = Color3.new(0, 0, 0)
		shadow.Transparency = 0.5
		shadow.Parent = frame

		-- Avatar (headshot) or an icon tile
		local avatar: GuiObject
		if toast.userId and toast.userId > 0 then
			local image = Instance.new("ImageLabel")
			image.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(toast.userId) .. "&w=48&h=48"
			image.BackgroundColor3 = colors.menuItemHover
			avatar = image
		else
			local icon = Instance.new("TextLabel")
			icon.BackgroundColor3 = colors.sendButton
			icon.TextColor3 = colors.sendButtonText
			icon.TextSize = 18
			Icons.apply(icon, toast.icon or "emptyChat")
			avatar = icon
		end
		avatar.Name = "Avatar"
		avatar.AnchorPoint = Vector2.new(0, 0.5)
		avatar.Position = UDim2.new(0, 12, 0.5, 0)
		avatar.Size = UDim2.fromOffset(34, 34)
		avatar.BorderSizePixel = 0
		avatar.ZIndex = Z + 1
		avatar.Parent = frame
		local avatarCorner = Instance.new("UICorner")
		avatarCorner.CornerRadius = UDim.new(1, 0)
		avatarCorner.Parent = avatar

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Position = UDim2.fromOffset(56, 9)
		title.Size = UDim2.new(1, -68, 0, 18)
		title.BackgroundTransparency = 1
		title.FontFace = FONTS.semibold
		title.TextSize = 14
		title.TextColor3 = colors.messageText
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.Text = toast.title
		title.ZIndex = Z + 1
		title.Parent = frame

		local body = Instance.new("TextLabel")
		body.Name = "Body"
		body.Position = UDim2.fromOffset(56, 28)
		body.Size = UDim2.new(1, -68, 0, 17)
		body.BackgroundTransparency = 1
		body.FontFace = FONTS.body
		body.TextSize = 13
		body.TextColor3 = colors.timestamp
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextTruncate = Enum.TextTruncate.AtEnd
		body.Text = toast.text or ""
		body.ZIndex = Z + 1
		body.Parent = frame

		frame.MouseEnter:Connect(function()
			Animation.tween(frame, "quick", { BackgroundColor3 = colors.menuItemHover })
		end)
		frame.MouseLeave:Connect(function()
			Animation.tween(frame, "quick", { BackgroundColor3 = colors.menuBack })
		end)
		frame.MouseButton1Click:Connect(function()
			dismiss(frame)
			if toast.onClick then
				toast.onClick()
			end
		end)

		frame.Parent = stack
		table.insert(shown, frame)
		while #shown > MAX_SHOWN do
			dismiss(shown[1])
		end
		Animation.fadeIn(frame, "smooth")
		Animation.popIn(frame, 0.9, "pop")

		Lifetime.delay(toast.duration or DURATION, function()
			dismiss(frame)
		end)
		return frame :: any
	end

	function self.clear()
		for _, frame in ipairs(table.clone(shown)) do
			dismiss(frame)
		end
	end

	function self.recolor(newPalette: Palette)
		colors = newPalette
		for _, frame in ipairs(shown) do
			(frame :: any).BackgroundColor3 = colors.menuBack;
			(frame:FindFirstChild("Stroke") :: UIStroke).Color = colors.menuBorder;
			(frame:FindFirstChild("Title") :: TextLabel).TextColor3 = colors.messageText;
			(frame:FindFirstChild("Body") :: TextLabel).TextColor3 = colors.timestamp
		end
	end

	return self
end

return Toasts
