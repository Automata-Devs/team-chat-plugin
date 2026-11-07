--!
-- ModalKit
-- Shared shell for ChatUI's modal dialogs (Create a Poll, Settings, What's
-- New): a dimmed overlay that closes when you click outside the card, a card
-- that grows with its content between a minimum and maximum height (then
-- scrolls) and is kept between a minimum and maximum width, and a title with
-- an accent icon and a close button. Dialog modules fill the card. Sizes
-- shrink below their minimums only when the panel itself is smaller.
--!

local Animation = require(script.Parent.Parent.Animation)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)

local FONTS = Theme.FONTS

local MODAL_MIN_WIDTH = 300
local MODAL_MAX_WIDTH = 520
local MODAL_WIDTH_SCALE = 0.9 -- of the panel, between the min and max width
local MODAL_MIN_HEIGHT = 200 -- per modal: options.minHeight
local MODAL_MAX_HEIGHT = 540
local MODAL_SCREEN_MARGIN = 16 -- gap around the card when the panel is small
local MODAL_TITLE_ICON_SPACE = 28 -- icon width + gap before the title text
local OVERLAY_TRANSPARENCY = 0.4 -- the dimmed backdrop, fully faded in

local ModalKit = {}

--!
-- params: {
--   container: Frame,              -- full-panel layer the modals live in
--   getThemeColors: () -> palette, -- the current palette
--   isInside: (gui, point) -> boolean,
--   mousePosition: () -> Vector2,  -- in the same space as AbsolutePosition
-- }
-- Returns a kit with createModal(options) and recolor().
--!
function ModalKit.new(params)
	local container = params.container
	local modals = {}
	local kit = {}

	-- Sizes the card: its width from the panel (min/max width, minus
	-- modal.reservedWidth for things beside it like the Settings nav), its
	-- height from the content (min/max height). The canvas is set by hand:
	-- AutomaticCanvasSize under-measured the padded list and cut off the
	-- bottom buttons. Returns the refit function.
	local function setupScrolling(card: ScrollingFrame, layout: UIListLayout, padding: UIPadding, modal)
		card.AutomaticCanvasSize = Enum.AutomaticSize.None
		card.ScrollingDirection = Enum.ScrollingDirection.Y
		card.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		card.ElasticBehavior = Enum.ElasticBehavior.Never
		card.ScrollBarThickness = 4

		local function fitHeight()
			local panel = container.AbsoluteSize
			local contentHeight = layout.AbsoluteContentSize.Y
				+ padding.PaddingTop.Offset
				+ padding.PaddingBottom.Offset
			card.CanvasSize = UDim2.fromOffset(0, contentHeight)

			local available = math.max(0, panel.X - MODAL_SCREEN_MARGIN * 2 - (modal.reservedWidth or 0))
			local width = math.clamp(
				panel.X * MODAL_WIDTH_SCALE - (modal.reservedWidth or 0),
				math.min(MODAL_MIN_WIDTH, available),
				math.min(MODAL_MAX_WIDTH, available)
			)
			local maxHeight = math.max(0, math.min(MODAL_MAX_HEIGHT, panel.Y - MODAL_SCREEN_MARGIN * 2))
			local minHeight = math.min(modal.minHeight or MODAL_MIN_HEIGHT, maxHeight)
			card.Size = UDim2.fromOffset(math.floor(width), math.clamp(contentHeight, minHeight, maxHeight))
		end
		-- Layout sizes can settle a frame late; re-fit once more after each change
		local function refit()
			fitHeight()
			task.defer(fitHeight)
		end
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refit)
		container:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
		card.Parent:GetPropertyChangedSignal("Visible"):Connect(refit) -- the overlay opening
		refit()
		return refit
	end

	--!
	-- options: { name, title, iconKey, zIndex, minHeight? }
	-- The overlay and click catcher use zIndex, the card zIndex + 1, the
	-- title zIndex + 2 and its close button zIndex + 3. Dialog content should
	-- use modal.contentZIndex (zIndex + 2), buttons on top of it one more.
	-- Returns { overlay, card, title, closeButton, contentZIndex,
	--           open(), close(), isVisible(), onClose: (() -> ())? }
	--!
	function kit.createModal(options)
		local colors = params.getThemeColors()
		local z = options.zIndex

		local overlay = Instance.new("Frame")
		overlay.Name = options.name
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 14) -- Roblox's scrim
		overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
		overlay.BorderSizePixel = 0
		overlay.Visible = false
		overlay.ZIndex = z
		overlay.Parent = container

		-- Full-panel button behind the card: closes on clicks outside the card.
		-- It also receives clicks made on the card (frames don't block GUI
		-- buttons), so it checks where the mouse is.
		local clickCatcher = Instance.new("TextButton")
		clickCatcher.Name = "ClickCatcher"
		clickCatcher.Size = UDim2.new(1, 0, 1, 0)
		clickCatcher.BackgroundTransparency = 1
		clickCatcher.Text = ""
		clickCatcher.AutoButtonColor = false
		clickCatcher.ZIndex = z
		clickCatcher.Parent = overlay

		local card = Instance.new("ScrollingFrame") -- height set by setupScrolling
		card.Name = "DialogFrame"
		card.Size = UDim2.fromOffset(MODAL_MIN_WIDTH, 0) -- set by setupScrolling
		card.Position = UDim2.new(0.5, 0, 0.5, 0)
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.BackgroundColor3 = colors.dialogBack
		card.BorderSizePixel = 0
		card.ScrollBarImageColor3 = colors.scrollBar
		card.ZIndex = z + 1
		card.Parent = overlay

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 16)
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Name = "DialogStroke"
		stroke.Color = colors.dialogBorder
		stroke.Thickness = 1
		stroke.Parent = card

		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 9)
		layout.Parent = card

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 18)
		padding.PaddingBottom = UDim.new(0, 18)
		padding.PaddingLeft = UDim.new(0, 18)
		padding.PaddingRight = UDim.new(0, 18)
		padding.Parent = card
		-- Sizing inputs; the modal table below adds its fields to this one
		local modal: any = { minHeight = options.minHeight, reservedWidth = 0 }
		local refit = setupScrolling(card, layout, padding, modal)

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 28)
		title.BackgroundTransparency = 1
		title.Text = options.title
		title.TextColor3 = colors.messageText
		title.FontFace = FONTS.display
		title.TextSize = 20
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.LayoutOrder = 1
		title.ZIndex = z + 2
		title.BorderSizePixel = 0
		title.Parent = card

		-- Accent icon left of the title text, in the title's left padding
		local titlePadding = Instance.new("UIPadding")
		titlePadding.PaddingLeft = UDim.new(0, MODAL_TITLE_ICON_SPACE)
		titlePadding.Parent = title

		local titleIcon = Instance.new("TextLabel")
		titleIcon.Name = "TitleIcon"
		titleIcon.AnchorPoint = Vector2.new(0, 0.5)
		titleIcon.Position = UDim2.new(0, -MODAL_TITLE_ICON_SPACE, 0.5, 0)
		titleIcon.Size = UDim2.fromOffset(20, 20)
		titleIcon.BackgroundTransparency = 1
		Icons.apply(titleIcon, options.iconKey)
		titleIcon.TextColor3 = colors.messageText
		titleIcon.TextSize = 20
		titleIcon.ZIndex = z + 2
		titleIcon.Parent = title

		local closeButton = Instance.new("TextButton")
		closeButton.Name = "Close"
		closeButton.Size = UDim2.new(0, 28, 0, 28)
		closeButton.Position = UDim2.new(1, -28, 0, 0)
		closeButton.BackgroundTransparency = 1
		Icons.apply(closeButton, "close")
		closeButton.TextColor3 = colors.timestamp
		closeButton.TextSize = 16
		closeButton.AutoButtonColor = true
		closeButton.BorderSizePixel = 0
		closeButton.ZIndex = z + 3
		closeButton.Parent = title

		modal.refit = refit -- after changing minHeight or reservedWidth
		for key, value in pairs({
			overlay = overlay,
			card = card,
			title = title,
			closeButton = closeButton,
			contentZIndex = z + 2,
			onClose = nil, -- set by the dialog, called after every close
			-- Set just before open/close: true = no animation, "switch" = a
			-- Settings tab swap (backdrop stays, the page fades in)
			instantNext = nil :: (boolean | string)?,
		}) do
			modal[key] = value
		end
		local isOpen = false
		local closeToken = 0

		-- Opening: the backdrop fades in and the card pops up
		function modal.open()
			local mode = modal.instantNext
			modal.instantNext = nil
			isOpen = true
			closeToken += 1
			overlay.Visible = true
			if mode == true then
				overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
			elseif mode == "switch" then
				overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
				Animation.fadeIn(card, "quick")
			else
				overlay.BackgroundTransparency = 1
				Animation.tween(overlay, "smooth", { BackgroundTransparency = OVERLAY_TRANSPARENCY })
				Animation.popIn(card, 0.94)
			end
		end

		-- Closing: counts as closed right away; the card shrinks and the
		-- backdrop fades before the overlay hides
		function modal.close()
			local instant = modal.instantNext ~= nil or not Animation.enabled()
			modal.instantNext = nil
			isOpen = false
			closeToken += 1
			local token = closeToken
			if instant then
				overlay.Visible = false
			else
				Animation.popOut(card, 0.96)
				Animation.tween(overlay, "exit", { BackgroundTransparency = 1 })
				task.delay(Animation.PRESETS.exit.Time, function()
					if closeToken == token then
						overlay.Visible = false
					end
				end)
			end
			if modal.onClose then
				modal.onClose()
			end
		end

		function modal.isVisible(): boolean
			return isOpen
		end

		function modal.recolor()
			local palette = params.getThemeColors()
			card.BackgroundColor3 = palette.dialogBack
			card.ScrollBarImageColor3 = palette.scrollBar
			stroke.Color = palette.dialogBorder
			title.TextColor3 = palette.messageText
			titleIcon.TextColor3 = palette.messageText
			closeButton.TextColor3 = palette.timestamp
		end

		closeButton.MouseButton1Click:Connect(function()
			modal.close()
		end)
		-- Clicks on the card, or on anything registered in modal.insideGuis
		-- (e.g. the Settings tabs beside it), don't count as outside
		modal.insideGuis = {}
		clickCatcher.MouseButton1Click:Connect(function()
			local point = params.mousePosition()
			if params.isInside(card, point) then
				return
			end
			for _, gui in ipairs(modal.insideGuis) do
				if gui.Visible and params.isInside(gui, point) then
					return
				end
			end
			modal.close()
		end)

		table.insert(modals, modal)
		return modal
	end

	--!
	-- Re-applies the current palette to every modal's shell.
	--!
	function kit.recolor()
		for _, modal in ipairs(modals) do
			modal.recolor()
		end
	end

	return kit
