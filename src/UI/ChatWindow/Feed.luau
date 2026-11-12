--[[
	Feed

	The message list: rows in a scrolling frame, the scroll-to-bottom button,
	the empty state and the unread divider. It follows the bottom only while
	you're there, jumps to and flashes a replied-to message, and wires each
	row's right-click menu, drags, poll votes and bot buttons.

	Usage:
		local feed = Feed.create(ctx, hooks)
		feed.addMessage(sender, timestamp, content, imageUrl, replyRef, senderId)
		feed.place(topSpace, bottomSpace)
]]

local TweenService = game:GetService("TweenService")

local Attachments = require(script.Parent.Attachments)
local Author = require(script.Parent.Parent.Messages.Author)
local Animation = require(script.Parent.Parent.Common.Animation)
local BadgeIcons = require(script.Parent.Parent.Components.BadgeIcons)
local Browser = require(script.Parent.Parent.Parent.Core.Browser)
local CommandEmbed = require(script.Parent.Parent.Embeds.Providers.CommandEmbed)
local Components = require(script.Parent.Parent.Embeds.Components)
local Constants = require(script.Parent.Parent.Parent.Config.Constants)
local EmbedManager = require(script.Parent.Parent.Embeds.EmbedManager)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Markdown = require(script.Parent.Parent.Parent.Util.Markdown)
local MessageText = require(script.Parent.Parent.Text.MessageText)
local Messages = require(script.Parent.Parent.Messages)
local Preferences = require(script.Parent.Parent.Common.Preferences)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT
local FONTS = Theme.FONTS
local INPUT_HEIGHT = Theme.INPUT_HEIGHT
local toHex = Theme.toHex

local JUMP_SCROLL_TIME = 0.3
local FLASH_HOLD_TIME = 0.6
local FLASH_FADE_TIME = 1.2
local FLASH_START_TRANSPARENCY = 0.75
local SCROLL_BOTTOM_THRESHOLD = 24
local SCROLLBAR_FADE_DELAY = 1.75

export type Hooks = {
	-- Opens the right-click menu for a row
	showMenu: (timestamp: number, options: { [string]: any }) -> (),
	-- A reaction chip was clicked (adds or removes yours)
	toggleReaction: (target: string | number, emoji: string) -> (),
	-- The + after a row's reactions was clicked
	addReaction: (target: string | number) -> (),
}

local Feed = {}

