--[[
	MessageController

	Handles message sending, command parsing, and input event wiring.
	Extracted from the main entry point for separation of concerns.
]]

local HttpService = game:GetService("HttpService")

local AdminNetwork = require(script.Parent.Parent.Services.Admin)
local EmojiData = require(script.Parent.Parent.Util.EmojiData)
local Language = require(script.Parent.Parent.Core.Language)
local Premium = require(script.Parent.Parent.Services.Premium)
local PremiumConfig = require(script.Parent.Parent.Config.Premium)
local UsageTracker = require(script.Parent.Parent.Services.Usage)

local MessageController = {}

-- Builds the command context table that is passed to Commands/Registry.tryParse.
-- This provides commands with access to UI callbacks and network helpers.
-- A card spec as JSON (its colour as hex), to save with a public message
local function encodeEmbed(spec): string
	local copy = table.clone(spec)
	if typeof(copy.color) == "Color3" then
		copy.color = copy.color:ToHex()
	end
	return HttpService:JSONEncode(copy)
end

local function buildCommandContext(ui, chatNetwork)
	local context
	context = {
		-- Replies only you see, unless options.public: then Team Chat posts it
		-- for everyone, under "<you> used /command" (context.command, set by
		-- the registry while a command runs)
		addSystemMessage = function(text: string, options: { public: boolean? }?)
			if options and options.public and chatNetwork.sendBotMessage then
				chatNetwork.sendBotMessage(text, nil, context.command)
				return
			end
			ui.addSystemMessage(text)
		end,
		-- A reply as a card (Embeds/Providers/CommandEmbed); as plain lines where
		-- the UI has no cards
		addEmbed = function(spec, options: { public: boolean? }?)
			if options and options.public and chatNetwork.sendBotMessage then
				chatNetwork.sendBotMessage("", encodeEmbed(spec), context.command)
				return
			end
			if ui.addSystemEmbed then
				ui.addSystemEmbed(spec)
				return
			end
			ui.addSystemMessage(spec.title or "")
			for _, field in ipairs(spec.fields or {}) do
				ui.addSystemMessage(field.name .. ": " .. tostring(field.value))
			end
		end,
		clearChat = ui.clearChat,
		openAbout = ui.openAbout,
		openBadges = ui.openBadges,
		openScript = ui.openScript,
		sendMessage = function(msg)
			chatNetwork.sendMessage(msg)
		end,
		getUsername = chatNetwork.getUsername,
		getUserId = chatNetwork.getUserId,
		getPendingImage = ui.getPendingImage,
		getPendingFile = ui.getPendingFile,
		clearPendingImage = ui.clearPendingImage,
		clearPendingFile = ui.clearPendingFile,
		setTextBox = function(t)
			ui.textBox.Text = t
		end,
		textBoxText = function()
			return ui.textBox.Text
		end,
	}
	return context
end

