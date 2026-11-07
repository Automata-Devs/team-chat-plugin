--!strict
--[[
	Messages/Grouping

	Discord-style message groups: a message sent by the same person within
	seven minutes of their previous one drops its avatar and name, so a burst
	of messages reads as one block. Its time shows in the gutter while the
	mouse is over it. Every message row also gets a soft hover highlight.

	Replies, system messages, messages only you can see and anything after
	the "New" line or another kind of row (polls, announcements) start a new
	group. Regrouping runs once per frame after rows are added or removed.

	Usage:
		Grouping.attach(scrollFrame, getPalette)
]]

local Author = require(script.Parent.Author)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local TimeFormat = require(script.Parent.Parent.Parent.Util.TimeFormat)

type Palette = { [string]: Color3 }

local GROUP_SECONDS = 7 * 60
local START_PADDING = 8 -- above the first message of a group
local CONTINUE_PADDING = 0 -- above the rest
local BOTTOM_PADDING = 2
local HOVER_TRANSPARENCY = 0.5 -- the row's hover colour, half see-through

local Grouping = {}

Grouping.GROUP_SECONDS = GROUP_SECONDS

-- Whether `row` can carry on the group `previous` started
local function continues(previous: Instance?, row: Instance): boolean
	if not previous or not previous:GetAttribute("HasAuthor") then
		return false
	end
	local senderId = row:GetAttribute("SenderId")
	if type(senderId) ~= "number" or senderId <= 0 or previous:GetAttribute("SenderId") ~= senderId then
		return false
	end
	if previous:GetAttribute("Sender") ~= row:GetAttribute("Sender") then
		return false
	end
	if row:FindFirstChild("ReplyReference") or row:GetAttribute("Ephemeral") or previous:GetAttribute("Ephemeral") then
		return false
	end
	local time, previousTime = row:GetAttribute("Timestamp"), previous:GetAttribute("Timestamp")
	return type(time) == "number" and type(previousTime) == "number" and time - previousTime <= GROUP_SECONDS
end

-- The first visible piece of a row's content (its text, else its image or card)
local function firstContent(row: Instance): GuiObject?
	local best: GuiObject? = nil
	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible and child.LayoutOrder > 0 then
			if not best or child.LayoutOrder < best.LayoutOrder then
				best = child
			end
		end
	end
	return best
end

-- Shows or hides a grouped row's time in the gutter
local function showGutterTime(row: Instance, palette: Palette, shown: boolean)
	local old = row:FindFirstChild("GutterTime", true)
	if old then
		old:Destroy()
	end
	if not shown then
		return
	end
	local host = firstContent(row)
	local timestamp = row:GetAttribute("Timestamp")
	local text = if type(timestamp) == "number" then TimeFormat.formatPlain(timestamp) else ""
	if not host or text == "" then
		return
	end
	local label = Instance.new("TextLabel")
	label.Name = "GutterTime"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.fromOffset(-8, 0)
	label.Size = UDim2.fromOffset(Author.INDENT - 10, 20)
	label.FontFace = Theme.FONTS.body
	label.TextSize = 10
	label.TextColor3 = palette.timestamp
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = text
	label.ZIndex = host.ZIndex
	label.Parent = host
end

-- Groups or ungroups one row
local function setGrouped(row: Instance, grouped: boolean)
	local header = row:FindFirstChild("Author")
	if header and header:IsA("GuiObject") then
		header.Visible = not grouped
	end
	local padding = row:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingTop = UDim.new(0, if grouped then CONTINUE_PADDING else START_PADDING)
		padding.PaddingBottom = UDim.new(0, BOTTOM_PADDING)
	end
	if grouped ~= (row:GetAttribute("Grouped") == true) then
		row:SetAttribute("Grouped", if grouped then true else nil)
	end
end

--[=[
	Groups the rows in `scrollFrame` (see the top of this file).
]=]
function Grouping.apply(scrollFrame: Instance)
	local rows = {}
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.AbsolutePosition.Y < b.AbsolutePosition.Y
	end)
	local previous: Instance? = nil
	for _, row in ipairs(rows) do
		if row:GetAttribute("HasAuthor") then
			setGrouped(row, continues(previous, row))
		end
		previous = row
	end
end

-- The soft highlight under the row the mouse is on (not over the flash of a
-- jump or the gold look of a message that mentions you)
local function bindHover(row: GuiObject, getPalette: () -> Palette)
	if not row:GetAttribute("HoverHighlight") or row:GetAttribute("HoverBound") then
		return
	end
	row:SetAttribute("HoverBound", true)
	row.MouseEnter:Connect(function()
		local palette = getPalette()
		if row.BackgroundTransparency >= 1 and not row:GetAttribute("Mentioned") then
			row.BackgroundColor3 = palette.menuItemHover
			row.BackgroundTransparency = HOVER_TRANSPARENCY
			row:SetAttribute("Hovered", true)
		end
		if row:GetAttribute("Grouped") then
			showGutterTime(row, palette, true)
		end
	end)
	row.MouseLeave:Connect(function()
		if row:GetAttribute("Hovered") then
			row:SetAttribute("Hovered", nil)
			if row.BackgroundTransparency == HOVER_TRANSPARENCY then
				row.BackgroundTransparency = 1
			end
		end
		showGutterTime(row, getPalette(), false)
	end)
end

--[=[
	Keeps `scrollFrame`'s message rows grouped and gives them the hover
	highlight. Returns a function that regroups at once.
]=]
function Grouping.attach(scrollFrame: ScrollingFrame, getPalette: () -> Palette): () -> ()
	local pending = false
	local function schedule()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if scrollFrame.Parent then
				Grouping.apply(scrollFrame)
			end
		end)
	end
	scrollFrame.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			bindHover(child, getPalette)
		end
		schedule()
	end)
	scrollFrame.ChildRemoved:Connect(schedule)
	return function()
		Grouping.apply(scrollFrame)
	end
end

return Grouping
