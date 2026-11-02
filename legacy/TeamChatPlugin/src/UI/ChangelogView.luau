--!
-- ChangelogView
-- Renders one Config.Changelog entry (version, date, optional title and its
-- changes with a colored type badge) into a container frame. Used by the
-- "What's New" modal in ChatUI.
--!

local Theme = require(script.Parent.Parent.Config.Theme)
local Icons = require(script.Parent.Parent.Config.Icons)

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

--!
-- Returns the index of the entry for a version, or nil.
--!
function ChangelogView.findIndex(changelog: {any}, version: string?): number?
	for i, entry in ipairs(changelog) do
		if entry.version == version then
			return i
		end
	end
	return nil
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

--!
-- Clears container (keeping its layout) and draws entry into it.
-- container should have a vertical UIListLayout and AutomaticSize Y.
--!
function ChangelogView.render(container: GuiObject, entry: any, themeColors: any, zIndex: number)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- "BETA-0.9.0  2026-10-31"
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

	if entry.title and entry.title ~= "" then
		textLabel({
			Name = "Title",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			Text = entry.title,
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
		local info = TYPE_INFO[change.type] or { label = string.upper(tostring(change.type or "note")), color = "timestamp" }
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
			Text = info.label,
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
			Text = change.text or "",
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
			Text = "No notes for this version.",
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
