--!
-- PollDialog
-- Creates the poll/video creation dialog overlay.
-- Returns a table of element references for wiring up behavior.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT
local MAX_POLL_OPTIONS = Theme.MAX_POLL_OPTIONS

local PollDialog = {}

--!
-- Creates the poll dialog overlay and all child elements.
-- @param themeColors table - current theme color palette
-- @return table - { dialog, dialogFrame, title, closeButton, questionHeading, questionBox, answersHeading, optionsContainer, addOptionButton, buttonsRow, cancelButton, createButton }
--!
function PollDialog.create(themeColors)
	local pollDialog = Instance.new("Frame")
	pollDialog.Name = "PollDialog"
	pollDialog.Size = UDim2.new(1, 0, 1, 0)
	pollDialog.Position = UDim2.new(0, 0, 0, 0)
	pollDialog.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	pollDialog.BackgroundTransparency = 0.4
	pollDialog.BorderSizePixel = 0
	pollDialog.Visible = false
	pollDialog.ZIndex = 20

	local dialogFrame = Instance.new("Frame")
	dialogFrame.Name = "DialogFrame"
	dialogFrame.Size = UDim2.new(0.9, 0, 0, 0)
	dialogFrame.AutomaticSize = Enum.AutomaticSize.Y
	dialogFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	dialogFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	dialogFrame.BackgroundColor3 = themeColors.dialogBack
	dialogFrame.BorderSizePixel = 0
	dialogFrame.ZIndex = 21
	dialogFrame.Parent = pollDialog

	local dialogSizeConstraint = Instance.new("UISizeConstraint")
	dialogSizeConstraint.MaxSize = Vector2.new(520, 540)
	dialogSizeConstraint.Parent = dialogFrame

	local dialogCorner = Instance.new("UICorner")
	dialogCorner.CornerRadius = UDim.new(0, 10)
	dialogCorner.Parent = dialogFrame

	local dialogStroke = Instance.new("UIStroke")
	dialogStroke.Name = "DialogStroke"
	dialogStroke.Color = themeColors.dialogBorder
	dialogStroke.Thickness = 1
	dialogStroke.Parent = dialogFrame

	local dialogLayout = Instance.new("UIListLayout")
	dialogLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dialogLayout.Padding = UDim.new(0, 9)
	dialogLayout.Parent = dialogFrame

	local dialogPad = Instance.new("UIPadding")
	dialogPad.PaddingTop = UDim.new(0, 18)
	dialogPad.PaddingBottom = UDim.new(0, 18)
	dialogPad.PaddingLeft = UDim.new(0, 18)
	dialogPad.PaddingRight = UDim.new(0, 18)
	dialogPad.Parent = dialogFrame

	-- Title row
	local dialogTitle = Instance.new("TextLabel")
	dialogTitle.Name = "Title"
	dialogTitle.Size = UDim2.new(1, 0, 0, 28)
	dialogTitle.BackgroundTransparency = 1
	dialogTitle.Text = "Create a Poll"
	dialogTitle.TextColor3 = themeColors.messageText
	dialogTitle.Font = Enum.Font.BuilderSansBold
	dialogTitle.TextSize = 18
	dialogTitle.TextXAlignment = Enum.TextXAlignment.Left
	dialogTitle.LayoutOrder = 1
	dialogTitle.ZIndex = 22
	dialogTitle.BorderSizePixel = 0
	dialogTitle.Parent = dialogFrame

	local closeDialogButton = Instance.new("TextButton")
	closeDialogButton.Name = "Close"
	closeDialogButton.Size = UDim2.new(0, 28, 0, 28)
	closeDialogButton.Position = UDim2.new(1, -28, 0, 0)
	closeDialogButton.BackgroundTransparency = 1
	closeDialogButton.Text = "\u{00D7}"
	closeDialogButton.TextColor3 = themeColors.timestamp
	closeDialogButton.Font = FONT
	closeDialogButton.TextSize = 24
	closeDialogButton.AutoButtonColor = true
	closeDialogButton.BorderSizePixel = 0
	closeDialogButton.ZIndex = 23
	closeDialogButton.Parent = dialogTitle

	-- Question heading
	local questionHeading = Instance.new("TextLabel")
	questionHeading.Name = "QuestionHeading"
	questionHeading.Size = UDim2.new(1, 0, 0, 18)
	questionHeading.BackgroundTransparency = 1
	questionHeading.Text = "Question"
	questionHeading.TextColor3 = themeColors.messageText
	questionHeading.Font = Enum.Font.BuilderSansBold
	questionHeading.TextSize = 14
	questionHeading.TextXAlignment = Enum.TextXAlignment.Left
	questionHeading.LayoutOrder = 2
	questionHeading.ZIndex = 22
	questionHeading.BorderSizePixel = 0
	questionHeading.Parent = dialogFrame

	-- Question text box
	local pollQuestionBox = Instance.new("TextBox")
	pollQuestionBox.Name = "QuestionBox"
	pollQuestionBox.Size = UDim2.new(1, 0, 0, 40)
	pollQuestionBox.BackgroundColor3 = themeColors.dialogInput
	pollQuestionBox.TextColor3 = themeColors.dialogInputText
	pollQuestionBox.PlaceholderText = "Poll question..."
	pollQuestionBox.PlaceholderColor3 = themeColors.placeholder
	pollQuestionBox.Font = FONT
	pollQuestionBox.TextSize = 14
	pollQuestionBox.Text = ""
	pollQuestionBox.ClearTextOnFocus = false
	pollQuestionBox.TextXAlignment = Enum.TextXAlignment.Left
	pollQuestionBox.BorderSizePixel = 0
	pollQuestionBox.LayoutOrder = 3
	pollQuestionBox.ZIndex = 22
	pollQuestionBox.Parent = dialogFrame

	local questionCorner = Instance.new("UICorner")
	questionCorner.CornerRadius = UDim.new(0, 6)
	questionCorner.Parent = pollQuestionBox

	local questionPadding = Instance.new("UIPadding")
	questionPadding.PaddingLeft = UDim.new(0, 8)
	questionPadding.PaddingRight = UDim.new(0, 8)
	questionPadding.Parent = pollQuestionBox

	-- Answers heading
	local answersHeading = Instance.new("TextLabel")
	answersHeading.Name = "AnswersHeading"
	answersHeading.Size = UDim2.new(1, 0, 0, 18)
	answersHeading.BackgroundTransparency = 1
	answersHeading.Text = "Answers"
	answersHeading.TextColor3 = themeColors.messageText
	answersHeading.Font = Enum.Font.BuilderSansBold
	answersHeading.TextSize = 14
	answersHeading.TextXAlignment = Enum.TextXAlignment.Left
	answersHeading.LayoutOrder = 4
	answersHeading.ZIndex = 22
	answersHeading.BorderSizePixel = 0
	answersHeading.Parent = dialogFrame

	-- Options container
	local optionsContainer = Instance.new("Frame")
	optionsContainer.Name = "OptionsContainer"
	optionsContainer.Size = UDim2.new(1, 0, 0, 0)
	optionsContainer.AutomaticSize = Enum.AutomaticSize.Y
	optionsContainer.BackgroundTransparency = 1
	optionsContainer.LayoutOrder = 5
	optionsContainer.ZIndex = 22
	optionsContainer.Parent = dialogFrame

	local optionsLayout = Instance.new("UIListLayout")
	optionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	optionsLayout.Padding = UDim.new(0, 8)
	optionsLayout.Parent = optionsContainer

	-- Add option button
	local addOptionButton = Instance.new("TextButton")
	addOptionButton.Name = "AddOption"
	addOptionButton.Size = UDim2.new(1, 0, 0, 36)
	addOptionButton.BackgroundColor3 = themeColors.dialogSecondary
	addOptionButton.Text = "+  Add another answer"
	addOptionButton.TextColor3 = themeColors.menuItemText
	addOptionButton.Font = FONT
	addOptionButton.TextSize = 13
	addOptionButton.AutoButtonColor = true
	addOptionButton.BorderSizePixel = 0
	addOptionButton.LayoutOrder = 6
	addOptionButton.ZIndex = 22
	addOptionButton.Parent = dialogFrame

	local addOptionCorner = Instance.new("UICorner")
	addOptionCorner.CornerRadius = UDim.new(0, 6)
	addOptionCorner.Parent = addOptionButton

	-- Buttons row
	local dialogButtonsRow = Instance.new("Frame")
	dialogButtonsRow.Name = "ButtonsRow"
	dialogButtonsRow.Size = UDim2.new(1, 0, 0, 38)
	dialogButtonsRow.BackgroundTransparency = 1
	dialogButtonsRow.LayoutOrder = 7
	dialogButtonsRow.ZIndex = 22
	dialogButtonsRow.Parent = dialogFrame

	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "Cancel"
	cancelButton.Size = UDim2.new(0.5, -4, 1, 0)
	cancelButton.Position = UDim2.new(0, 0, 0, 0)
	cancelButton.BackgroundColor3 = themeColors.dialogSecondary
	cancelButton.Text = "Cancel"
	cancelButton.TextColor3 = themeColors.menuItemText
	cancelButton.Font = FONT
	cancelButton.TextSize = 14
	cancelButton.AutoButtonColor = true
	cancelButton.BorderSizePixel = 0
	cancelButton.ZIndex = 23
	cancelButton.Parent = dialogButtonsRow

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 6)
	cancelCorner.Parent = cancelButton

	local createPollButton = Instance.new("TextButton")
	createPollButton.Name = "Create"
	createPollButton.Size = UDim2.new(0.5, -4, 1, 0)
	createPollButton.Position = UDim2.new(0.5, 4, 0, 0)
	createPollButton.BackgroundColor3 = themeColors.dialogButton
	createPollButton.Text = "Create"
	createPollButton.TextColor3 = themeColors.dialogButtonText
	createPollButton.Font = FONT
	createPollButton.TextSize = 14
	createPollButton.AutoButtonColor = true
	createPollButton.BorderSizePixel = 0
	createPollButton.ZIndex = 23
	createPollButton.Parent = dialogButtonsRow

	local createCorner = Instance.new("UICorner")
	createCorner.CornerRadius = UDim.new(0, 6)
	createCorner.Parent = createPollButton

	-- Click catcher overlay (blocks clicks through the modal)
	local clickCatcher = Instance.new("TextButton")
	clickCatcher.Name = "ClickCatcher"
	clickCatcher.Size = UDim2.new(1, 0, 1, 0)
	clickCatcher.BackgroundColor3 = Color3.new(0, 0, 0)
	clickCatcher.BackgroundTransparency = 0.5
	clickCatcher.Text = ""
	clickCatcher.AutoButtonColor = false
	clickCatcher.ZIndex = 19
	clickCatcher.Parent = pollDialog

	return {
		dialog = pollDialog,
		dialogFrame = dialogFrame,
		title = dialogTitle,
		closeButton = closeDialogButton,
		questionHeading = questionHeading,
		questionBox = pollQuestionBox,
		answersHeading = answersHeading,
		optionsContainer = optionsContainer,
		addOptionButton = addOptionButton,
		buttonsRow = dialogButtonsRow,
		cancelButton = cancelButton,
		createButton = createPollButton,
	}