function Feed.create(ctx, hooks: Hooks)
	local container: Frame = ctx.container
	local services = ctx.services

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "MessageList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -(INPUT_HEIGHT + ctx.topSpace()))
	scrollFrame.Position = UDim2.new(0, 0, 0, ctx.topSpace())
	scrollFrame.BackgroundColor3 = ctx.palette.scrollBack
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = ctx.palette.scrollBar
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	scrollFrame.Parent = container
	-- A badge tooltip would stay behind while the messages scroll away
	scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		ctx.tooltip.hide()
	end)

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.Parent = scrollFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 5)
	padding.Parent = scrollFrame

	Messages.group(scrollFrame, ctx.getPalette)

	local scrollButton = Instance.new("TextButton")
	scrollButton.Name = "ScrollToBottomButton"
	scrollButton.Size = UDim2.new(0, 33, 0, 33)
	scrollButton.AnchorPoint = Vector2.new(1, 1)
	scrollButton.Position = UDim2.new(1, -14, 1, -(INPUT_HEIGHT + 14))
	scrollButton.BackgroundColor3 = ctx.palette.menuBack
	Icons.apply(scrollButton, "scrollDown")
	scrollButton.TextColor3 = ctx.palette.menuItemText
	scrollButton.TextSize = 20
	scrollButton.AutoButtonColor = true
	scrollButton.BorderSizePixel = 0
	scrollButton.Visible = false
	scrollButton.ZIndex = 12
	scrollButton.Parent = container

	local scrollButtonCorner = Instance.new("UICorner")
	scrollButtonCorner.CornerRadius = UDim.new(1, 0)
	scrollButtonCorner.Parent = scrollButton

	local scrollButtonStroke = Instance.new("UIStroke")
	scrollButtonStroke.Color = ctx.palette.menuBorder
	scrollButtonStroke.Thickness = 1
	scrollButtonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- the button, not its arrow
	scrollButtonStroke.Parent = scrollButton

	local scrollButtonShadow = Instance.new("UIShadow")
	scrollButtonShadow.BlurRadius = UDim.new(0, 8)
	scrollButtonShadow.Color = Color3.fromRGB(0, 0, 0)
	scrollButtonShadow.Transparency = 0.55
	scrollButtonShadow.Parent = scrollButton

	-- The list uses AutomaticCanvasSize, so AbsoluteCanvasSize (not
	-- CanvasSize) holds the real content height
	local isScrollAtBottom = true
	local function getMaxScroll()
		return math.max(0, scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteSize.Y)
	end
	local function scrollToBottom()
		scrollFrame.CanvasPosition = Vector2.new(0, getMaxScroll())
	end

	local activeFlashes = {} -- [row] = Tween, so a second click restarts the flash

	local function flashMessage(target)
		if activeFlashes[target] then
			activeFlashes[target]:Cancel()
		end
		local palette = ctx.palette
		local fadeInfo =
			TweenInfo.new(FLASH_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, FLASH_HOLD_TIME)
		local tween
		if target:GetAttribute("HoverHighlight") then
			-- Tint the hover surface; a message that mentions you gets its gold look back after
			local mentionGradient = target:FindFirstChild("MentionGradient") :: UIGradient?
			if mentionGradient then
				mentionGradient.Enabled = false
			end
			target.BackgroundColor3 = palette.sendButton
			target.BackgroundTransparency = FLASH_START_TRANSPARENCY
			tween = TweenService:Create(target, fadeInfo, { BackgroundTransparency = 1 })
			tween.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					target.BackgroundColor3 = ctx.palette.menuItemHover
					if target:GetAttribute("Mentioned") then
						Messages.applyMention(target, ctx.palette, target:GetAttribute("Content"))
					end
				end
			end)
		else
			-- Poll and announcement cards light up their outline instead
			local stroke = target:FindFirstChildOfClass("UIStroke")
			if not stroke then
				return
			end
			stroke.Color = palette.sendButton
			stroke.Transparency = 0
			tween = TweenService:Create(stroke, fadeInfo, { Color = palette.divider, Transparency = 0.35 })
		end
		activeFlashes[target] = tween
		tween.Completed:Connect(function()
			if activeFlashes[target] == tween then
				activeFlashes[target] = nil
			end
		end)
		tween:Play()
	end

	--[=[
		Scrolls a message into the middle of the list and flashes it.
	]=]
	local function jumpToMessage(timestamp: number)
		local target
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("GuiObject") and child:GetAttribute("Timestamp") == timestamp then
				target = child
				break
			end
		end
		if not target then
			return
		end

		local top = target.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y + scrollFrame.CanvasPosition.Y
		local y = math.clamp(top - (scrollFrame.AbsoluteSize.Y - target.AbsoluteSize.Y) / 2, 0, getMaxScroll())
		TweenService:Create(
			scrollFrame,
			TweenInfo.new(JUMP_SCROLL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CanvasPosition = Vector2.new(0, y) }
		):Play()
		flashMessage(target)
	end
	Messages.setJumpHandler(jumpToMessage)

	local function updateScrollState()
		isScrollAtBottom = scrollFrame.CanvasPosition.Y >= getMaxScroll() - SCROLL_BOTTOM_THRESHOLD
		scrollButton.Visible = not isScrollAtBottom
	end

	-- Scrolling by hand never forces the position; growing content follows
	-- the bottom only when you were already there
	scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(updateScrollState)

	local function updateScrollStateAndFollow()
		local wasAtBottom = isScrollAtBottom
		updateScrollState()
		if wasAtBottom then
			scrollToBottom()
		end
	end

	scrollFrame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(updateScrollStateAndFollow)
	scrollFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScrollStateAndFollow)

	scrollButton.MouseButton1Click:Connect(function()
		scrollToBottom()
		scrollButton.Visible = false
	end)

	-- The scrollbar shows while scrolling or growing, then fades out
	local scrollFadeToken = 0
	local scrollFadeTween = nil
	local function hideScrollBar()
		if scrollFadeTween then
			scrollFadeTween:Cancel()
		end
		scrollFadeTween = TweenService:Create(
			scrollFrame,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ ScrollBarImageTransparency = 1 }
		)
		scrollFadeTween:Play()
	end
	local function pulseScrollBar()
		scrollFadeToken += 1
		local token = scrollFadeToken
		if scrollFadeTween then
			scrollFadeTween:Cancel()
		end
		scrollFrame.ScrollBarImageTransparency = 0
		task.delay(SCROLLBAR_FADE_DELAY, function()
			if scrollFadeToken == token then
				hideScrollBar()
			end
		end)
	end
	scrollFrame.ScrollBarImageTransparency = 1
	scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(pulseScrollBar)
	scrollFrame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(pulseScrollBar)

	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.Size = UDim2.new(1, 0, 1, -(INPUT_HEIGHT + ctx.topSpace()))
	emptyState.Position = UDim2.new(0, 0, 0, ctx.topSpace())
	emptyState.BackgroundTransparency = 1
	emptyState.BorderSizePixel = 0
	emptyState.Parent = container

	local emptyLayout = Instance.new("UIListLayout")
	emptyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	emptyLayout.FillDirection = Enum.FillDirection.Vertical
	emptyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	emptyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	emptyLayout.Padding = UDim.new(0, 10)
	emptyLayout.Parent = emptyState

	local emptyIcon = Instance.new("TextLabel")
	emptyIcon.Name = "Icon"
	emptyIcon.Size = UDim2.new(0, 48, 0, 48)
	emptyIcon.BackgroundTransparency = 1
	Icons.apply(emptyIcon, "emptyChat")
	emptyIcon.TextColor3 = ctx.palette.emptyTitle
	emptyIcon.TextSize = 36
	emptyIcon.LayoutOrder = 1
	emptyIcon.BorderSizePixel = 0
	emptyIcon.Parent = emptyState

	local emptyTitleLabel = Instance.new("TextLabel")
	emptyTitleLabel.Name = "Title"
	emptyTitleLabel.Size = UDim2.new(1, -20, 0, 24)
	emptyTitleLabel.BackgroundTransparency = 1
	emptyTitleLabel.Text = Language.t("empty.title")
	emptyTitleLabel.TextColor3 = ctx.palette.emptyTitle
	emptyTitleLabel.FontFace = FONTS.display
	emptyTitleLabel.TextSize = 17
	emptyTitleLabel.LayoutOrder = 2
	emptyTitleLabel.BorderSizePixel = 0
	emptyTitleLabel.Parent = emptyState

	local emptySubtitle = Instance.new("TextLabel")
	emptySubtitle.Name = "Subtitle"
	emptySubtitle.Size = UDim2.new(1, -30, 0, 20)
	emptySubtitle.BackgroundTransparency = 1
	emptySubtitle.Text = Language.t("empty.subtitle")
	emptySubtitle.TextColor3 = ctx.palette.emptySubtitle
	emptySubtitle.Font = FONT
	emptySubtitle.TextSize = 13
	emptySubtitle.TextWrapped = true
	emptySubtitle.LayoutOrder = 3
	emptySubtitle.BorderSizePixel = 0
	emptySubtitle.Parent = emptyState

	local function hideEmptyState()
		emptyState.Visible = false
	end

	local function showEmptyStateIfNoMessages()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") and child.Name:match("^Message_") then
				emptyState.Visible = false
				return
			end
		end
		emptyState.Visible = true
	end

	local pinnedTimestamps: { [number]: boolean } = {}
	local pollContainers = {}
	local voteHandler: ((number, number) -> ())? = nil

	local function colorUnreadDivider(unreadDivider: Instance)
		for _, part in ipairs(unreadDivider:GetDescendants()) do
			if part.Name == "Line" then
				(part :: Frame).BackgroundColor3 = ctx.palette.danger
			elseif part.Name == "Tag" then
				(part :: TextLabel).BackgroundColor3 = ctx.palette.danger;
				(part :: TextLabel).TextColor3 = Color3.new(1, 1, 1)
			end
		end
	end

	-- Replaces a reply's quoted line with "Original message deleted"
	local function markReplyDeleted(row)
		row:SetAttribute("ReplyOriginalDeleted", true)
		local ref = row:FindFirstChild("ReplyReference", true)
		if not ref then
			return
		end
		local label = ref:FindFirstChild("ReplyLabel", true)
		if label and label:IsA("TextLabel") then
			label.RichText = true
			label.Text =
				string.format('<font color="%s"><i>Original message deleted</i></font>', toHex(ctx.palette.timestamp))
		end
	end

	-- A reply whose original isn't in the chat (deleted before the plugin
	-- loaded) is marked as deleted
	local function checkReplyTarget(row, replyRef)
		if not replyRef or not replyRef.timestamp then
			return
		end
		task.delay(1, function()
			if not row.Parent then
				return
			end
			for _, child in ipairs(scrollFrame:GetChildren()) do
				if child ~= row and child:GetAttribute("Timestamp") == replyRef.timestamp then
					-- Older replies don't store the original author's id: use the original's
					if not replyRef.senderId then
						Messages.setReplyAvatar(row, child:GetAttribute("SenderId"), ctx.palette)
					end
					return
				end
			end
			markReplyDeleted(row)
		end)
	end

	local function setReplyAttributes(row, replyRef)
		if replyRef then
			row:SetAttribute("ReplyToTimestamp", replyRef.timestamp)
			row:SetAttribute("ReplyToSender", replyRef.sender)
			row:SetAttribute("ReplyToContent", replyRef.content)
		end
	end

	-- Right-click on a row that only offers reactions (polls, files, announcements)
	local function connectReactMenu(row, timestamp: number)
		row.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				hooks.showMenu(timestamp, {
					canReact = ctx.userId > 0,
					messageId = row:GetAttribute("MessageId"),
				})
			end
		end)
	end

	local function attachEmbeds(row, label: TextLabel)
		local urls = MessageText.urls(label)
		if #urls > 0 and Preferences.values.linkPreviews then
			EmbedManager.attach(row, urls, ctx.palette, { plugin = ctx.plugin })
		end
	end

	local self = {}
	self.frame = scrollFrame
	self.jumpTo = jumpToMessage

	--[=[
		Adds a system message only you see (not saved), with a way to dismiss it.
	]=]
	function self.addSystemMessage(text)
		hideEmptyState()
		local row = Messages.text("System", os.time(), text, nil, ctx.palette)
		row:SetAttribute("Sender", "System")
		row:SetAttribute("Content", text)
		row:SetAttribute("Timestamp", os.time())
		row:SetAttribute("IsSystem", true)
		Messages.addOnlyYouNote(row, ctx.palette, function()
			row:Destroy()
		end)
		row.Parent = scrollFrame
		return row
	end

	function self.addMessage(sender, timestamp, content, imageUrl, replyRef, senderId)
		hideEmptyState()
		local row = Messages.text(sender, timestamp, content, imageUrl, ctx.palette, replyRef, senderId)
		row:SetAttribute("Sender", sender)
		row:SetAttribute("Content", content)
		row:SetAttribute("Timestamp", timestamp)
		if imageUrl then
			row:SetAttribute("ImageUrl", imageUrl)
		end
		setReplyAttributes(row, replyRef)

		local textLabel = row:FindFirstChild("TextContent")
		if textLabel and textLabel:IsA("TextLabel") then
			MessageText.attachClicks(textLabel, function(url)
				self.addSystemMessage(Language.t("links.copied", { url = url }))
			end)
			attachEmbeds(row, textLabel)
		end

		row.Parent = scrollFrame
		checkReplyTarget(row, replyRef)

		if imageUrl and imageUrl ~= "" then
			local imageAttachment = row:FindFirstChild("ImageAttachment")
			if imageAttachment and imageAttachment:IsA("ImageLabel") then
				imageAttachment.Active = true
				imageAttachment.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						ctx.plugin:StartDrag({
							MimeType = Attachments.MIME_TYPE,
							Data = "Image|" .. imageUrl .. "|Image",
							DragIcon = "",
							DragWidget = imageAttachment,
						})
					end
				end)
			end
		end

		row.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				-- Edit and Delete only on your own messages; a public bot message
				-- can be deleted by whoever ran its command
				local myUserId = ctx.userId
				local isMine = myUserId > 0 and senderId == myUserId and sender ~= "System"
				local ranIt = myUserId > 0
					and row:GetAttribute("BotMessage") == true
					and (row:GetAttribute("SaidBy") == myUserId or row:GetAttribute("BotOwner") == myUserId)
				-- Anyone signed in can pin, except answers only they can see
				local canPin = myUserId > 0 and not row:GetAttribute("Ephemeral")
				hooks.showMenu(timestamp, {
					canEdit = isMine,
					canDelete = isMine or ranIt,
					canPin = canPin,
					pinned = pinnedTimestamps[timestamp] == true,
					canReact = canPin,
					messageId = row:GetAttribute("MessageId"),
				})
			end
		end)
		return row
	end

	--[=[
		Shows a message's new text after an edit (here or by its author
		elsewhere): text, "(edited)", clickable links and link previews.
	]=]
	function self.updateMessage(timestamp: number, content: string, edited: boolean)
		for _, child in ipairs(scrollFrame:GetChildren()) do
			local label = child:FindFirstChild("TextContent")
			if child:GetAttribute("Timestamp") == timestamp and label and child:FindFirstChild("Author") then
				child:SetAttribute("Content", content)
				child:SetAttribute("Edited", edited)
				Messages.setBody(child, ctx.palette)
				for _, embed in ipairs(child:GetChildren()) do
					if embed.Name == "Embed" then
						embed:Destroy()
					end
				end
				attachEmbeds(child, label)
				return
			end
		end
	end

	--[=[
		The text of one of the shown text messages (nil when it isn't one).
	]=]
	function self.contentOf(timestamp: number): string?
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:GetAttribute("Timestamp") == timestamp and child:FindFirstChild("TextContent") then
				return child:GetAttribute("Content") or ""
			end
		end
		return nil
	end

	function self.addAnnouncement(sender, timestamp, content, replyRef)
		hideEmptyState()
		local row = Messages.announcement(sender, timestamp, content, ctx.palette, replyRef)
		row:SetAttribute("Sender", sender)
		row:SetAttribute("Timestamp", timestamp)
		row:SetAttribute("Content", content)
		row:SetAttribute("IsAnnouncement", true)
		setReplyAttributes(row, replyRef)
		row.Parent = scrollFrame
		checkReplyTarget(row, replyRef)
		connectReactMenu(row, timestamp)
	end

	function self.addPoll(sender, timestamp, pollData, replyRef, senderId)
		hideEmptyState()
		local row = Messages.poll(sender, timestamp, pollData, ctx.palette, replyRef, senderId)
		row:SetAttribute("Sender", sender)
		row:SetAttribute("Timestamp", timestamp)
		row:SetAttribute("IsPoll", true)
		setReplyAttributes(row, replyRef)
		row.Parent = scrollFrame
		pollContainers[timestamp] = row
		checkReplyTarget(row, replyRef)

		Messages.updatePollVotes(row, pollData, ctx.palette)

		for i = 1, #pollData.options do
			local optionFrame = row:FindFirstChild("Option_" .. i, true)
			if optionFrame then
				optionFrame.MouseButton1Click:Connect(function()
					if voteHandler then
						voteHandler(timestamp, i)
					end
				end)
			end
		end

		connectReactMenu(row, timestamp)
	end

	function self.updatePoll(timestamp, pollData)
		local row = pollContainers[timestamp]
		if row then
			Messages.updatePollVotes(row, pollData, ctx.palette)
		end
	end

	function self.addFile(sender, timestamp, fileName, fileUrl, fileType, content, replyRef, senderId)
		hideEmptyState()
		local row =
			Messages.file(sender, timestamp, content, fileName, fileUrl, fileType, ctx.palette, replyRef, senderId)
		row:SetAttribute("Sender", sender)
		row:SetAttribute("Timestamp", timestamp)
		row:SetAttribute("FileName", fileName)
		row:SetAttribute("FileUrl", fileUrl)
		row:SetAttribute("FileType", fileType)
		row:SetAttribute("IsFile", true)
		setReplyAttributes(row, replyRef)
		row.Parent = scrollFrame
		checkReplyTarget(row, replyRef)

		-- File and audio cards can be dragged into the composer (but not by their controls)
		local card = row:FindFirstChild("FileCard") or row:FindFirstChild("AudioPlayerCard")
		if card and card:IsA("Frame") then
			card.Active = true
			card.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					for _, controlName in ipairs({ "PlayPauseButton", "Waveform", "DownloadButton" }) do
						local control = card:FindFirstChild(controlName, true)
						if
							control and ctx.pointer.isInside(control, Vector2.new(input.Position.X, input.Position.Y))
						then
							return
						end
					end
					ctx.plugin:StartDrag({
						MimeType = Attachments.MIME_TYPE,
						Data = (fileName or "file") .. "|" .. (fileUrl or "") .. "|" .. (fileType or "Other"),
						DragIcon = "",
						DragWidget = card,
					})
				end
			end)
		end

		connectReactMenu(row, timestamp)
	end

	-- Clicking a #tag selects the object and glides the camera to it
	MessageText.onTag = function(path: string)
		local instance = services.objectTags.resolve(path)
		if instance then
			services.objectTags.focus(instance, Animation.enabled())
		else
			self.addSystemMessage(Language.t("tag.notFound", { name = Markdown.tagName(path) }))
		end
	end

	--[=[
		A command's reply as a card (Embeds/Providers/CommandEmbed): a Team Chat
		message with the card instead of text.
	]=]
	function self.addSystemEmbed(spec)
		local row = self.addSystemMessage("")
		row:SetAttribute("HasCommandEmbed", true)
		local embed = CommandEmbed.fromSpec(spec, ctx.palette)
		embed.LayoutOrder = 2
		embed.Parent = row
		return row
	end

	--[=[
		A bot message: its text and/or card under a "<name> used /command"
		line, like a Discord bot's reply to a slash command.
		entry: { timestamp, content, saidBy, saidByName, command, embed?, components?, ... }
	]=]
	function self.addBotMessage(entry)
		local usedBy = if entry.saidByName
			then {
				sender = entry.saidByName,
				senderId = entry.saidBy,
				content = Language.t("bot.used", { command = entry.command or "" }),
			}
			else nil
		local content = if entry.thinking
			then "*" .. Language.t("bot.thinking", { bot = entry.botName or Constants.PLUGIN_TITLE }) .. "*"
			else entry.content or ""
		local row = self.addMessage(entry.botName or "System", entry.timestamp, content, nil, usedBy, 0)
		row:SetAttribute("Thinking", entry.thinking == true)
		row:SetAttribute("SaidBy", entry.saidBy or 0)
		row:SetAttribute("BotMessage", true)
		if entry.botId then
			-- A user-made bot: its own avatar and an (unverified) BOT tag
			row:SetAttribute("BotOwner", entry.botOwner or 0)
			Messages.markBot(row, entry.botAvatar, ctx.palette)
		end
		if entry.embed then
			row:SetAttribute("HasCommandEmbed", true)
			local embed = CommandEmbed.fromSpec(entry.embed, ctx.palette)
			embed.LayoutOrder = 2
			embed.Parent = row
		end
		-- Link buttons open; the others send an interaction to the bot
		if entry.components and entry.botId then
			local buttons = Components.build(entry.components, ctx.palette, function(button)
				if button.url then
					if not Browser.open(button.url) then
						self.addSystemMessage(Language.t("links.copied", { url = button.url }))
					end
					return
				end
				services.bots.clickButton({
					botId = entry.botId,
					customId = button.customId,
					message = entry.instance or row,
				})
			end)
			buttons.LayoutOrder = 3
			buttons.Parent = row
		end
		if entry.ephemeralLocal or entry.visibleTo then
			row:SetAttribute("Ephemeral", true)
			Messages.addOnlyYouNote(row, ctx.palette, function()
				if entry.onDismiss then
					entry.onDismiss()
				else
					row:Destroy()
				end
			end)
		end
		return row
	end

	--[=[
		Removes a message and marks the replies that pointed at it.
	]=]
	function self.removeMessage(timestamp: number)
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:GetAttribute("Timestamp") == timestamp then
				child.Parent = nil
				break
			end
		end
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:GetAttribute("ReplyToTimestamp") == timestamp then
				markReplyDeleted(child)
			end
		end
		showEmptyStateIfNoMessages()
	end

	function self.clear()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") and child.Name:match("^Message_") then
				child:Destroy()
			end
		end
		pollContainers = {}
		emptyState.Visible = true
	end

	--[=[
		Empties the list for another conversation (the unread divider too).
	]=]
	function self.reset()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		pollContainers = {}
		emptyState.Visible = true
	end

	--[=[
		The red "New" line above the first unread message (nil removes it).
	]=]
	function self.showUnreadDivider(timestamp: number?)
		local old = scrollFrame:FindFirstChild("UnreadDivider")
		if old then
			old:Destroy()
		end
		if not timestamp then
			return
		end
		local unreadDivider = Instance.new("Frame")
		unreadDivider.Name = "UnreadDivider"
		unreadDivider.BackgroundTransparency = 1
		unreadDivider.Size = UDim2.new(1, 0, 0, 18)
		-- Rows are ordered by timestamp: this sits just before the first unread one
		unreadDivider.LayoutOrder = math.floor(timestamp) - 1
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.new(0, 12, 0.5, 0)
		line.Size = UDim2.new(1, -24, 0, 1)
		line.BorderSizePixel = 0
		line.Parent = unreadDivider
		local tag = Instance.new("TextLabel")
		tag.Name = "Tag"
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -12, 0.5, 0)
		tag.Size = UDim2.fromOffset(0, 14)
		tag.AutomaticSize = Enum.AutomaticSize.X
		tag.BorderSizePixel = 0
		tag.FontFace = FONTS.bold
		tag.TextSize = 10
		tag.Parent = unreadDivider
		Language.bind(tag, "Text", "unread.new", nil, string.upper)
		local tagCorner = Instance.new("UICorner")
		tagCorner.CornerRadius = UDim.new(0, 4)
		tagCorner.Parent = tag
		local tagPadding = Instance.new("UIPadding")
		tagPadding.PaddingLeft = UDim.new(0, 5)
		tagPadding.PaddingRight = UDim.new(0, 5)
		tagPadding.Parent = tag
		colorUnreadDivider(unreadDivider)
		unreadDivider.Parent = scrollFrame
	end

	--[=[
		Shows the empty state for the open conversation: a DM's name and
		verified badge, or the team chat's text.
	]=]
	function self.setEmptyState(isDm: boolean, shown: string, verified: boolean?)
		Icons.apply(emptyIcon, if isDm then "directMessages" else "emptyChat")
		emptyTitleLabel.RichText = true
		emptyTitleLabel.Text = if isDm
			then Icons.escape(shown) .. BadgeIcons.verifiedSuffix(verified, 16)
			else Language.t("empty.title")
		emptySubtitle.Text = if isDm
			then Language.t("empty.dmSubtitle", { name = shown })
			else Language.t("empty.subtitle")
		emptySubtitle.Size = UDim2.new(1, -30, 0, if isDm then 36 else 20)
	end

	--[=[
		Re-reads the team chat's empty-state text (after a language change).
	]=]
	function self.retranslateEmptyState()
		emptyTitleLabel.Text = Language.t("empty.title")
		emptySubtitle.Text = Language.t("empty.subtitle")
	end

	--[=[
		Which messages are pinned (Services/Chat/Pins.list), for the right-click menu.
	]=]
	function self.setPinned(list)
		table.clear(pinnedTimestamps)
		for _, entry in ipairs(list) do
			pinnedTimestamps[entry.timestamp] = true
		end
	end

	-- A saved message's row: by its name (MessageId) or, failing that, the
	-- newest row with its timestamp
	local function rowOf(target: string | number, untaggedOnly: boolean?): Frame?
		local found = nil
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") and not child:GetAttribute("IsSystem") and not child:GetAttribute("Ephemeral") then
				local id = child:GetAttribute("MessageId")
				if type(target) == "string" then
					if id == target then
						return child
					end
				elseif child:GetAttribute("Timestamp") == target and not (untaggedOnly and id) then
					found = child
				end
			end
		end
		return found
	end

	--[=[
		Names the row just shown for a saved message, so reactions find the
		right one when messages share a second.
	]=]
	function self.tagMessage(timestamp: number, messageId: string)
		local row = rowOf(timestamp, true)
		if row then
			row:SetAttribute("MessageId", messageId)
		end
	end

	-- "builderman and Roblox reacted with 👍" (at most 3 names)
	local function describeReaction(reaction): string
		local names = reaction.names or {}
		local shown = {}
		for index = 1, math.min(3, #names) do
			table.insert(shown, names[index])
		end
		local list = table.concat(shown, ", ")
		if #names > 3 then
			return Language.t("reactions.whoMore", { names = list, count = #names - 3, emoji = reaction.emoji })
		end
		return Language.t("reactions.who", { names = list, emoji = reaction.emoji })
	end

	--[=[
		Shows a message's reactions (Services/Chat/Reactions.read) under it.
		target: the message's name, or its timestamp.
	]=]
	function self.setReactions(target: string | number, reactions)
		local row = rowOf(target)
		if not row then
			return
		end
		Messages.setReactions(row, reactions, ctx.palette, {
			toggle = function(emoji: string)
				hooks.toggleReaction(target, emoji)
			end,
			add = function()
				hooks.addReaction(target)
			end,
			hover = function(button, reaction)
				if not button then
					ctx.tooltip.hide()
				elseif reaction then
					ctx.tooltip.show(button, describeReaction(reaction))
				else
					ctx.tooltip.show(button, Language.t("menu.addReaction"))
				end
			end,
		})
	end

	function self.onVote(fn)
		voteHandler = fn
	end

	--[=[
		Re-renders the shown messages (clock, timestamps, text size, names).
	]=]
	function self.refresh()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") then
				for _, labelName in ipairs({ "TextContent", "Body" }) do
					local label = child:FindFirstChild(labelName)
					if label and label:IsA("TextLabel") then
						label.TextSize = Messages.getTextSize()
					end
				end
				Messages.recolor(child, ctx.palette)
			end
		end
	end

	--[=[
		Re-renders the author line of every message from userId (their badges changed).
	]=]
	function self.refreshBadges(userId: number)
		for _, row in ipairs(scrollFrame:GetChildren()) do
			if row:GetAttribute("SenderId") == userId and row:FindFirstChild("Author") then
				Author.render(row, ctx.palette)
			end
		end
	end

	--[=[
		Fits the list between the header (top) and the composer (bottom).
	]=]
	function self.place(top: number, bottom: number)
		scrollFrame.Size = UDim2.new(1, 0, 1, -(bottom + top))
		scrollFrame.Position = UDim2.new(0, 0, 0, top)
		emptyState.Size = UDim2.new(1, 0, 1, -(bottom + top))
		emptyState.Position = UDim2.new(0, 0, 0, top)
		scrollButton.Position = UDim2.new(1, -14, 1, -(bottom + 14))
	end

	function self.recolor()
		local palette = ctx.palette
		scrollFrame.BackgroundColor3 = palette.scrollBack
		scrollFrame.ScrollBarImageColor3 = palette.scrollBar
		scrollButton.BackgroundColor3 = palette.menuBack
		scrollButton.TextColor3 = palette.menuItemText or palette.messageText
		scrollButtonStroke.Color = palette.menuBorder
		local unreadDivider = scrollFrame:FindFirstChild("UnreadDivider")
		if unreadDivider then
			colorUnreadDivider(unreadDivider)
		end
		emptyIcon.TextColor3 = palette.emptyTitle
		emptyTitleLabel.TextColor3 = palette.emptyTitle
		emptySubtitle.TextColor3 = palette.emptySubtitle
	end

	--[=[
		Recolors every message row (the last step of a theme change).
	]=]
	function self.recolorMessages()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") and child.Name ~= "UnreadDivider" then
				Messages.recolor(child, ctx.palette)
			end
		end
	end

	-- Live messages fade in; history loading in stays instant
	scrollFrame.ChildAdded:Connect(function(child)
		task.defer(function()
			local timestamp = child:GetAttribute("Timestamp")
			if child.Parent and type(timestamp) == "number" and os.time() - timestamp <= 5 then
				Animation.fadeIn(child, "smooth")
			end
		end)
	end)

	return self
end

return Feed
