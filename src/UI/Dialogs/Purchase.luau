--[[
	Purchase

	Checkout for a badge (opened from Badges > Buy): the badge, its price in
	Robux and how buying works. Plugins can't show Roblox's purchase prompt,
	open a browser or copy text, so the game pass page's address is shown to
	go to in a browser. "I bought it" then waits for the purchase
	(handlers.watchPurchase checks ownership every few seconds) and shows
	when it's done.
]]

local Foundation = require(script.Parent.Parent.Common.Foundation)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local ModalKit = require(script.Parent.Kit.ModalKit)
local RichText = require(script.Parent.Parent.Parent.Util.RichText)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS
local Z = 34 -- above Badges (30) and About (32)

local PurchaseDialog = {}

-- Status lines, by state (Core/Language keys)
local STATUS_KEYS = {
	waiting = "checkout.waiting",
	owned = "checkout.owned",
	timeout = "checkout.timeout",
}

local function corner(gui: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = gui
end

--[=[
	kit: a ModalKit. params: {
	  getThemeColors: () -> palette,
	  getHandlers: () -> {
	    purchaseUrl: (gamePassId) -> string,
	    watchPurchase: (badgeId, onStatus: ("waiting" | "owned" | "timeout") -> ()) -> (),
	  }?,
	  onPurchased: ((badgeId) -> ())?,   -- e.g. reload the Badges dialog
	}
	Returns { open(item), close(), isVisible(), recolor() }; item is a store
	item { badge, gamePassId, price, owned, forSale }.
]=]
function PurchaseDialog.create(kit, params)
	local colors = params.getThemeColors()
	local modal = kit.createModal({ name = "PurchaseDialog", title = "Checkout", iconKey = "shop", zIndex = Z })
	Language.bind(modal.title, "Text", "checkout.title")
	local card = modal.card
	local z = modal.contentZIndex

	-- The badge being bought: big icon tile, name, description, price
	local summary = Instance.new("Frame")
	summary.Name = "Summary"
	summary.Size = UDim2.new(1, 0, 0, 72)
	summary.BorderSizePixel = 0
	summary.LayoutOrder = 2
	summary.ZIndex = z
	summary.Parent = card
	corner(summary, 8)

	local tile = Instance.new("TextLabel")
	tile.Name = "Icon"
	tile.AnchorPoint = Vector2.new(0, 0.5)
	tile.Position = UDim2.new(0, 12, 0.5, 0)
	tile.Size = UDim2.fromOffset(48, 48)
	tile.BackgroundTransparency = 0.82
	tile.BorderSizePixel = 0
	tile.FontFace = Icons.font(true)
	tile.TextSize = 26
	tile.ZIndex = z + 1
	tile.Parent = summary
	corner(tile, 8)

	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.Position = UDim2.fromOffset(72, 0)
	info.Size = UDim2.new(1, -170, 1, 0)
	info.BackgroundTransparency = 1
	info.RichText = true
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.FontFace = FONTS.semibold
	info.TextSize = 16
	info.ZIndex = z + 1
	info.Parent = summary

	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.AnchorPoint = Vector2.new(1, 0.5)
	price.Position = UDim2.new(1, -14, 0.5, 0)
	price.Size = UDim2.fromOffset(90, 30)
	price.BackgroundTransparency = 1
	price.RichText = true
	price.TextXAlignment = Enum.TextXAlignment.Right
	price.FontFace = FONTS.bold
	price.TextSize = 18
	price.ZIndex = z + 1
	price.Parent = summary

	ModalKit.addTextKey(card, "heading", "checkout.howItWorks", 3, z, colors)
	ModalKit.addTextKey(card, "body", "checkout.steps", 4, z, colors)

	-- The game pass page's address, to go to in a browser (selectable text)
	local link = Instance.new("TextBox")
	link.Name = "Link"
	link.Size = UDim2.new(1, 0, 0, 0)
	link.AutomaticSize = Enum.AutomaticSize.Y
	link.BorderSizePixel = 0
	link.ClearTextOnFocus = false
	link.TextEditable = false
	link.TextWrapped = true
	link.TextXAlignment = Enum.TextXAlignment.Left
	link.FontFace = FONTS.mono
	link.TextSize = 14
	link.LayoutOrder = 5
	link.ZIndex = z
	link.Parent = card
	corner(link, 8)
	local linkPadding = Instance.new("UIPadding")
	linkPadding.PaddingTop = UDim.new(0, 10)
	linkPadding.PaddingBottom = UDim.new(0, 10)
	linkPadding.PaddingLeft = UDim.new(0, 12)
	linkPadding.PaddingRight = UDim.new(0, 12)
	linkPadding.Parent = link

	local status = ModalKit.addText(card, "body", "", 6, z, colors)
	status.Name = "Status"
	status.Visible = false

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.Size = UDim2.new(1, 0, 0, 36)
	buttons.BackgroundTransparency = 1
	buttons.LayoutOrder = 7
	buttons.ZIndex = z
	buttons.Parent = card
	local buttonsLayout = Instance.new("UIListLayout")
	buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonsLayout.Padding = UDim.new(0, 8)
	buttonsLayout.Parent = buttons

	local function button(name: string, order: number): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.fromOffset(0, 36)
		b.AutomaticSize = Enum.AutomaticSize.X
		b.FontFace = FONTS.semibold
		b.TextSize = 14
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.LayoutOrder = order
		b.ZIndex = z + 1
		b.Parent = buttons
		corner(b, 8)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 16)
		padding.PaddingRight = UDim.new(0, 16)
		padding.Parent = b
		return b
	end
	local cancelButton = button("Cancel", 1)
	local continueButton = button("Continue", 2)
	continueButton.RichText = true

	local current = nil -- the store item being bought
	local state = "ready" -- "ready" | "waiting" | "owned" | "timeout"

	local function render()
		local palette = params.getThemeColors()
		summary.BackgroundColor3 = palette.dialogSecondary
		if current then
			local badge = current.badge
			tile.Text = badge.icon or ""
			tile.TextColor3 = badge.color or palette.sendButton
			tile.BackgroundColor3 = badge.color or palette.sendButton
			info.TextColor3 = palette.messageText
			info.Text = string.format(
				'%s\n<font size="12" weight="regular" color="%s">%s</font>',
				RichText.escape(Language.tOr("badge." .. tostring(badge.id) .. ".name", badge.name)),
				RichText.toHex(palette.timestamp),
				RichText.escape(Language.tOr("badge." .. tostring(badge.id) .. ".description", badge.description))
			)
			price.TextColor3 = palette.messageText
			price.Text = if current.price
				then Icons.inline("robux", true, 18) .. " " .. tostring(current.price)
				else '<font size="12">' .. RichText.escape(Language.t("checkout.priceOnRoblox")) .. "</font>"
		end
		local done = state == "owned"
		local handlers = params.getHandlers()
		link.Visible = current ~= nil and handlers ~= nil and not done
		if current and handlers then
			link.Text = handlers.purchaseUrl(current.gamePassId, current.passName)
		end
		link.BackgroundColor3 = palette.dialogInput
		link.TextColor3 = palette.dialogInputText
		status.Visible = state ~= "ready"
		status.Text = if state == "owned"
			then Language.t("checkout.owned", {
				badge = if current
					then RichText.escape(
						Language.tOr("badge." .. tostring(current.badge.id) .. ".name", current.badge.name)
					)
					else Language.t("checkout.theBadge"),
			})
			elseif STATUS_KEYS[state] then Language.t(STATUS_KEYS[state])
			else ""
		continueButton.Visible = not done
		continueButton.Text = Language.t(
			if state == "ready"
				then "checkout.continue"
				elseif state == "waiting" then "checkout.openAgain"
				else "checkout.tryAgain"
		)
		Foundation.button(continueButton, palette, "emphasis")
		cancelButton.Text = Language.t(if done then "checkout.done" else "common.cancel")
		Foundation.button(cancelButton, palette, "standard")
		ModalKit.recolorText(card, palette)
	end

	continueButton.MouseButton1Click:Connect(function()
		local handlers = params.getHandlers()
		if not current or not handlers then
			return
		end
		local item = current
		-- Bought it on Roblox.com: check (and keep checking) until Roblox says so
		handlers.watchPurchase(item.badge.id, function(newStatus)
			if current ~= item then
				return -- another badge's checkout is open now
			end
			state = newStatus
			if newStatus == "owned" and params.onPurchased then
				params.onPurchased(item.badge.id)
			end
			render()
		end)
	end)
	cancelButton.MouseButton1Click:Connect(function()
		modal.close()
	end)

	local self = {}

	function self.open(item)
		current = item
		state = if item.owned then "owned" else "ready"
		render()
		card.CanvasPosition = Vector2.zero
		modal.open()
	end

	function self.close()
		modal.close()
	end

	function self.isVisible(): boolean
		return modal.isVisible()
	end

	function self.recolor()
		render()
	end

	return self
end

return PurchaseDialog
