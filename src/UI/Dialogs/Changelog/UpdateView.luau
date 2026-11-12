--[[
	UpdateView

	Renders one Config.Changelog update (version, date, optional title and its
	changes with a colored type badge) into a container frame, and finds a
	version among the main versions' updates. Used by the "What's New" page.
]]

local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local Theme = require(script.Parent.Parent.Parent.Parent.Config.Theme)
local Icons = require(script.Parent.Parent.Parent.Parent.Config.Icons)

local FONTS = Theme.FONTS

local ChangelogView = {}

-- Change types in display order (Keep a Changelog); color = palette key
ChangelogView.TYPES = {
	{ key = "added", label = "ADDED", color = "success" },
	{ key = "changed", label = "CHANGED", color = "sendButton" },
	{ key = "fixed", label = "FIXED", color = "warning" },
	{ key = "removed", label = "REMOVED", color = "danger" },
}

local BADGE_WIDTH = 64
local TYPE_ORDER = {}
local TYPE_INFO = {}
for i, info in ipairs(ChangelogView.TYPES) do
	TYPE_ORDER[info.key] = i
	TYPE_INFO[info.key] = info
end

--[=[
	Finds a version in the changelog (main versions holding their `updates`):
	returns the main version's index and the update's index, or nil.
]=]
function ChangelogView.find(changelog: { any }, version: string?): (number?, number?)
	for mainIndex, main in ipairs(changelog) do
		for subIndex, update in ipairs(main.updates or {}) do
			if update.version == version then
				return mainIndex, subIndex
			end
		end
	end
	return nil, nil
end

local function textLabel(props): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	for key, value in pairs(props) do
		label[key] = value
	end
	return label
end

--[=[
	Clears container (keeping its layout) and draws entry into it.
	container should have a vertical UIListLayout and AutomaticSize Y.
]=]
function ChangelogView.render(container: GuiObject, entry: any, themeColors: any, zIndex: number)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- "1.13.1  01/11/2026" (left out when the caller shows it, e.g. a card header)
	if entry.version then
		textLabel({
			Name = "Version",
			Size = UDim2.new(1, 0, 0, 20),
			RichText = true,
			Text = string.format(
				'%s  <font size="11" color="%s">%s%s</font></font>',
				Icons.escape(entry.version or "?"),
				Theme.toHex(themeColors.timestamp),
				Theme.richFont("mono"),
				Icons.escape(entry.date or "")
			),
			FontFace = FONTS.heading,
			TextSize = 15,
			TextColor3 = themeColors.messageText,
			LayoutOrder = 1,
			ZIndex = zIndex,
			Parent = container,
		})
	end

	local title = Language.pick(entry.title)
	if title ~= "" then
		textLabel({
			Name = "Title",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			Text = title,
			FontFace = FONTS.semibold,
			TextSize = 13,
			TextColor3 = themeColors.timestamp,
			LayoutOrder = 2,
			ZIndex = zIndex,
			Parent = container,
		})
	end

	-- Changes, grouped by type (keeping the written order within a type)
	local changes = {}
	for i, change in ipairs(entry.changes or {}) do
		table.insert(changes, { change = change, order = i })
	end
	table.sort(changes, function(a, b)
		local ta, tb = TYPE_ORDER[a.change.type] or 99, TYPE_ORDER[b.change.type] or 99
		if ta ~= tb then
			return ta < tb
		end
		return a.order < b.order
	end)

	for i, item in ipairs(changes) do
		local change = item.change
		local info = TYPE_INFO[change.type]
			or { label = string.upper(tostring(change.type or "note")), color = "timestamp" }
		local typeLabel = string.upper(Language.tOr("changeType." .. tostring(change.type), info.label))
		local color = themeColors[info.color] or themeColors.timestamp

		local row = Instance.new("Frame")
		row.Name = "Change" .. i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = 10 + i
		row.ZIndex = zIndex
		row.Parent = container

		local badge = textLabel({
			Name = "Badge",
			Size = UDim2.fromOffset(BADGE_WIDTH, 18),
			BackgroundTransparency = 0.82,
			BackgroundColor3 = color,
			Text = typeLabel,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			FontFace = FONTS.bold,
			TextSize = 10,
			TextColor3 = color,
			ZIndex = zIndex,
			Parent = row,
		})
		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(1, 0)
		badgeCorner.Parent = badge

		textLabel({
			Name = "Text",
			Position = UDim2.fromOffset(BADGE_WIDTH + 8, 1),
			Size = UDim2.new(1, -(BADGE_WIDTH + 8), 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			Text = Language.pick(change.text),
			FontFace = FONTS.body,
			TextSize = 13,
			TextColor3 = themeColors.messageText,
			ZIndex = zIndex,
			Parent = row,
		})
	end

	if #changes == 0 then
		textLabel({
			Name = "Empty",
			Size = UDim2.new(1, 0, 0, 18),
			Text = Language.t("whatsNew.noNotes"),
			FontFace = FONTS.italic,
			TextSize = 13,
			TextColor3 = themeColors.timestamp,
			LayoutOrder = 10,
			ZIndex = zIndex,
			Parent = container,
		})
	end
end

return ChangelogView
