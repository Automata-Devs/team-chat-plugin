--!
-- ModalKit
-- Shared shell for ChatUI's modal dialogs (Create a Poll, Settings, What's
-- New): a dimmed overlay that closes when you click outside the card, a card
-- that grows with its content up to MODAL_MAX_HEIGHT and then scrolls, and a
-- title with an accent icon and a close button. Dialog modules fill the card.
--!

local Theme = require(script.Parent.Parent.Config.Theme)
local Icons = require(script.Parent.Parent.Config.Icons)

local FONTS = Theme.FONTS

local MODAL_MAX_HEIGHT = 540
local MODAL_SCREEN_MARGIN = 16 -- gap above and below the card when the panel is short
local MODAL_TITLE_ICON_SPACE = 28 -- icon width + gap before the title text

local ModalKit = {}

--!
-- params: {
--   container: Frame,              -- the chat panel's root frame
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

	-- Sizes the card to its content (canvas set by hand: AutomaticCanvasSize
	-- under-measured the padded list and cut off the bottom buttons)
	local function setupScrolling(card: ScrollingFrame, layout: UIListLayout, padding: UIPadding)
		card.AutomaticCanvasSize = Enum.AutomaticSize.None
		card.ScrollingDirection = Enum.ScrollingDirection.Y
		card.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		card.ElasticBehavior = Enum.ElasticBehavior.Never
		card.ScrollBarThickness = 4

		local function fitHeight()
			local contentHeight = layout.AbsoluteContentSize.Y + padding.PaddingTop.Offset + padding.PaddingBottom.Offset
			local maxHeight = math.min(MODAL_MAX_HEIGHT, container.AbsoluteSize.Y - MODAL_SCREEN_MARGIN * 2)
			card.CanvasSize = UDim2.fromOffset(0, contentHeight)
			card.Size = UDim2.new(card.Size.X.Scale, card.Size.X.Offset, 0, math.max(0, math.min(contentHeight, maxHeight)))
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
	end

	--!
	-- options: { name, title, iconKey, zIndex }
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
		overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		overlay.BackgroundTransparency = 0.4
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
		card.Size = UDim2.new(0.9, 0, 0, 0)
		card.Position = UDim2.new(0.5, 0, 0.5, 0)
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.BackgroundColor3 = colors.dialogBack
		card.BorderSizePixel = 0
		card.ScrollBarImageColor3 = colors.scrollBar
		card.ZIndex = z + 1
		card.Parent = overlay

		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MaxSize = Vector2.new(520, MODAL_MAX_HEIGHT)
		sizeConstraint.Parent = card

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
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
		setupScrolling(card, layout, padding)

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 28)
		title.BackgroundTransparency = 1
		title.Text = options.title
		title.TextColor3 = colors.messageText
		title.FontFace = FONTS.display
		title.TextSize = 18
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
		titleIcon.TextColor3 = colors.sendButton
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

		local modal = {
			overlay = overlay,
			card = card,
			title = title,
			closeButton = closeButton,
			contentZIndex = z + 2,
			onClose = nil, -- set by the dialog, called after every close
		}

		function modal.open()
			overlay.Visible = true
		end

		function modal.close()
			overlay.Visible = false
			if modal.onClose then
				modal.onClose()
			end
		end

		function modal.isVisible(): boolean
			return overlay.Visible
		end

		function modal.recolor()
			local palette = params.getThemeColors()
			card.BackgroundColor3 = palette.dialogBack
			card.ScrollBarImageColor3 = palette.scrollBar
			stroke.Color = palette.dialogBorder
			title.TextColor3 = palette.messageText
			titleIcon.TextColor3 = palette.sendButton
			closeButton.TextColor3 = palette.timestamp
		end

		closeButton.MouseButton1Click:Connect(function()
			modal.close()
		end)
		clickCatcher.MouseButton1Click:Connect(function()
			if not params.isInside(card, params.mousePosition()) then
				modal.close()
			end
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

return ModalKit
