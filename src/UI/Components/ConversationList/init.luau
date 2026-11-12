--[[
	ConversationList

	The Discord-style sidebar on the left of the chat: the place's team chat
	pinned at the top (game icon), then a direct message per collaborator
	(Row). Collapsed it's an icon rail with a name tooltip on hover;
	expanded it also shows names, the latest message and a search. The +
	above the DMs starts a new message; the footer holds buttons and the
	expand/collapse toggle (Footer).

	Usage:
		local list = ConversationList.create(palette, widget, onSelect, onToggle, onNewMessage, onClose)
		list.update(entries, activeId)
		list.setExpanded(true)
]]

local Animation = require(script.Parent.Parent.Common.Animation)
local Footer = require(script.Footer)
local Foundation = require(script.Parent.Parent.Common.Foundation)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Row = require(script.Row)
local Shared = require(script.Shared)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local Tooltip = require(script.Tooltip)

local FONTS = Theme.FONTS
local ROW_HEIGHT = Shared.ROW_HEIGHT
local AVATAR_SIZE = Shared.AVATAR_SIZE
local PINNED_TOP = Shared.PINNED_TOP
local corner = Shared.corner
local newLabel = Shared.label

local ConversationList = {}

ConversationList.COLLAPSED_WIDTH = 64
ConversationList.EXPANDED_WIDTH = 220
-- Added to every sidebar ZIndex while it lies over the chat (setOverlay): the
-- widget uses Global ZIndexBehavior, so the sidebar must out-rank the chat's
-- content (up to 15) but stay under dialogs (20+). Its own ZIndexes go to 4.
ConversationList.OVERLAY_Z_OFFSET = 15