end

--!
-- Re-themes the poll dialog.
-- @param elements table - the elements table returned from create()
-- @param themeColors table - current theme color palette
--!
function PollDialog.recolor(elements, themeColors)
	elements.dialogFrame.BackgroundColor3 = themeColors.dialogBack

	local stroke = elements.dialogFrame:FindFirstChild("DialogStroke")
	if stroke then
		stroke.Color = themeColors.dialogBorder
	end

	elements.title.TextColor3 = themeColors.messageText
	elements.closeButton.TextColor3 = themeColors.timestamp
	elements.questionHeading.TextColor3 = themeColors.messageText
	elements.answersHeading.TextColor3 = themeColors.messageText
	elements.questionBox.BackgroundColor3 = themeColors.dialogInput
	elements.questionBox.TextColor3 = themeColors.dialogInputText
	elements.questionBox.PlaceholderColor3 = themeColors.placeholder
	elements.addOptionButton.BackgroundColor3 = themeColors.dialogSecondary
	elements.addOptionButton.TextColor3 = themeColors.menuItemText
	elements.cancelButton.BackgroundColor3 = themeColors.dialogSecondary
	elements.cancelButton.TextColor3 = themeColors.menuItemText
	elements.createButton.BackgroundColor3 = themeColors.dialogButton
	elements.createButton.TextColor3 = themeColors.dialogButtonText

	for _, optFrame in ipairs(elements.optionsContainer:GetChildren()) do
		if optFrame:IsA("Frame") and optFrame.Name:match("^Opt%d+$") then
			optFrame.BackgroundColor3 = themeColors.dialogInput
			local tb = optFrame:FindFirstChildWhichIsA("TextBox")
			if tb then
				tb.BackgroundColor3 = themeColors.dialogInput
				tb.TextColor3 = themeColors.dialogInputText
				tb.PlaceholderColor3 = themeColors.placeholder
			end
			local rm = optFrame:FindFirstChildWhichIsA("TextButton")
			if rm then
				rm.BackgroundColor3 = themeColors.dialogSecondary
				rm.TextColor3 = themeColors.menuItemText
			end
		end
	end
end

return PollDialog