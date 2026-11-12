--[[
	Sidebar

	The conversations sidebar on the left of the panel (Components/
	ConversationList) and how it shares the panel with the chat. It expands
	by itself in a wide panel; expanding it in a narrow one would squeeze the
	chat, so it slides over the chat instead (a drawer with a dimmed scrim).
	It also keeps the conversation list and puts the unread total in the
	widget's title.

	Usage:
		local sidebar = Sidebar.create(ctx, { onNewMessage = open, baseTitle = "Team Chat 1.27.0" })
		sidebar.setConversations(entries, activeId)
]]

local Animation = require(script.Parent.Parent.Common.Animation)
local ConversationList = require(script.Parent.Parent.Components.ConversationList)

-- Narrower than this, the expanded sidebar lies over the chat
local MIN_CHAT_WIDTH = 360
-- Wider than this, the sidebar expands by itself (until toggled by hand)
local AUTO_EXPAND_WIDTH = 600

export type Options = {
	baseTitle: string,
	-- The + above the DMs: open the New message dialog with what was typed
	onNewMessage: (query: string?) -> (),
}

local Sidebar = {}

function Sidebar.create(ctx, options: Options)
	local widget = ctx.widget
	local container: Frame = ctx.container

	local list
	local manualExpanded: boolean? = nil
	local overlay = false
	local selectCallback: ((id: string) -> ())? = nil
	local closeCallback: ((id: string) -> ())? = nil
	local entries = nil
	local activeId = nil

	-- Dims the chat while the sidebar lies over it; clicking it closes the sidebar
	local scrim = Instance.new("TextButton")
	scrim.Name = "SidebarScrim"
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 0.5
	scrim.BorderSizePixel = 0
	scrim.Position = UDim2.fromOffset(ConversationList.EXPANDED_WIDTH, 0)
	scrim.Size = UDim2.new(1, -ConversationList.EXPANDED_WIDTH, 1, 0)
	scrim.ZIndex = ConversationList.OVERLAY_Z_OFFSET -- above the chat, below the raised sidebar
	scrim.Visible = false
	scrim.Parent = widget

	local function applyWidth()
		overlay = list.expanded and widget.AbsoluteSize.X - ConversationList.EXPANDED_WIDTH < MIN_CHAT_WIDTH
		local width = if overlay then ConversationList.COLLAPSED_WIDTH else list.width()
		Animation.tween(container, "smooth", {
			Position = UDim2.fromOffset(width, 0),
			Size = UDim2.new(1, -width, 1, 0),
		})
		list.setOverlay(overlay)
		if overlay and not scrim.Visible then
			scrim.BackgroundTransparency = 1
			Animation.tween(scrim, "smooth", { BackgroundTransparency = 0.5 })
		end
		scrim.Visible = overlay
	end
	local function setExpanded(expanded: boolean)
		list.setExpanded(expanded)
		applyWidth()
	end
	scrim.MouseButton1Click:Connect(function()
		manualExpanded = false
		setExpanded(false)
	end)

	-- Picking a conversation from the overlay closes it
	local function closeOverlay()
		if overlay then
			manualExpanded = false
			setExpanded(false)
		end
	end

	list = ConversationList.create(
		ctx.palette,
		widget,
		function(id)
			closeOverlay()
			if selectCallback then
				selectCallback(id)
			end
		end,
		function(expanded)
			manualExpanded = expanded
			setExpanded(expanded)
		end,
		options.onNewMessage,
		function(id)
			if closeCallback then
				closeCallback(id)
			end
		end
	)

	local function autoExpand()
		if manualExpanded ~= nil then
			return
		end
		local wide = widget.AbsoluteSize.X >= AUTO_EXPAND_WIDTH
		if wide ~= list.expanded then
			setExpanded(wide)
		end
	end
	widget:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		autoExpand()
		applyWidth()
	end)
	applyWidth()
	task.defer(autoExpand)

	local self = {}
	self.list = list

	function self.entries()
		return entries
	end

	--[=[
		Shows the conversations and the unread total in the widget's title,
		like "Team Chat 1.26.0 (3)", so it shows while the chat is out of view.
	]=]
	function self.setConversations(newEntries, newActiveId)
		entries = newEntries
		activeId = newActiveId
		list.update(newEntries, newActiveId)
		local total = 0
		for _, entry in ipairs(newEntries) do
			total += entry.unread or 0
		end
		widget.Title = if total > 0
			then string.format("%s (%s)", options.baseTitle, if total > 99 then "99+" else tostring(total))
			else options.baseTitle
	end

	--[=[
		Re-draws the list (names or verified badges changed).
	]=]
	function self.rerender()
		if entries then
			list.update(entries, activeId)
		end
	end

	function self.onSelect(callback)
		selectCallback = callback
	end

	function self.onClose(callback)
		closeCallback = callback
	end

	function self.recolor()
		list.recolor(ctx.palette)
	end

	return self
end

return Sidebar
