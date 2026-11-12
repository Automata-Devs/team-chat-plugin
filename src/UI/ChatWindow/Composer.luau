--[[
	Composer

	The bottom of the chat: the message box (growing with its text, markdown
	and @mentions styled as you type, spell check), the send and + buttons
	with the + menu (Create Poll, Attach Files), the reply / editing bar and
	the "is typing" line above it.

	Usage:
		local composer = Composer.create(ctx, hooks)
		composer.setReply(timestamp, sender, content, senderId)
		local height = composer.resize()
]]

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Author = require(script.Parent.Parent.Messages.Author)
local ComposerText = require(script.Parent.Parent.Text.ComposerText)
local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local MentionPills = require(script.Parent.Parent.Text.MentionPills)
local Preferences = require(script.Parent.Parent.Common.Preferences)
local Animation = require(script.Parent.Parent.Common.Animation)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)
local SpellCheck = require(script.Parent.Parent.Parent.Util.SpellCheck)
local SpellingMarks = require(script.Parent.Parent.Text.SpellingMarks)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local TypingBar = require(script.Parent.TypingBar)
local UsernameColors = require(script.Parent.Parent.Parent.Util.UsernameColors)

local FONT = Theme.FONT
local INPUT_HEIGHT = Theme.INPUT_HEIGHT
local MENU_WIDTH = Theme.MENU_WIDTH
local toHex = Theme.toHex

local MAX_INPUT_HEIGHT = 240
local REPLY_BAR_HEIGHT = 30

