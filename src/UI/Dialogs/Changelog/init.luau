--[[
	Changelog

	The "What's New" page, Minecraft-style: the MAIN versions (1.0.0, 2.0.0,
	...) are the tabs, and the selected one lists its updates (1.13.1, 1.12.4,
	...) as cards, newest first. Each card shows its version, date and title;
	click it to fold its notes open or shut (drawn by ChangelogView). Opening
	the page for a version unfolds that update. In a ModalKit modal like
	ChatUI's other dialogs.
]]

local Animation = require(script.Parent.Parent.Common.Animation)
local Changelog = require(script.Parent.Parent.Parent.Config.Changelog)
local Foundation = require(script.Parent.Parent.Common.Foundation)
local ChangelogView = require(script.UpdateView)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS
local Z = 28 -- above the poll (20+) and settings (24+) dialogs
local HEADER_HEIGHT = 44

local ChangelogDialog = {}

local function corner(gui: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = gui
end

-- "1.0.0" -> "1.0" for tab labels (main versions read like Minecraft's 1.21)
local function mainLabel(version: string): string
	local major, minor = string.match(version, "^(%d+)%.(%d+)")
	return if major then major .. "." .. minor else version
end

--[=[
	kit: a ModalKit. params: {
	  getThemeColors: () -> palette,  -- the current palette
	  onClosed: (() -> ())?,           -- e.g. remember the version as seen
	}
	Returns { open(version?), close(), isVisible(), recolor(), hasNotesFor(version), modal }
]=]
function ChangelogDialog.create(kit, params)
	local themeColors = params.getThemeColors()
	local modal =
		kit.createModal({ name = "ChangelogDialog", title = "What′s New", iconKey = "whatsNew", zIndex = Z })
	local card = modal.card
	local z = modal.contentZIndex
	modal.onClose = params.onClosed

	-- Main version tabs; the row scrolls sideways when there are many
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
	tabsRow.ZIndex = z
	tabsRow.Parent = card
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Padding = UDim.new(0, 6)
	tabsLayout.Parent = tabsRow
	tabsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		tabsRow.CanvasSize = UDim2.fromOffset(tabsLayout.AbsoluteContentSize.X, 0)
	end)

	-- The selected main version: its title and date, then its updates
	local mainInfo = Instance.new("TextLabel")
	mainInfo.Name = "MainInfo"
	mainInfo.Size = UDim2.new(1, 0, 0, 0)
	mainInfo.AutomaticSize = Enum.AutomaticSize.Y
	mainInfo.BackgroundTransparency = 1
	mainInfo.RichText = true
	mainInfo.TextWrapped = true
	mainInfo.TextXAlignment = Enum.TextXAlignment.Left
	mainInfo.FontFace = FONTS.heading
	mainInfo.TextSize = 16
	mainInfo.LayoutOrder = 3
	mainInfo.ZIndex = z
	mainInfo.Parent = card

	local updatesList = Instance.new("Frame")
	updatesList.Name = "Updates"
	updatesList.Size = UDim2.new(1, 0, 0, 0)
	updatesList.AutomaticSize = Enum.AutomaticSize.Y
	updatesList.BackgroundTransparency = 1
	updatesList.LayoutOrder = 4
	updatesList.ZIndex = z
	updatesList.Parent = card
	local updatesLayout = Instance.new("UIListLayout")
	updatesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	updatesLayout.Padding = UDim.new(0, 8)
	updatesLayout.Parent = updatesList

	local tabButtons: { TextButton } = {}
	local selectedMain = 1
	local expanded: { [string]: boolean } = {} -- update versions folded open

	-- One update as a card: a header button (version, date, title, chevron)
	-- and, when unfolded, its notes
	local function buildUpdate(update, order: number, colors)
		local isOpen = expanded[update.version] == true
		local box = Instance.new("Frame")
		box.Name = "Update_" .. tostring(update.version)
		box.Size = UDim2.new(1, 0, 0, 0)
		box.AutomaticSize = Enum.AutomaticSize.Y
		box.BackgroundColor3 = colors.dialogSecondary
		box.BorderSizePixel = 0
		box.LayoutOrder = order
		box.ZIndex = z
		box:SetAttribute("Open", isOpen)
		box.Parent = updatesList
		corner(box, 8)
		local boxLayout = Instance.new("UIListLayout")
		boxLayout.SortOrder = Enum.SortOrder.LayoutOrder
		boxLayout.Parent = box

		local header = Instance.new("TextButton")
		header.Name = "Header"
		header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
		header.BackgroundTransparency = 1
		header.Text = ""
		header.AutoButtonColor = false
		header.LayoutOrder = 1
		header.ZIndex = z + 1
		header.Parent = box

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Position = UDim2.fromOffset(14, 0)
		label.Size = UDim2.new(1, -48, 1, 0)
		label.BackgroundTransparency = 1
		label.RichText = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.FontFace = FONTS.semibold
		label.TextSize = 14
		label.TextColor3 = colors.messageText
		label.Text = string.format(
			'%s  <font size="11" color="%s">%s%s</font></font>%s',
			Icons.escape(update.version or "?"),
			Theme.toHex(colors.timestamp),
			Theme.richFont("mono"),
			Icons.escape(update.date or ""),
			if Language.pick(update.title) ~= ""
				then string.format(
					'  <font weight="regular" color="%s">%s</font>',
					Theme.toHex(colors.timestamp),
					Icons.escape(Language.pick(update.title))
				)
				else ""
		)
		label.ZIndex = z + 2
		label.Parent = header

		local chevron = Instance.new("TextLabel")
		chevron.Name = "Chevron"
		chevron.AnchorPoint = Vector2.new(1, 0.5)
		chevron.Position = UDim2.new(1, -14, 0.5, 0)
		chevron.Size = UDim2.fromOffset(16, 16)
		chevron.BackgroundTransparency = 1
		chevron.TextSize = 14
		chevron.TextColor3 = colors.timestamp
		chevron.Rotation = if isOpen then 180 else 0
		chevron.ZIndex = z + 2
		Icons.apply(chevron, "chevronDown")
		chevron.Parent = header

		if isOpen then
			local notes = Instance.new("Frame")
			notes.Name = "Notes"
			notes.Size = UDim2.new(1, 0, 0, 0)
			notes.AutomaticSize = Enum.AutomaticSize.Y
			notes.BackgroundTransparency = 1
			notes.LayoutOrder = 2
			notes.ZIndex = z + 1
			notes.Parent = box
			local notesPadding = Instance.new("UIPadding")
			notesPadding.PaddingLeft = UDim.new(0, 14)
			notesPadding.PaddingRight = UDim.new(0, 14)
			notesPadding.PaddingBottom = UDim.new(0, 14)
			notesPadding.Parent = notes
			local notesLayout = Instance.new("UIListLayout")
			notesLayout.SortOrder = Enum.SortOrder.LayoutOrder
			notesLayout.Padding = UDim.new(0, 8)
			notesLayout.Parent = notes
			-- The header already shows the version, date and title: notes only
			ChangelogView.render(notes, { changes = update.changes }, colors, z + 1)
			Animation.fadeIn(notes, "quick")
		end

		header.MouseEnter:Connect(function()
			Animation.tween(box, "quick", { BackgroundColor3 = colors.menuItemHover })
		end)
		header.MouseLeave:Connect(function()
			Animation.tween(box, "quick", { BackgroundColor3 = colors.dialogSecondary })
		end)
		return header
	end

	local render -- forward-declared: folding a card re-renders the list

	-- Highlights the selected main version and lists its updates
	function render()
		local colors = params.getThemeColors()
		for i, tab in ipairs(tabButtons) do
			local selected = i == selectedMain
			-- Roblox filter chips: the chosen one filled with the text colour
			Foundation.button(tab, colors, if selected then "subEmphasis" else "standard")
		end
		for _, child in ipairs(updatesList:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local main = Changelog[selectedMain]
		if not main then
			mainInfo.Text = ""
			return
		end
		local updates = main.updates or {}
		mainInfo.TextColor3 = colors.messageText
		mainInfo.Text = string.format(
			'%s  <font size="11" color="%s">%s%s · %s</font></font>',
			Icons.escape(
				main.title and Language.pick(main.title)
					or Language.t("whatsNew.version", { version = tostring(main.version) })
			),
			Theme.toHex(colors.timestamp),
			Theme.richFont("mono"),
			Icons.escape(main.version or ""),
			Icons.escape(Language.t(if #updates == 1 then "whatsNew.oneUpdate" else "whatsNew.updates", {
				count = #updates,
			}))
		)
		for i, update in ipairs(updates) do
			local header = buildUpdate(update, i, colors)
			header.MouseButton1Click:Connect(function()
				expanded[update.version] = not expanded[update.version]
				render()
			end)
		end
	end

	for i, main in ipairs(Changelog) do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. tostring(main.version)
		tab.Size = UDim2.fromOffset(0, 26)
		tab.AutomaticSize = Enum.AutomaticSize.X
		tab.Text = mainLabel(tostring(main.version))
		tab.FontFace = FONTS.medium
		tab.TextSize = 12
		tab.AutoButtonColor = true
		tab.BorderSizePixel = 0
		tab.LayoutOrder = i
		tab.ZIndex = z
		tab.Parent = tabsRow
		corner(tab, 999)
		local tabPadding = Instance.new("UIPadding")
		tabPadding.PaddingLeft = UDim.new(0, 12)
		tabPadding.PaddingRight = UDim.new(0, 12)
		tabPadding.Parent = tab
		tab.MouseButton1Click:Connect(function()
			selectedMain = i
			render()
			card.CanvasPosition = Vector2.zero
		end)
		table.insert(tabButtons, tab)
	end

	local self = { modal = modal } -- modal: joined into the Settings tabs

	--[=[
		Opens on the main version holding `version`, with that update unfolded
		(the newest update when the version has no notes).
	]=]
	function self.open(version: string?)
		local mainIndex, updateIndex = ChangelogView.find(Changelog, version)
		selectedMain = mainIndex or 1
		local main = Changelog[selectedMain]
		local update = main and main.updates and main.updates[updateIndex or 1]
		if update then
			expanded[update.version] = true
		end
		render()
		card.CanvasPosition = Vector2.zero
		modal.open()
		-- Scroll the tab row so the selected tab is in view
		task.defer(function()
			local tab = tabButtons[selectedMain]
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

	--[=[
		Whether an update with exactly this version has notes (only those pop up).
	]=]
	function self.hasNotesFor(version: string?): boolean
		return (ChangelogView.find(Changelog, version)) ~= nil
	end

	--[=[
		Re-applies the current palette to the tabs and notes (the shell is
		recolored by the ModalKit).
	]=]
	function self.recolor()
		tabsRow.ScrollBarImageColor3 = params.getThemeColors().scrollBar
		render()
	end

	return self
end

return ChangelogDialog
