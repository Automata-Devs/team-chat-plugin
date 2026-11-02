--!
-- MessageController
-- Handles message sending, command parsing, and input event wiring.
-- Extracted from the main entry point for separation of concerns.
--!

local EmojiData = require(script.Parent.Parent.Utils.EmojiData)
local UsageTracker = require(script.Parent.Parent.Utils.UsageTracker)

local MessageController = {}

--!
-- Builds the command context table that is passed to CommandHandler.tryParse.
-- This provides commands with access to UI callbacks and network helpers.
--!
local function buildCommandContext(ui, chatNetwork)
	return {
		addSystemMessage = ui.addSystemMessage,
		clearChat = ui.clearChat,
		sendMessage = function(msg)
			chatNetwork.sendMessage(msg)
		end,
		getUsername = chatNetwork.getUsername,
		getUserId = chatNetwork.getUserId,
		getPendingImage = ui.getPendingImage,
		getPendingFile = ui.getPendingFile,
		clearPendingImage = ui.clearPendingImage,
		clearPendingFile = ui.clearPendingFile,
		setTextBox = function(t) ui.textBox.Text = t end,
		textBoxText = function() return ui.textBox.Text end,
	}
end

--!
-- Sends a message or parses a command from the UI text box.
--!
local function sendMessage(ui, chatNetwork, commandHandler)
	if ui.isUploading and ui.isUploading() then
		return -- Wait for upload to finish
	end

	-- Note: Enter intentionally does NOT accept autocomplete suggestions anymore.
	-- Suggestions (commands and emojis) are accepted with Tab or a click, see
	-- ChatUI's updateAutocomplete. Enter always sends / runs what was typed.

	-- Drop leading/trailing blank lines and spaces (the box is multi-line)
	local text = string.match(ui.textBox.Text, "^%s*(.-)%s*$")
	local pendingImage = ui.getPendingImage()
	local pendingFile = ui.getPendingFile and ui.getPendingFile()

	-- Attach the pending reply reference (if any) to the outgoing message
	local replyRef
	if ui.getReplyReference then
		local ts, replySender, replyContent = ui.getReplyReference()
		if ts then
			replyRef = { timestamp = ts, sender = replySender, content = replyContent }
		end
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

--!
-- Initializes the message controller by wiring up input events.
-- @param ui The ChatUI instance
-- @param chatNetwork The ChatNetwork module
-- @param commandHandler The CommandHandler module
--!
function MessageController.init(ui, chatNetwork, commandHandler)
	-- Send on button click
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
		if removingEnter or #text ~= #previous + 1 then return end

		-- Find the one inserted character
		local at = 1
		while at <= #previous and string.byte(text, at) == string.byte(previous, at) do
			at += 1
		end
		if string.sub(text, at, at) ~= "\n" or string.sub(text, at + 1) ~= string.sub(previous, at) then return end

		local enterSends = not ui.isEnterToSendEnabled or ui.isEnterToSendEnabled()
		if not enterSends then return end

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