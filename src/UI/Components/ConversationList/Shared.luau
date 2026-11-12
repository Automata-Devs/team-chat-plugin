--[[
	Shared

	Sizes and small builders the conversation sidebar's parts share, and
	the sidebar's state they read (View).
]]

export type View = {
	list: any, -- the sidebar object: expanded, activeId, getProfile
	colors: { [string]: Color3 },
	hoveredRow: TextButton?,
	tooltip: any, -- Tooltip: show(target, text, above?), hide()
	onSelect: (id: string) -> (),
	onClose: (id: string) -> (),
}

local Shared = {}

Shared.ROW_HEIGHT = 48
Shared.AVATAR_SIZE = 40
Shared.PINNED_TOP = 8
Shared.LIST_TOP = Shared.PINNED_TOP + Shared.ROW_HEIGHT + 22

function Shared.corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

--[=[
	A transparent, left-aligned, truncating TextLabel with the given properties.
]=]
function Shared.label(name: string, parent: Instance, props): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	for key, value in pairs(props) do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

return Shared