--[=[
	Creates the sidebar in parent (the widget).
	onSelect(id): a conversation was clicked. onToggle(expanded): the toggle
	was clicked. onNewMessage(query?): the + was clicked, with the search
	text when searching. onClose(id): a DM's × was clicked.
]=]
function ConversationList.create(
	themeColors,
	parent: Instance,
	onSelect: (string) -> (),
	onToggle: (boolean) -> (),
	onNewMessage: (query: string?) -> (),
	onClose: (string) -> ()
)
	local self = { expanded = false, rows = {}, activeId = nil, entries = {} }
	local view: Shared.View = {
		list = self,
		colors = themeColors,
		hoveredRow = nil,
		tooltip = nil,
		onSelect = onSelect,
		onClose = onClose,
	}
	local colors = themeColors

	local frame = Instance.new("Frame")
	frame.Name = "Sidebar"
	frame.Size = UDim2.new(0, ConversationList.COLLAPSED_WIDTH, 1, 0)
	frame.BackgroundColor3 = colors.inputFrame
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = parent
	self.frame = frame

	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(1, 0)
	edge.Position = UDim2.fromScale(1, 0)
	edge.Size = UDim2.new(0, 1, 1, 0)
	edge.BackgroundColor3 = colors.divider
	edge.BorderSizePixel = 0
	edge.ZIndex = 4 -- the widget uses Global ZIndexBehavior: above every row
	edge.Parent = frame

	-- The pinned team chat goes here (its row is made on the first update)
	local pinnedHolder = Instance.new("Frame")
	pinnedHolder.Name = "Pinned"
	pinnedHolder.Position = UDim2.fromOffset(0, PINNED_TOP)
	pinnedHolder.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	pinnedHolder.BackgroundTransparency = 1
	pinnedHolder.Parent = frame

	-- A short divider on the rail, a section title when expanded
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.AnchorPoint = Vector2.new(0.5, 0)
	separator.Position = UDim2.new(0.5, 0, 0, PINNED_TOP + ROW_HEIGHT + 9)
	separator.Size = UDim2.fromOffset(32, 2)
	separator.BackgroundColor3 = colors.divider
	separator.BorderSizePixel = 0
	separator.Parent = frame
	corner(separator, UDim.new(1, 0))

	local sectionTitle = newLabel("SectionTitle", frame, {
		Position = UDim2.fromOffset(14, PINNED_TOP + ROW_HEIGHT + 4),
		Size = UDim2.new(1, -28, 0, 14),
		FontFace = FONTS.bold,
		TextSize = 12,
		TextColor3 = colors.timestamp,
		Visible = false,
	})
	Language.bind(sectionTitle, "Text", "sidebar.directMessages")

	local list = Instance.new("ScrollingFrame")
	list.Name = "DirectMessages"
	list.Position = UDim2.fromOffset(0, Shared.LIST_TOP)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = frame
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list

	-- Search (expanded only): filters the DMs, and turns "New message" into
	-- "Search friends for ..."
	local searchHolder = Instance.new("Frame")
	searchHolder.Name = "SearchHolder"
	searchHolder.BackgroundTransparency = 1
	searchHolder.Size = UDim2.new(1, 0, 0, 34)
	searchHolder.LayoutOrder = -1
	searchHolder.Visible = false
	searchHolder.Parent = list
	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.Position = UDim2.fromOffset(12, 3)
	search.Size = UDim2.new(1, -24, 0, 28)
	Foundation.input(search, colors)
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.FontFace = FONTS.body
	search.TextSize = 13
	search.TextColor3 = colors.messageText
	search.PlaceholderColor3 = colors.placeholder
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.TextTruncate = Enum.TextTruncate.AtEnd
	search.Text = ""
	search.Parent = searchHolder
	corner(search, UDim.new(0, 8))
	local searchPadding = Instance.new("UIPadding")
	searchPadding.PaddingLeft = UDim.new(0, 30)
	searchPadding.PaddingRight = UDim.new(0, 10)
	searchPadding.Parent = search
	local searchIcon = newLabel("Icon", search, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -22, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		TextColor3 = colors.placeholder,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	Icons.apply(searchIcon, "search")
	Language.bind(search, "PlaceholderText", "sidebar.search")
	self.search = search

	-- New message: a round + on the rail, a "New message" row when expanded
	local newMessage = Instance.new("TextButton")
	newMessage.Name = "NewMessage"
	newMessage.Text = ""
	newMessage.AutoButtonColor = false
	newMessage.BorderSizePixel = 0
	newMessage.BackgroundColor3 = colors.menuItemHover
	newMessage.BackgroundTransparency = 1
	newMessage.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
	newMessage.LayoutOrder = 0
	corner(newMessage, UDim.new(0, 8))
	local newMessageHolder = Instance.new("Frame")
	newMessageHolder.Name = "NewMessageHolder"
	newMessageHolder.BackgroundTransparency = 1
	newMessageHolder.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	newMessageHolder.LayoutOrder = 0
	newMessageHolder.Parent = list
	newMessage.Position = UDim2.fromOffset(6, 0)
	newMessage.Parent = newMessageHolder

	local newMessageCircle = newLabel("Circle", newMessage, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE),
		BackgroundTransparency = 0,
		BackgroundColor3 = colors.menuItemHover,
		TextColor3 = colors.sendButton,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	Icons.apply(newMessageCircle, "newMessage")
	corner(newMessageCircle, UDim.new(1, 0))
	local newMessageLabel = newLabel("NameLabel", newMessage, {
		Position = UDim2.fromOffset(AVATAR_SIZE + 16, 0),
		Size = UDim2.new(1, -(AVATAR_SIZE + 22), 1, 0),
		FontFace = FONTS.semibold,
		TextSize = 14,
		TextColor3 = colors.menuItemText,
		Visible = false,
	})
	Language.bind(newMessageLabel, "Text", "sidebar.newMessage")

	local emptyHint = newLabel("EmptyHint", list, {
		Size = UDim2.new(1, -24, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		FontFace = FONTS.body,
		TextSize = 12,
		TextColor3 = colors.timestamp,
		LayoutOrder = 100000,
		Visible = false,
	})
	Language.bind(emptyHint, "Text", "sidebar.emptyHint")
	local hintPadding = Instance.new("UIPadding")
	hintPadding.PaddingLeft = UDim.new(0, 14)
	hintPadding.Parent = emptyHint

	local footer = Footer.create(view, frame, list)
	local tooltip = Tooltip.create(view, parent, frame)
	view.tooltip = tooltip
	self.addFooterButton = footer.addButton
	footer.addToggle(onToggle)

	newMessage.MouseEnter:Connect(function()
		newMessage.BackgroundTransparency = if self.expanded then 0.5 else 1
		newMessageCircle.BackgroundColor3 = view.colors.sendButton
		newMessageCircle.TextColor3 = view.colors.sendButtonText
		newMessageLabel.TextColor3 = view.colors.messageText
		tooltip.show(newMessage :: any, Language.t("sidebar.newMessage"))
	end)
	newMessage.MouseLeave:Connect(function()
		newMessage.BackgroundTransparency = 1
		newMessageCircle.BackgroundColor3 = view.colors.menuItemHover
		newMessageCircle.TextColor3 = view.colors.sendButton
		newMessageLabel.TextColor3 = view.colors.menuItemText
		tooltip.hide()
	end)
	newMessage.MouseButton1Click:Connect(function()
		tooltip.hide()
		onNewMessage(if search.Text ~= "" and self.expanded then search.Text else nil)
	end)

	-- Hides the DMs that don't match the search
	local function applyFilter()
		local query = if self.expanded then string.lower(search.Text) else ""
		for _, row in pairs(self.rows) do
			local holder = row.Parent :: Frame?
			if holder and holder.Parent == list then
				holder.Visible = query == "" or string.find(row:GetAttribute("SearchText") or "", query, 1, true) ~= nil
			end
		end
		if query ~= "" then
			newMessageLabel.Text = Language.t("sidebar.searchFriends", { query = search.Text })
		else
			newMessageLabel.Text = Language.t("sidebar.newMessage")
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(applyFilter)

	--[=[
		Shows the entries (from Conversations.list) with activeId selected.
	]=]
	function self.update(entries: { table }, activeId: string)
		self.entries = entries
		self.activeId = activeId
		local seen = {}
		local dmCount = 0
		for index, entry in ipairs(entries) do
			seen[entry.id] = true
			local row = self.rows[entry.id]
			if not row then
				row = Row.create(view, entry)
				self.rows[entry.id] = row
			end
			local holder = row.Parent :: Frame
			if entry.kind == "place" then
				holder.Parent = pinnedHolder
			else
				dmCount += 1
				holder.LayoutOrder = index
				holder.Parent = list
			end
			Row.fill(view, row, entry)
		end
		for id, row in pairs(self.rows) do
			if not seen[id] then
				row.Parent:Destroy()
				self.rows[id] = nil
			end
		end
		emptyHint.Visible = dmCount == 0 and self.expanded
		applyFilter()
	end

	function self.setActive(activeId: string)
		self.activeId = activeId
		for _, row in pairs(self.rows) do
			Row.paint(view, row)
		end
	end

	--[=[
		Switches between the icon rail and the full list with names.
	]=]
	function self.setExpanded(expanded: boolean)
		self.expanded = expanded
		Animation.tween(frame, "smooth", {
			Size = UDim2.new(
				0,
				if expanded then ConversationList.EXPANDED_WIDTH else ConversationList.COLLAPSED_WIDTH,
				1,
				0
			),
		})
		separator.Visible = not expanded
		sectionTitle.Visible = expanded
		footer.layout()
		newMessageLabel.Visible = expanded
		searchHolder.Visible = expanded
		if not expanded then
			search.Text = ""
		end
		applyFilter()
		tooltip.hide()
		for _, row in pairs(self.rows) do
			Row.layout(view, row)
		end
		local dmCount = 0
		for _, entry in ipairs(self.entries) do
			if entry.kind == "dm" then
				dmCount += 1
			end
		end
		emptyHint.Visible = dmCount == 0 and expanded
	end

	-- Raises (or lowers back) every sidebar element above the chat. Each
	-- element's own ZIndex is kept in its BaseZ attribute, so raising twice
	-- (rows moved inside the sidebar fire DescendantAdded again) is harmless.
	local overlayOn = false
	local function raise(gui: Instance)
		if gui:IsA("GuiObject") then
			local base = gui:GetAttribute("BaseZ")
			if type(base) ~= "number" then
				base = gui.ZIndex
				gui:SetAttribute("BaseZ", base)
			end
			gui.ZIndex = base + ConversationList.OVERLAY_Z_OFFSET
		end
	end
	local function lower(gui: Instance)
		if gui:IsA("GuiObject") then
			local base = gui:GetAttribute("BaseZ")
			if type(base) == "number" then
				gui.ZIndex = base
				gui:SetAttribute("BaseZ", nil)
			end
		end
	end
	frame.DescendantAdded:Connect(function(descendant)
		if overlayOn then
			raise(descendant)
		end
	end)

	--[=[
		Lays the sidebar over the chat (a drawer in a narrow panel), or back beside it.
	]=]
	function self.setOverlay(on: boolean)
		if on == overlayOn then
			return
		end
		overlayOn = on
		local apply = if on then raise else lower
		apply(frame)
		for _, descendant in ipairs(frame:GetDescendants()) do
			apply(descendant)
		end
		frame:SetAttribute("Overlay", on)
	end

	function self.width(): number
		return if self.expanded then ConversationList.EXPANDED_WIDTH else ConversationList.COLLAPSED_WIDTH
	end

	function self.recolor(themeColorsNew)
		colors = themeColorsNew
		view.colors = themeColorsNew
		frame.BackgroundColor3 = colors.inputFrame
		edge.BackgroundColor3 = colors.divider
		separator.BackgroundColor3 = colors.divider
		sectionTitle.TextColor3 = colors.timestamp
		emptyHint.TextColor3 = colors.timestamp
		Foundation.input(search, colors)
		search.TextColor3 = colors.messageText
		search.PlaceholderColor3 = colors.placeholder
		searchIcon.TextColor3 = colors.placeholder
		footer.recolor()
		tooltip.recolor()
		newMessageCircle.BackgroundColor3 = colors.menuItemHover
		newMessageCircle.TextColor3 = colors.sendButton
		newMessageLabel.TextColor3 = colors.menuItemText
		for _, row in pairs(self.rows) do
			Row.recolor(view, row)
		end
	end

	return self
end

return ConversationList
