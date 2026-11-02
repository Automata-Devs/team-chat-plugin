--!
-- CreatePollDialog
-- The "Create a Poll" modal: a question and 2 to MAX_POLL_OPTIONS answers.
-- The first MIN_POLL_OPTIONS answers are required (no remove button); extra
-- ones can be removed. Create sends the trimmed question and non-empty
-- answers to opts.onSubmit.
--!

local Theme = require(script.Parent.Parent.Config.Theme)
local Icons = require(script.Parent.Parent.Config.Icons)

local FONTS = Theme.FONTS
local MIN_POLL_OPTIONS = 2
local MAX_POLL_OPTIONS = Theme.MAX_POLL_OPTIONS

local CreatePollDialog = {}

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

--!
-- kit: a ModalKit. opts: {
--   getThemeColors: () -> palette,
--   onSubmit: (question: string, options: {string}) -> (),
-- }
-- Returns { open, close, isVisible, recolor }
--!
function CreatePollDialog.create(kit, opts)
	local modal = kit.createModal({ name = "PollDialog", title = "Create a Poll", iconKey = "createPoll", zIndex = 20 })
	local card = modal.card
	local z = modal.contentZIndex
	local colors = opts.getThemeColors()

	local function heading(name: string, text: string, order: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Size = UDim2.new(1, 0, 0, 18)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = colors.messageText
		label.FontFace = FONTS.bold
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = order
		label.ZIndex = z
		label.BorderSizePixel = 0
		label.Parent = card
		return label
	end

	local function roundCorners(gui: GuiObject)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = gui
	end

	local function horizontalPadding(gui: GuiObject)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.Parent = gui
	end

	local questionHeading = heading("QuestionHeading", "QUESTION", 2)

	local questionBox = Instance.new("TextBox")
	questionBox.Name = "QuestionBox"
	questionBox.Size = UDim2.new(1, 0, 0, 40)
	questionBox.BackgroundColor3 = colors.dialogInput
	questionBox.TextColor3 = colors.dialogInputText
	questionBox.PlaceholderText = "Poll question..."
	questionBox.PlaceholderColor3 = colors.placeholder
	questionBox.Font = Theme.FONT
	questionBox.TextSize = 14
	questionBox.Text = ""
	questionBox.ClearTextOnFocus = false
	questionBox.TextXAlignment = Enum.TextXAlignment.Left
	questionBox.BorderSizePixel = 0
	questionBox.LayoutOrder = 3
	questionBox.ZIndex = z
	questionBox.Parent = card
	roundCorners(questionBox)
	horizontalPadding(questionBox)

	local answersHeading = heading("AnswersHeading", "ANSWERS", 4)

	local optionsContainer = Instance.new("Frame")
	optionsContainer.Name = "OptionsContainer"
	optionsContainer.Size = UDim2.new(1, 0, 0, 0)
	optionsContainer.AutomaticSize = Enum.AutomaticSize.Y
	optionsContainer.BackgroundTransparency = 1
	optionsContainer.LayoutOrder = 5
	optionsContainer.ZIndex = z
	optionsContainer.Parent = card

	local optionsLayout = Instance.new("UIListLayout")
	optionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	optionsLayout.Padding = UDim.new(0, 8)
	optionsLayout.Parent = optionsContainer

	local addOptionButton = Instance.new("TextButton")
	addOptionButton.Name = "AddOption"
	addOptionButton.Size = UDim2.new(1, 0, 0, 36)
	addOptionButton.BackgroundColor3 = colors.dialogSecondary
	addOptionButton.Text = "+  Add another answer"
	addOptionButton.TextColor3 = colors.menuItemText or colors.messageText
	addOptionButton.FontFace = FONTS.medium
	addOptionButton.TextSize = 13
	addOptionButton.AutoButtonColor = true
	addOptionButton.BorderSizePixel = 0
	addOptionButton.LayoutOrder = 6
	addOptionButton.ZIndex = z
	addOptionButton.Parent = card
	roundCorners(addOptionButton)

	local buttonsRow = Instance.new("Frame")
	buttonsRow.Name = "ButtonsRow"
	buttonsRow.Size = UDim2.new(1, 0, 0, 38)
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.LayoutOrder = 7
	buttonsRow.ZIndex = z
	buttonsRow.Parent = card

	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "Cancel"
	cancelButton.Size = UDim2.new(0.5, -4, 1, 0)
	cancelButton.BackgroundColor3 = colors.dialogSecondary
	cancelButton.Text = "Cancel"
	cancelButton.TextColor3 = colors.menuItemText or colors.messageText
	cancelButton.FontFace = FONTS.medium
	cancelButton.TextSize = 14
	cancelButton.AutoButtonColor = true
	cancelButton.BorderSizePixel = 0
	cancelButton.ZIndex = z + 1
	cancelButton.Parent = buttonsRow
	roundCorners(cancelButton)

	local createButton = Instance.new("TextButton")
	createButton.Name = "Create"
	createButton.Size = UDim2.new(0.5, -4, 1, 0)
	createButton.Position = UDim2.new(0.5, 4, 0, 0)
	createButton.BackgroundColor3 = colors.dialogButton
	createButton.Text = "Create"
	createButton.TextColor3 = colors.dialogButtonText
	createButton.FontFace = FONTS.semibold
	createButton.TextSize = 14
	createButton.AutoButtonColor = true
	createButton.BorderSizePixel = 0
	createButton.ZIndex = z + 1
	createButton.Parent = buttonsRow
	roundCorners(createButton)

	-- One TextBox per answer row, in order
	local optionBoxes: {TextBox} = {}

	local function refreshOptionRows()
		for i, box in ipairs(optionBoxes) do
			box.PlaceholderText = "Answer " .. i
			box.Parent.LayoutOrder = i
			-- The first MIN_POLL_OPTIONS answers are required: no X, full-width box
			local removable = i > MIN_POLL_OPTIONS
			box.Parent:FindFirstChild("Remove").Visible = removable
			box.Size = if removable then UDim2.new(1, -34, 1, 0) else UDim2.new(1, 0, 1, 0)
		end
		addOptionButton.Visible = #optionBoxes < MAX_POLL_OPTIONS
	end

	local function addOptionRow()
		if #optionBoxes >= MAX_POLL_OPTIONS then return end
		local palette = opts.getThemeColors()

		local row = Instance.new("Frame")
		row.Name = "OptionRow"
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundTransparency = 1
		row.ZIndex = z
		row.Parent = optionsContainer

		local box = Instance.new("TextBox")
		box.Name = "Answer"
		box.Size = UDim2.new(1, -34, 1, 0)
		box.BackgroundColor3 = palette.dialogInput
		box.TextColor3 = palette.dialogInputText
		box.PlaceholderColor3 = palette.placeholder
		box.FontFace = FONTS.body
		box.TextSize = 14
		box.Text = ""
		box.ClearTextOnFocus = false
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.BorderSizePixel = 0
		box.ZIndex = z
		box.Parent = row
		roundCorners(box)
		horizontalPadding(box)

		local removeButton = Instance.new("TextButton")
		removeButton.Name = "Remove"
		removeButton.AnchorPoint = Vector2.new(1, 0.5)
		removeButton.Position = UDim2.new(1, 0, 0.5, 0)
		removeButton.Size = UDim2.fromOffset(28, 28)
		removeButton.BackgroundTransparency = 1
		Icons.apply(removeButton, "close")
		removeButton.TextColor3 = palette.timestamp
		removeButton.TextSize = 14
		removeButton.ZIndex = z + 1
		removeButton.Parent = row

		removeButton.MouseButton1Click:Connect(function()
			if #optionBoxes <= MIN_POLL_OPTIONS then
				return -- required answers have no X; guard just in case
			end
			local index = table.find(optionBoxes, box)
			if index then
				table.remove(optionBoxes, index)
			end
			row:Destroy()
			refreshOptionRows()
		end)

		table.insert(optionBoxes, box)
		refreshOptionRows()
	end

	local self = {}

	--!
	-- Opens the dialog with an empty question and the required answers.
	--!
	function self.open()
		questionBox.Text = ""
		for _, box in ipairs(optionBoxes) do
			box.Parent:Destroy()
		end
		table.clear(optionBoxes)
		for _ = 1, MIN_POLL_OPTIONS do
			addOptionRow()
		end
		modal.open()
		questionBox:CaptureFocus()
	end

	function self.close()
		modal.close()
	end

	function self.isVisible(): boolean
		return modal.isVisible()
	end

	--!
	-- Re-applies the current palette to the dialog's content (the shell is
	-- recolored by the ModalKit).
	--!
	function self.recolor()
		local palette = opts.getThemeColors()
		questionHeading.TextColor3 = palette.messageText
		answersHeading.TextColor3 = palette.messageText
		questionBox.BackgroundColor3 = palette.dialogInput
		questionBox.TextColor3 = palette.dialogInputText
		questionBox.PlaceholderColor3 = palette.placeholder
		addOptionButton.BackgroundColor3 = palette.dialogSecondary
		addOptionButton.TextColor3 = palette.menuItemText or palette.messageText
		cancelButton.BackgroundColor3 = palette.dialogSecondary
		cancelButton.TextColor3 = palette.menuItemText or palette.messageText
		createButton.BackgroundColor3 = palette.dialogButton
		createButton.TextColor3 = palette.dialogButtonText
		for _, box in ipairs(optionBoxes) do
			box.BackgroundColor3 = palette.dialogInput
			box.TextColor3 = palette.dialogInputText
			box.PlaceholderColor3 = palette.placeholder
			local removeButton = box.Parent and box.Parent:FindFirstChild("Remove")
			if removeButton then
				removeButton.TextColor3 = palette.timestamp
			end
		end
	end

	-- Create: needs a question and at least MIN_POLL_OPTIONS answers;
	-- otherwise the cursor goes to the first empty required field
	local function submit()
		local question = trim(questionBox.Text)
		if question == "" then
			questionBox:CaptureFocus()
			return
		end

		local options = {}
		local firstEmpty
		for _, box in ipairs(optionBoxes) do
			local answer = trim(box.Text)
			if answer ~= "" then
				table.insert(options, answer)
			elseif not firstEmpty then
				firstEmpty = box
			end
		end
		if #options < MIN_POLL_OPTIONS then
			if firstEmpty then
				firstEmpty:CaptureFocus()
			end
			return
		end

		opts.onSubmit(question, options)
		modal.close()
	end

	addOptionButton.MouseButton1Click:Connect(addOptionRow)
	cancelButton.MouseButton1Click:Connect(function()
		modal.close()
	end)
	createButton.MouseButton1Click:Connect(submit)

	return self
end

return CreatePollDialog