-- Sends a message or parses a command from the UI text box.
local function sendMessage(ui, chatNetwork, commandHandler)
	if ui.isUploading and ui.isUploading() then
		return -- Wait for upload to finish
	end

	-- Note: Enter intentionally does NOT accept autocomplete suggestions anymore.
	-- Suggestions (commands and emojis) are accepted with Tab or a click, see
	-- ChatWindow/Suggestions. Enter always sends / runs what was typed.

	-- Drop leading/trailing blank lines and spaces (the box is multi-line)
	local text = string.match(ui.textBox.Text, "^%s*(.-)%s*$")
	local pendingImage = ui.getPendingImage()
	local pendingFile = ui.getPendingFile and ui.getPendingFile()

	-- Attach the pending reply reference (if any) to the outgoing message
	local replyRef
	if ui.getReplyReference then
		local ts, replySender, replyContent, replySenderId = ui.getReplyReference()
		if ts then
			replyRef = { timestamp = ts, sender = replySender, content = replyContent, senderId = replySenderId }
		end
	end

	-- Blocked words (admin dashboard > Chat tools): not sent, the text stays in
	-- the box to fix; moderators and up are exempt
	if text ~= "" and text:sub(1, 1) ~= "/" and not AdminNetwork.hasRank(AdminNetwork.RANK_MODERATOR) then
		local blocked = AdminNetwork.ChatRules.findBlocked(text)
		if blocked then
			ui.addSystemMessage(Language.t("rules.blocked", { word = blocked }))
			return
		end
	end

	-- Too long (Premium sends longer messages): not sent, the text stays in the box
	if text ~= "" and text:sub(1, 1) ~= "/" then
		local limit = Premium.messageLength(chatNetwork.getUserId())
		local length = utf8.len(text) or #text
		if length > limit then
			local premiumLimit = PremiumConfig.MESSAGE_LENGTH.premium
			ui.addSystemMessage(
				Language.t(
					if limit < premiumLimit then "premium.tooLongFree" else "premium.tooLong",
					{ length = length, limit = limit, premium = premiumLimit }
				)
			)
			return
		end
	end

	-- Editing one of your messages: save the new text instead of sending
	local editingTimestamp = ui.getEditingMessage and ui.getEditingMessage()
	if editingTimestamp then
		if text ~= "" then
			text = EmojiData.replaceShortcodes(text, function(entry)
				UsageTracker.record("emoji", entry.name)
			end)
			chatNetwork.editMessage(editingTimestamp, text)
		end
		ui.textBox.Text = ""
		ui.clearEditing()
		return
	end

	-- If the message starts with "/", try to parse it as a command
	if text ~= "" and text:sub(1, 1) == "/" and not pendingImage and not pendingFile then
		local ctx = buildCommandContext(ui, chatNetwork)
		local handled = commandHandler.tryParse(text, ctx)
		if handled then
			ui.textBox.Text = ""
			return
		end
	end

	if text == "" and not pendingImage and not pendingFile then
		return
	end

	-- Convert any complete :shortcode: that wasn't already converted while typing
	-- (e.g. pasted text) into its emoji.
	text = EmojiData.replaceShortcodes(text, function(entry)
		UsageTracker.record("emoji", entry.name)
	end)

	if pendingFile then
		chatNetwork.sendFile(pendingFile.fileName, pendingFile.fileUrl, pendingFile.fileType, text)
	else
		chatNetwork.sendMessage(text, pendingImage, replyRef)
	end

	ui.textBox.Text = ""
	if pendingImage then
		ui.clearPendingImage()
	end
	if pendingFile then
		ui.clearPendingFile()
	end
	if replyRef and ui.clearReplyReference then
		ui.clearReplyReference()
	end
end

--[=[
	Initializes the message controller by wiring up input events.
	ui: The ChatUI instance
	chatNetwork: The ChatNetwork module
	commandHandler: The CommandHandler module
]=]
function MessageController.init(ui, chatNetwork, commandHandler)
	ui.sendButton.MouseButton1Click:Connect(function()
		sendMessage(ui, chatNetwork, commandHandler)
	end)

	-- The message box is MultiLine (it wraps while typing), so Enter types a
	-- newline instead of losing focus. A typed Enter sends the message when
	-- Enter-to-send is on; with "Button Only" it keeps the newline.
	-- Studio sends plugin widgets no keyboard events (only the text changes),
	-- so modifier keys like Shift can't be detected: there is no Shift+Enter.
	-- Only a single typed "\n" counts, so pasted multi-line text isn't sent.
	local lastText = ui.textBox.Text
	local removingEnter = false

	ui.textBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = ui.textBox.Text
		local previous = lastText
		lastText = text
		if removingEnter or #text ~= #previous + 1 then
			return
		end

		-- Find the one inserted character
		local at = 1
		while at <= #previous and string.byte(text, at) == string.byte(previous, at) do
			at += 1
		end
		if string.sub(text, at, at) ~= "\n" or string.sub(text, at + 1) ~= string.sub(previous, at) then
			return
		end

		local enterSends = not ui.isEnterToSendEnabled or ui.isEnterToSendEnabled()
		if not enterSends then
			return
		end

		-- Take the newline back out, then send what was typed
		removingEnter = true
		ui.textBox.Text = previous
		lastText = previous
		removingEnter = false
		sendMessage(ui, chatNetwork, commandHandler)
	end)

	-- Send on Enter when focus is lost with Enter (kept as a fallback)
	ui.textBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			if ui.isEnterToSendEnabled and not ui.isEnterToSendEnabled() then
				return
			end
			sendMessage(ui, chatNetwork, commandHandler)
		end
	end)
end

return MessageController