export type Hooks = {
	-- ContextMenu.createItem: the + menu's items look like the right-click menu's
	createMenuItem: (...any) -> TextButton,
	-- The text of a shown message, for editing it (nil when it isn't a text message)
	contentOf: (timestamp: number) -> string?,
	onCreatePoll: () -> (),
	onAttachFiles: () -> (),
}

local Composer = {}

function Composer.create(ctx, hooks: Hooks)
	local container: Frame = ctx.container

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Position = UDim2.new(0, 0, 1, -INPUT_HEIGHT)
	divider.BackgroundColor3 = ctx.palette.divider
	divider.BorderSizePixel = 0
	divider.Parent = container

	local inputFrame = Instance.new("Frame")
	inputFrame.Name = "InputFrame"
	inputFrame.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
	inputFrame.Position = UDim2.new(0, 0, 1, -INPUT_HEIGHT)
	inputFrame.BackgroundColor3 = ctx.palette.inputFrame
	inputFrame.BorderSizePixel = 0
	inputFrame.Parent = container

	local attachButton = Instance.new("TextButton")
	attachButton.Name = "AttachButton"
	attachButton.Size = UDim2.new(0, 33, 0, 33)
	attachButton.Position = UDim2.new(0, 8, 0, 8)
	attachButton.BackgroundColor3 = ctx.palette.attachButton
	Icons.apply(attachButton, "add")
	attachButton.TextColor3 = ctx.palette.attachIcon
	attachButton.TextSize = 18
	attachButton.AutoButtonColor = true
	attachButton.BorderSizePixel = 0
	attachButton.Parent = inputFrame

	local attachCorner = Instance.new("UICorner")
	attachCorner.CornerRadius = UDim.new(1, 0)
	attachCorner.Parent = attachButton

	-- The + menu pops up above the button, styled like the right-click menu
	local menuFrame = Instance.new("Frame")
	menuFrame.Name = "Menu"
	menuFrame.Size = UDim2.new(0, MENU_WIDTH, 0, 0)
	menuFrame.AutomaticSize = Enum.AutomaticSize.Y
	menuFrame.AnchorPoint = Vector2.new(0, 1)
	menuFrame.Position = UDim2.new(0, 4, 1, -(INPUT_HEIGHT + 8))
	menuFrame.BackgroundColor3 = ctx.palette.menuBack
	menuFrame.BorderSizePixel = 0
	menuFrame.Visible = false
	menuFrame.ZIndex = 20
	menuFrame.Parent = container

	local menuClickCatcher = Instance.new("TextButton")
	menuClickCatcher.Name = "MenuClickCatcher"
	menuClickCatcher.Size = UDim2.new(1, 0, 1, 0)
	menuClickCatcher.Position = UDim2.new(0, 0, 0, 0)
	menuClickCatcher.BackgroundTransparency = 1
	menuClickCatcher.Text = ""
	menuClickCatcher.AutoButtonColor = false
	menuClickCatcher.Visible = false
	menuClickCatcher.ZIndex = 9
	menuClickCatcher.Parent = container

	local menuCorner = Instance.new("UICorner")
	menuCorner.CornerRadius = UDim.new(0, 8)
	menuCorner.Parent = menuFrame

	local menuStroke = Instance.new("UIStroke")
	menuStroke.Color = ctx.palette.menuBorder
	menuStroke.Thickness = 1
	menuStroke.Parent = menuFrame

	local menuShadow = Instance.new("UIShadow")
	menuShadow.BlurRadius = UDim.new(0, 12)
	menuShadow.Color = Color3.fromRGB(0, 0, 0)
	menuShadow.Transparency = 0.5
	menuShadow.Parent = menuFrame

	local menuLayout = Instance.new("UIListLayout")
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Padding = UDim.new(0, 4)
	menuLayout.Parent = menuFrame

	local menuPad = Instance.new("UIPadding")
	menuPad.PaddingTop = UDim.new(0, 6)
	menuPad.PaddingBottom = UDim.new(0, 6)
	menuPad.PaddingLeft = UDim.new(0, 8)
	menuPad.PaddingRight = UDim.new(0, 8)
	menuPad.Parent = menuFrame

	local menuItemPoll = hooks.createMenuItem("Create Poll", "createPoll", 1, false, menuFrame, "composer.createPoll")
	menuItemPoll.Name = "MenuItemPoll"

	local menuItemFile =
		hooks.createMenuItem("Attach File(s)", "attachFile", 2, false, menuFrame, "composer.attachFiles")
	menuItemFile.Name = "MenuItemFile"

	local textBox = Instance.new("TextBox")
	textBox.Name = "InputBox"
	textBox.Size = UDim2.new(1, -98, 0, 33)
	textBox.Position = UDim2.new(0, 49, 0, 8)
	textBox.BackgroundColor3 = ctx.palette.inputBox
	textBox.TextColor3 = ctx.palette.textBoxText
	textBox.PlaceholderText = Language.t("composer.placeholder")
	textBox.PlaceholderColor3 = ctx.palette.placeholder
	textBox.Font = FONT
	textBox.TextSize = 14
	textBox.TextScaled = false
	textBox.TextWrapped = true
	-- MultiLine so text wraps while typing (a single-line TextBox scrolls
	-- sideways until it loses focus); MessageController turns Enter into send
	textBox.MultiLine = true
	textBox.TextYAlignment = Enum.TextYAlignment.Center
	textBox.Text = ""
	textBox.ClearTextOnFocus = false
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.BorderSizePixel = 0
	textBox.ClipsDescendants = false
	textBox.Parent = inputFrame

	local textBoxCorner = Instance.new("UICorner")
	textBoxCorner.CornerRadius = UDim.new(1, 0)
	textBoxCorner.Parent = textBox

	local textBoxPadding = Instance.new("UIPadding")
	textBoxPadding.PaddingLeft = UDim.new(0, 7)
	textBoxPadding.PaddingRight = UDim.new(0, 5)
	textBoxPadding.PaddingTop = UDim.new(0, 5)
	textBoxPadding.PaddingBottom = UDim.new(0, 5)
	textBoxPadding.Parent = textBox
	-- A TextBox can't colour its own text: @mentions get a rounded tint behind them
	MentionPills.attach(textBox, ctx.palette)

	local composerText = ComposerText.attach(textBox, {
		getPalette = ctx.getPalette,
	})

	local spelling = SpellingMarks.attach(textBox, {
		getPalette = ctx.getPalette,
		isEnabled = function()
			return Preferences.values.spellCheck
		end,
	})
	-- Words added with "Add to dictionary", and the names of people here
	SpellCheck.addWords(Settings.getJson(Constants.SETTING_KEY_DICTIONARY, {}) or {})
	local function addPlayerNames(player: Player)
		SpellCheck.addWords({ player.Name, player.DisplayName })
	end
	for _, player in ipairs(Players:GetPlayers()) do
		addPlayerNames(player)
	end
	Lifetime.connect(Players.PlayerAdded, addPlayerNames)

	local sendButton = Instance.new("TextButton")
	sendButton.Name = "SendButton"
	sendButton.Size = UDim2.new(0, 33, 0, 33)
	sendButton.Position = UDim2.new(1, -41, 0, 8)
	sendButton.BackgroundColor3 = ctx.palette.sendButton
	Icons.apply(sendButton, "send", true)
	sendButton.TextColor3 = ctx.palette.sendButtonText
	sendButton.TextSize = 18
	sendButton.AutoButtonColor = true
	sendButton.BorderSizePixel = 0
	sendButton.Parent = inputFrame

	local sendCorner = Instance.new("UICorner")
	sendCorner.CornerRadius = UDim.new(1, 0)
	sendCorner.Parent = sendButton

	local replyBar = Instance.new("Frame")
	replyBar.Name = "ReplyBar"
	replyBar.Size = UDim2.new(1, 0, 0, REPLY_BAR_HEIGHT)
	replyBar.Position = UDim2.new(0, 0, 1, -(INPUT_HEIGHT + Theme.PREVIEW_HEIGHT + REPLY_BAR_HEIGHT))
	replyBar.BackgroundColor3 = ctx.palette.inputFrame
	replyBar.BorderSizePixel = 0
	replyBar.Visible = false
	replyBar.ZIndex = 10
	replyBar.Parent = container

	local replyChip = Instance.new("Frame")
	replyChip.Name = "ReplyChip"
	replyChip.Size = UDim2.new(1, -16, 1, -6)
	replyChip.Position = UDim2.new(0, 8, 0, 3)
	replyChip.BackgroundColor3 = ctx.palette.inputBox
	replyChip.BorderSizePixel = 0
	replyChip.ZIndex = 11
	replyChip.Parent = replyBar

	local replyChipCorner = Instance.new("UICorner")
	replyChipCorner.CornerRadius = UDim.new(1, 0)
	replyChipCorner.Parent = replyChip

	local replyText = Instance.new("TextLabel")
	replyText.Name = "ReplyText"
	replyText.Size = UDim2.new(1, -40, 1, 0)
	replyText.Position = UDim2.new(0, 12, 0, 0)
	replyText.BackgroundTransparency = 1
	replyText.TextColor3 = ctx.palette.timestamp
	replyText.Font = FONT
	replyText.TextSize = 13
	replyText.TextXAlignment = Enum.TextXAlignment.Left
	replyText.TextTruncate = Enum.TextTruncate.AtEnd
	replyText.RichText = true
	replyText.Text = ""
	replyText.BorderSizePixel = 0
	replyText.ZIndex = 12
	replyText.Parent = replyChip

	local replyCloseButton = Instance.new("TextButton")
	replyCloseButton.Name = "ReplyCloseButton"
	replyCloseButton.Size = UDim2.new(0, 18, 0, 18)
	replyCloseButton.AnchorPoint = Vector2.new(1, 0.5)
	replyCloseButton.Position = UDim2.new(1, -4, 0.5, 0)
	replyCloseButton.BackgroundColor3 = ctx.palette.menuBorder
	Icons.apply(replyCloseButton, "close")
	replyCloseButton.TextColor3 = ctx.palette.attachIcon
	replyCloseButton.TextSize = 12
	replyCloseButton.AutoButtonColor = true
	replyCloseButton.BorderSizePixel = 0
	replyCloseButton.ZIndex = 12
	replyCloseButton.Parent = replyChip

	local replyCloseCorner = Instance.new("UICorner")
	replyCloseCorner.CornerRadius = UDim.new(1, 0)
	replyCloseCorner.Parent = replyCloseButton

	local typingBar = TypingBar.create({
		container = container,
		getThemeColors = ctx.getPalette,
	})
	local typingLabel = typingBar.frame
	local lastTypingUsers = {}
	local typingActivityCallback: ((boolean) -> ())? = nil

	local function setTypingUsers(users)
		lastTypingUsers = users
		typingBar.setUsers(if Preferences.values.typingIndicator then users else {})
	end

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if typingActivityCallback then
			typingActivityCallback(#textBox.Text > 0)
		end
	end)
	textBox.FocusLost:Connect(function()
		if typingActivityCallback then
			typingActivityCallback(false)
		end
	end)

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		ctx.relayout()
	end)
	textBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		ctx.relayout()
	end)
	task.defer(function()
		ctx.relayout()
	end)

	local reply = {
		timestamp = nil :: number?,
		sender = nil :: string?,
		senderId = nil :: number?,
		content = nil :: string?,
		originalDeleted = false,
	}
	-- Editing your own message: its text is in the box and the reply bar says
	-- "Editing message" until it's saved or cancelled
	local editingTimestamp: number? = nil

	local function renderReplyText()
		if editingTimestamp then
			replyText.Text = Icons.inline("edit", false, 13) .. "  " .. Icons.escape(Language.t("reply.editing"))
			return
		end
		if reply.originalDeleted and reply.timestamp then
			replyText.Text = string.format(
				'<font color="%s"><i>%s</i></font>',
				toHex(ctx.palette.timestamp),
				Icons.escape(Language.t("reply.originalDeleted"))
			)
			return
		end
		if not reply.sender then
			replyText.Text = ""
			return
		end
		local escapedName = Icons.escape(Author.nameOf(reply.sender, reply.senderId))
		replyText.Text = Language.t("reply.replyingTo", {
			name = string.format(
				'<font color="%s"><b>%s</b></font>',
				toHex(UsernameColors.getNameColor(reply.sender)),
				escapedName
			),
		})
	end

	local function focusTextBox()
		pcall(function()
			textBox:CaptureFocus()
		end)
	end

	local function hideReplyReference()
		editingTimestamp = nil
		reply.timestamp = nil
		reply.sender = nil
		reply.senderId = nil
		reply.content = nil
		reply.originalDeleted = false
		replyBar.Visible = false
		ctx.relayout()
	end

	replyCloseButton.MouseButton1Click:Connect(function()
		if editingTimestamp then
			textBox.Text = "" -- cancelling an edit drops the edited text
		end
		hideReplyReference()
	end)

	local function setAttachMenuOpen(open: boolean)
		menuFrame.Visible = open
		menuClickCatcher.Visible = open
	end

	attachButton.MouseButton1Click:Connect(function()
		setAttachMenuOpen(not menuFrame.Visible)
	end)
	menuClickCatcher.MouseButton1Click:Connect(function()
		if not ctx.pointer.isInside(menuFrame, ctx.pointer.mousePosition()) then
			setAttachMenuOpen(false)
		end
	end)
	menuItemPoll.MouseButton1Click:Connect(function()
		setAttachMenuOpen(false)
		hooks.onCreatePoll()
	end)
	menuItemFile.MouseButton1Click:Connect(function()
		setAttachMenuOpen(false)
		hooks.onAttachFiles()
	end)

	for _, gui in ipairs({ typingLabel, replyBar }) do
		gui:GetPropertyChangedSignal("Visible"):Connect(function()
			if gui.Visible then
				Animation.fadeIn(gui, "quick")
			end
		end)
	end

	local self = {}
	self.textBox = textBox
	self.sendButton = sendButton
	self.spelling = spelling
	self.setAttachMenuOpen = setAttachMenuOpen
	self.setTypingUsers = setTypingUsers
	self.clearReply = hideReplyReference

	--[=[
		Adds a word to your spell check dictionary (saved in plugin settings).
	]=]
	function self.addToDictionary(word: string)
		SpellCheck.addWords({ word })
		local saved = Settings.getJson(Constants.SETTING_KEY_DICTIONARY, {})
		if type(saved) ~= "table" then
			saved = {}
		end
		if not table.find(saved, string.lower(word)) then
			table.insert(saved, string.lower(word))
			Settings.setJson(Constants.SETTING_KEY_DICTIONARY, saved)
		end
		spelling.refresh()
	end

	--[=[
		Registers fn(typing: boolean), called as you type and when the box loses focus.
	]=]
	function self.onTypingActivity(fn)
		typingActivityCallback = fn
	end

	--[=[
		Shows the reply bar for a message and focuses the box.
	]=]
	function self.setReply(timestamp: number, sender: string, content: string, senderId: number?)
		reply.timestamp = timestamp
		reply.sender = sender
		reply.senderId = senderId
		reply.content = content
		reply.originalDeleted = false

		renderReplyText()
		replyBar.Visible = true
		ctx.relayout()
		focusTextBox()
	end

	--[=[
		The pending reply: timestamp, sender, content, senderId (nil when none).
	]=]
	function self.getReply()
		if reply.timestamp then
			return reply.timestamp, reply.sender, reply.content, reply.senderId
		end
		return nil
	end

	--[=[
		Starts editing one of your messages: its text goes into the message box.
	]=]
	function self.startEdit(timestamp: number)
		local content = hooks.contentOf(timestamp)
		if content == nil then
			return
		end
		hideReplyReference()
		editingTimestamp = timestamp
		textBox.Text = content
		renderReplyText()
		replyBar.Visible = true
		ctx.relayout()
		focusTextBox()
		textBox.CursorPosition = #textBox.Text + 1
	end

	function self.editingTimestamp(): number?
		return editingTimestamp
	end

	--[=[
		The message being replied to was deleted.
	]=]
	function self.markReplyDeleted(timestamp: number)
		if reply.timestamp == timestamp then
			reply.originalDeleted = true
			renderReplyText()
		end
	end

	--[=[
		Clears the box for another conversation (an unsaved edit is dropped).
	]=]
	function self.reset()
		if editingTimestamp then
			textBox.Text = ""
		end
		hideReplyReference()
	end

	function self.setPlaceholder(text: string)
		textBox.PlaceholderText = text
	end

	--[=[
		Grows the box with its wrapped text; returns the composer's height.
	]=]
	function self.resize(): number
		-- TextBounds is clipped to the box's current height, so measure the
		-- wrapped text at the box's inner width instead
		local horizontalPadding = textBoxPadding.PaddingLeft.Offset + textBoxPadding.PaddingRight.Offset
		local verticalPadding = textBoxPadding.PaddingTop.Offset + textBoxPadding.PaddingBottom.Offset
		local availableWidth = math.max(60, textBox.AbsoluteSize.X - horizontalPadding)
		local measuredHeight = textBox.TextSize
		local ok, bounds = pcall(function()
			local measuredText = textBox.Text == "" and " " or textBox.Text
			return TextService:GetTextSize(
				measuredText,
				textBox.TextSize,
				textBox.Font,
				Vector2.new(availableWidth, 100000)
			)
		end)
		if ok and bounds then
			measuredHeight = bounds.Y
		end

		-- The box is at least 33px; the composer adds 8px above and below it
		local wantedBoxHeight = math.max(33, math.ceil(measuredHeight) + verticalPadding)
		local composerHeight = math.clamp(wantedBoxHeight + 16, INPUT_HEIGHT, MAX_INPUT_HEIGHT)
		inputFrame.Size = UDim2.new(1, 0, 0, composerHeight)
		inputFrame.Position = UDim2.new(0, 0, 1, -composerHeight)
		local textBoxHeight = composerHeight - 16
		textBox.Size = UDim2.new(1, -98, 0, textBoxHeight)
		-- A pill while single-line; corners stay at most 16px as it grows
		textBoxCorner.CornerRadius = UDim.new(0, math.min(textBoxHeight / 2, 16))
		attachButton.Position = UDim2.new(0, 8, 1, -41)
		sendButton.Position = UDim2.new(1, -41, 1, -41)
		menuFrame.Position = UDim2.new(0, 4, 1, -(composerHeight + 8))
		return composerHeight
	end

	--[=[
		Stacks the reply bar, divider and typing line above the composer and
		the attachment preview; returns the total space taken at the bottom.
	]=]
	function self.placeBars(composerHeight: number, previewSpace: number): number
		local replySpace = if replyBar.Visible then REPLY_BAR_HEIGHT else 0
		local barSpace = previewSpace + replySpace
		divider.Position = UDim2.new(0, 0, 1, -(composerHeight + barSpace))
		replyBar.Position = UDim2.new(0, 0, 1, -(composerHeight + previewSpace + REPLY_BAR_HEIGHT))
		typingLabel.Position = UDim2.new(0, 10, 1, -(composerHeight + barSpace + 20))
		return composerHeight + barSpace
	end

	--[=[
		Re-draws the text built by code (after a language change).
	]=]
	function self.retranslate()
		setTypingUsers(lastTypingUsers)
		renderReplyText()
	end

	--[=[
		Re-applies the typing indicator setting.
	]=]
	function self.refreshTyping()
		setTypingUsers(lastTypingUsers)
	end

	function self.recolor()
		local palette = ctx.palette
		divider.BackgroundColor3 = palette.divider
		inputFrame.BackgroundColor3 = palette.inputFrame
		textBox.BackgroundColor3 = palette.inputBox
		MentionPills.recolor(textBox, palette)
		composerText.recolor()
		spelling.recolor()
		textBox.TextColor3 = palette.textBoxText
		textBox.PlaceholderColor3 = palette.placeholder
		sendButton.BackgroundColor3 = palette.sendButton
		sendButton.TextColor3 = palette.sendButtonText
		attachButton.BackgroundColor3 = palette.attachButton
		attachButton.TextColor3 = palette.attachIcon
		typingBar.recolor()
		-- The + menu's items are recolored with the right-click menu's
		menuFrame.BackgroundColor3 = palette.menuBack
		menuStroke.Color = palette.menuBorder

		replyBar.BackgroundColor3 = palette.inputFrame
		replyChip.BackgroundColor3 = palette.inputBox
		replyText.TextColor3 = palette.timestamp
		replyCloseButton.BackgroundColor3 = palette.menuBorder
		replyCloseButton.TextColor3 = palette.attachIcon
		renderReplyText()
	end

	return self
end

return Composer
