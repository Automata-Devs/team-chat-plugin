--[[
	Badges

	The "Badges" modal (sidebar): the badges you have, the badges you can buy
	(Roblox game passes; Buy opens the checkout, PurchaseDialog) and a
	Refresh purchases button to check again. The badge data comes from handlers ChatWindow is
	given by the controller (UI doesn't require services).
]]

local Foundation = require(script.Parent.Parent.Common.Foundation)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local ModalKit = require(script.Parent.Kit.ModalKit)
local RichText = require(script.Parent.Parent.Parent.Util.RichText)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONTS = Theme.FONTS
local Z = 30
local ROW_HEIGHT = 54
local ICON_TILE = 34
local BUY_WIDTH = 96

local BadgesDialog = {}

local function corner(gui: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = gui
end

--[=[
	kit: a ModalKit. params: {
	  getThemeColors: () -> palette,
	  onBuy: ((StoreItem) -> ())?,        -- open the checkout for a badge
	  getHandlers: () -> {
	    myBadges: () -> { Badge },          -- your badges now
	    getStore: () -> { StoreItem },      -- yields; badges for sale
	    purchaseUrl: (gamePassId) -> string,
	    refresh: () -> (),                  -- look up your badges again
	  }?,
	}
	Returns { open(), close(), isVisible(), recolor() }
]=]
function BadgesDialog.create(kit, params)
	local colors = params.getThemeColors()
	local modal = kit.createModal({ name = "BadgesDialog", title = "Badges", iconKey = "badges", zIndex = Z })
	local card = modal.card
	local z = modal.contentZIndex

	ModalKit.addTextKey(card, "muted", "badges.intro", 2, z, colors)
	ModalKit.addTextKey(card, "heading", "badges.yours", 3, z, colors)
	local mine = ModalKit.addText(card, "body", "", 4, z, colors)
	mine.Name = "MyBadges"
	ModalKit.addTextKey(card, "heading", "badges.get", 5, z, colors)

	local store = Instance.new("Frame")
	store.Name = "Store"
	store.Size = UDim2.new(1, 0, 0, 0)
	store.AutomaticSize = Enum.AutomaticSize.Y
	store.BackgroundTransparency = 1
	store.LayoutOrder = 6
	store.ZIndex = z
	store.Parent = card
	local storeLayout = Instance.new("UIListLayout")
	storeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	storeLayout.Padding = UDim.new(0, 6)
	storeLayout.Parent = store

	ModalKit.addTextKey(card, "muted", "badges.howToBuy", 7, z, colors)
	ModalKit.addTextKey(card, "heading", "badges.verifiedHeading", 8, z, colors)
	local verifiedText = ModalKit.addText(card, "body", "", 9, z, colors)
	local function renderVerifiedText()
		verifiedText.Text = RichText.buildBadges({ { verified = true } })
			.. " "
			.. RichText.escape(Language.t("badges.verifiedText"))
	end
	renderVerifiedText()

	local refreshButton = Instance.new("TextButton")
	refreshButton.Name = "Refresh"
	refreshButton.Size = UDim2.new(1, 0, 0, 34)
	Language.bind(refreshButton, "Text", "badges.refresh")
	refreshButton.FontFace = FONTS.medium
	refreshButton.TextSize = 13
	refreshButton.BorderSizePixel = 0
	refreshButton.AutoButtonColor = true
	refreshButton.LayoutOrder = 10
	refreshButton.ZIndex = z + 1
	refreshButton.Parent = card
	corner(refreshButton, 8)

	local status = ModalKit.addText(card, "muted", "", 11, z, colors)
	status.Name = "Status"
	status.Visible = false

	local storeItems = nil -- last loaded store, nil while loading
	local loadId = 0

	local function setStatus(text: string?)
		status.Text = text or ""
		status.Visible = text ~= nil
	end

	local function describeBadges(badges): string
		local parts = {}
		for _, badge in ipairs(badges) do
			local name = Language.tOr("badge." .. tostring(badge.id) .. ".name", badge.name)
			table.insert(parts, RichText.buildBadges({ badge }) .. " " .. RichText.escape(name))
		end
		return if #parts > 0 then table.concat(parts, "     ") else Language.t("badges.none")
	end

	local function createRow(index: number, item, palette)
		local row = Instance.new("Frame")
		row.Name = "Badge_" .. item.badge.id
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BackgroundColor3 = palette.dialogSecondary
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.ZIndex = z
		row.Parent = store
		corner(row, 8)

		local tile = Instance.new("TextLabel")
		tile.Name = "Icon"
		tile.AnchorPoint = Vector2.new(0, 0.5)
		tile.Position = UDim2.new(0, 10, 0.5, 0)
		tile.Size = UDim2.fromOffset(ICON_TILE, ICON_TILE)
		tile.BackgroundColor3 = item.badge.color or palette.sendButton
		tile.BackgroundTransparency = 0.82
		tile.BorderSizePixel = 0
		tile.FontFace = Icons.font(true)
		tile.Text = item.badge.icon or ""
		tile.TextColor3 = item.badge.color or palette.sendButton
		tile.TextSize = 18
		tile.ZIndex = z + 1
		tile.Parent = row
		corner(tile, 8)

		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Position = UDim2.fromOffset(ICON_TILE + 20, 0)
		text.Size = UDim2.new(1, -(ICON_TILE + 20 + BUY_WIDTH + 18), 1, 0)
		text.BackgroundTransparency = 1
		text.RichText = true
		text.TextWrapped = true
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.FontFace = FONTS.semibold
		text.TextSize = 14
		text.TextColor3 = palette.messageText
		text.Text = string.format(
			'%s\n<font size="12" weight="regular" color="%s">%s</font>',
			RichText.escape(Language.tOr("badge." .. item.badge.id .. ".name", item.badge.name)),
			RichText.toHex(palette.timestamp),
			RichText.escape(Language.tOr("badge." .. item.badge.id .. ".description", item.badge.description))
		)
		text.ZIndex = z + 1
		text.Parent = row

		local buy = Instance.new("TextButton")
		buy.Name = "Buy"
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, -10, 0.5, 0)
		buy.Size = UDim2.fromOffset(BUY_WIDTH, 30)
		buy.BorderSizePixel = 0
		buy.RichText = true
		buy.FontFace = FONTS.semibold
		buy.TextSize = 13
		buy.ZIndex = z + 2
		buy.Parent = row
		corner(buy, 8)

		if item.owned then
			buy.Text = Language.t("badges.owned")
			buy.AutoButtonColor = false
			buy.BackgroundColor3 = palette.dialogBack
			buy.TextColor3 = palette.timestamp
		elseif not item.forSale then
			buy.Text = Language.t("badges.comingSoon")
			buy.AutoButtonColor = false
			buy.BackgroundColor3 = palette.dialogBack
			buy.TextColor3 = palette.timestamp
		else
			buy.Text = if item.price
				then Icons.inline("robux", false, 13) .. " " .. tostring(item.price)
				else Language.t("badges.buy")
			Foundation.button(buy, palette, "emphasis")
			buy.MouseButton1Click:Connect(function()
				if params.onBuy then
					params.onBuy(item) -- the checkout (PurchaseDialog)
				end
			end)
		end
	end

	local function renderStore()
		local palette = params.getThemeColors()
		for _, child in ipairs(store:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if storeItems == nil then
			ModalKit.addText(store, "muted", Language.t("badges.loading"), 1, z, palette)
		elseif #storeItems == 0 then
			ModalKit.addText(store, "muted", Language.t("badges.noneForSale"), 1, z, palette)
		else
			for i, item in ipairs(storeItems) do
				createRow(i, item, palette)
			end
		end
	end

	local function render()
		local palette = params.getThemeColors()
		local handlers = params.getHandlers()
		mine.Text = describeBadges(if handlers then handlers.myBadges() else {})
		renderVerifiedText()
		Foundation.button(refreshButton, palette, "standard")
		ModalKit.recolorText(card, palette)
		renderStore()
	end

	-- Loads the store in the background (web requests) and shows it
	local function load()
		loadId += 1
		local thisLoad = loadId
		storeItems = nil
		render()
		task.spawn(function()
			local handlers = params.getHandlers()
			local ok, items = pcall(function()
				return if handlers then handlers.getStore() else {}
			end)
			if thisLoad ~= loadId or not Lifetime.alive or not card.Parent then
				return
			end
			storeItems = if ok then items else {}
			render()
		end)
	end

	refreshButton.MouseButton1Click:Connect(function()
		local handlers = params.getHandlers()
		if handlers then
			handlers.refresh()
		end
		local checking = Language.t("badges.checking")
		setStatus(checking)
		load()
		Lifetime.delay(4, function()
			if status.Text == checking then
				setStatus(nil)
			end
			render() -- badges found since
		end)
	end)

	local self = { modal = modal } -- modal: joined into the Settings tabs

	function self.open()
		setStatus(nil)
		card.CanvasPosition = Vector2.zero
		modal.open()
		load()
	end

	function self.close()
		modal.close()
	end

	function self.isVisible(): boolean
		return modal.isVisible()
	end

	--[=[
		Loads the store again (e.g. after a purchase) if the dialog is open.
	]=]
	function self.reload()
		if modal.isVisible() then
			load()
		end
	end

	--[=[
		Re-renders with the current palette, or after your badges changed.
	]=]
	function self.recolor()
		if modal.isVisible() then
			render()
		else
			ModalKit.recolorText(card, params.getThemeColors())
		end
	end

	return self
end

return BadgesDialog
