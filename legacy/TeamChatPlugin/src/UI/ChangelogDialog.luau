--!
-- ChangelogDialog
-- The "What's New" modal: version tabs (newest first, from Config.Changelog)
-- above the selected version's notes (drawn by ChangelogView), in a
-- ModalKit modal like ChatUI's other dialogs.
--!

local Theme = require(script.Parent.Parent.Config.Theme)
local Changelog = require(script.Parent.Parent.Config.Changelog)
local ChangelogView = require(script.Parent.ChangelogView)

local FONTS = Theme.FONTS
local Z = 28 -- above the poll (20+) and settings (24+) dialogs

local ChangelogDialog = {}

--!
-- kit: a ModalKit. params: {
--   getThemeColors: () -> palette,  -- the current palette
--   onClosed: (() -> ())?,           -- e.g. remember the version as seen
-- }
-- Returns { open(version?), close(), isVisible(), recolor(), hasNotesFor(version) }
--!
function ChangelogDialog.create(kit, params)
	local themeColors = params.getThemeColors()
	local modal = kit.createModal({ name = "ChangelogDialog", title = "What′s New", iconKey = "whatsNew", zIndex = Z })
	local card = modal.card
	modal.onClose = params.onClosed

	-- Version tabs; the row scrolls sideways when there are many versions
	local tabsRow = Instance.new("ScrollingFrame")
	tabsRow.Name = "Tabs"
	tabsRow.Size = UDim2.new(1, 0, 0, 34)
	tabsRow.BackgroundTransparency = 1
	tabsRow.BorderSizePixel = 0
	tabsRow.ScrollingDirection = Enum.ScrollingDirection.X
	tabsRow.HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	tabsRow.ElasticBehavior = Enum.ElasticBehavior.Never
	tabsRow.ScrollBarThickness = 3
	tabsRow.ScrollBarImageColor3 = themeColors.scrollBar
	tabsRow.LayoutOrder = 2
	tabsRow.ZIndex = Z + 2
	tabsRow.Parent = card

	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Padding = UDim.new(0, 6)
	tabsLayout.Parent = tabsRow
	tabsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		tabsRow.CanvasSize = UDim2.fromOffset(tabsLayout.AbsoluteContentSize.X, 0)
	end)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.LayoutOrder = 3
	content.ZIndex = Z + 2
	content.Parent = card

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 8)
	contentLayout.Parent = content

	local tabButtons: {TextButton} = {}
	local selectedIndex = 1

	-- Highlights the selected tab and draws its notes with the current palette
	local function render()
		local colors = params.getThemeColors()
		for i, tab in ipairs(tabButtons) do
			local selected = i == selectedIndex
			tab.BackgroundColor3 = if selected then colors.dialogButton else colors.dialogSecondary
			tab.TextColor3 = if selected then colors.dialogButtonText else (colors.menuItemText or colors.messageText)
		end
		local entry = Changelog[selectedIndex]
		if entry then
			ChangelogView.render(content, entry, colors, Z + 2)
		end
	end

	for i, entry in ipairs(Changelog) do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. tostring(entry.version)
		tab.Size = UDim2.fromOffset(0, 26)
		tab.AutomaticSize = Enum.AutomaticSize.X
		tab.Text = tostring(entry.version)
		tab.FontFace = FONTS.medium
		tab.TextSize = 12
		tab.AutoButtonColor = true
		tab.BorderSizePixel = 0
		tab.LayoutOrder = i
		tab.ZIndex = Z + 2
		tab.Parent = tabsRow

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(1, 0)
		tabCorner.Parent = tab

		local tabPadding = Instance.new("UIPadding")
		tabPadding.PaddingLeft = UDim.new(0, 10)
		tabPadding.PaddingRight = UDim.new(0, 10)
		tabPadding.Parent = tab

		tab.MouseButton1Click:Connect(function()
			selectedIndex = i
			render()
			card.CanvasPosition = Vector2.zero
		end)
		table.insert(tabButtons, tab)
	end

	local self = {}

	--!
	-- Opens on a version's tab (the newest if that version has no entry).
	--!
	function self.open(version: string?)
		selectedIndex = ChangelogView.findIndex(Changelog, version) or 1
		render()
		card.CanvasPosition = Vector2.zero
		modal.open()
		-- Scroll the tab row so the selected tab is in view
		task.defer(function()
			local tab = tabButtons[selectedIndex]
			if tab then
				local x = tab.AbsolutePosition.X - tabsRow.AbsolutePosition.X + tabsRow.CanvasPosition.X
				tabsRow.CanvasPosition = Vector2.new(math.max(0, x - 12), 0)
			end
		end)
	end

	function self.close()
		modal.close()
	end

	function self.isVisible(): boolean
		return modal.isVisible()
	end

	function self.hasNotesFor(version: string?): boolean
		return ChangelogView.findIndex(Changelog, version) ~= nil
	end

	--!
	-- Re-applies the current palette to the tabs and notes (the shell is
	-- recolored by the ModalKit).
	--!
	function self.recolor()
		tabsRow.ScrollBarImageColor3 = params.getThemeColors().scrollBar
		render()
	end

	return self
end

return ChangelogDialog