end

-- Text roles for addText: font, size and palette color
local TEXT_ROLES = {
	heading = { font = FONTS.bold, size = 14, color = "messageText" },
	body = { font = FONTS.body, size = 13, color = "messageText" },
	muted = { font = FONTS.body, size = 12, color = "timestamp" },
}

--!
-- Adds a wrapping text label to a dialog card. role: "heading" (a bold
-- title), "body" or "muted". Text is rich text. recolorText re-applies
-- the palette to every label made here.
--!
function ModalKit.addText(parent: Instance, role: string, text: string, order: number, zIndex: number, colors)
	local style = TEXT_ROLES[role]
	local label = Instance.new("TextLabel")
	label.Name = role .. "_" .. order
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.RichText = true
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.FontFace = style.font
	label.TextSize = style.size
	label.LineHeight = 1.15
	label.Text = if style.upper then string.upper(text) else text
	label.TextColor3 = colors[style.color]
	label.LayoutOrder = order
	label.ZIndex = zIndex
	label:SetAttribute("TextRole", role)
	label.Parent = parent
	return label
end

--!
-- Like addText, but the text is a Core/Language key and follows language
-- changes (headings stay in capitals).
--!
function ModalKit.addTextKey(
	parent: Instance,
	role: string,
	key: string,
	order: number,
	zIndex: number,
	colors,
	vars: { [string]: any }?
)
	local label = ModalKit.addText(parent, role, Language.t(key, vars), order, zIndex, colors)
	Language.bind(label, "Text", key, vars, if TEXT_ROLES[role].upper then string.upper else nil)
	return label
end

--!
-- Re-applies the palette to the labels made by addText under root.
--!
function ModalKit.recolorText(root: Instance, colors)
	for _, label in ipairs(root:GetDescendants()) do
		local role = label:GetAttribute("TextRole")
		if role and TEXT_ROLES[role] and label:IsA("TextLabel") then
			label.TextColor3 = colors[TEXT_ROLES[role].color]
		end
	end
end

return ModalKit
