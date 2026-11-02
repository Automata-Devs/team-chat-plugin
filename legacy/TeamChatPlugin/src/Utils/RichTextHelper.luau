--!
-- RichTextHelper
-- Utilities for building RichText strings used in chat messages.
-- Handles HTML escaping, color formatting, and message composition.
--!

local TimeFormatter = require(script.Parent.TimeFormatter)
local UsernameColors = require(script.Parent.UsernameColors)
local LinkHelper = require(script.Parent.LinkHelper)
local Theme = require(script.Parent.Parent.Config.Theme)

local RichTextHelper = {}

--!
-- Escapes HTML special characters (< and >) for safe RichText rendering.
--!
function RichTextHelper.escape(text: string): string
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

--!
-- Converts a Color3 to a hex string for use in RichText <font color> tags.
--!
function RichTextHelper.toHex(color: Color3): string
	return string.format("#%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255))
end

--!
-- Builds the rich text content for a message's text label.
-- @param sender The sender's display name
-- @param content The message content
-- @param timestamp The message timestamp (unix)
-- @param themeColors The current theme color palette
-- @return string RichText-formatted string
--!
function RichTextHelper.buildMessage(sender: string, content: string, timestamp: number, themeColors: table): string
	local timeStr = TimeFormatter.format(timestamp)
	local senderColor = UsernameColors.getNameColor(sender)

	local styledContent = LinkHelper.styleContent(content)
	local escapedSender = RichTextHelper.escape(sender)

	-- Timestamps hidden: omit the time prefix entirely.
	if timeStr == "" then
		if content == "" then
			return string.format(
				'<font color="%s">[%s]</font>',
				RichTextHelper.toHex(senderColor), escapedSender
			)
		end
		return string.format(
			'<font color="%s">[%s]</font>: <font color="%s">%s</font>',
			RichTextHelper.toHex(senderColor), escapedSender,
			RichTextHelper.toHex(themeColors.messageText), styledContent
		)
	end

	if content == "" then
		return string.format(
			'<font color="%s">%s</font> <font color="%s">[%s]</font>',
			RichTextHelper.toHex(themeColors.timestamp), timeStr,
			RichTextHelper.toHex(senderColor), escapedSender
		)
	end

	return string.format(
		'<font color="%s">%s</font> <font color="%s">[%s]</font>: <font color="%s">%s</font>',
		RichTextHelper.toHex(themeColors.timestamp), timeStr,
		RichTextHelper.toHex(senderColor), escapedSender,
		RichTextHelper.toHex(themeColors.messageText), styledContent
	)
end

--!
-- Builds the rich text header for a poll message: timestamp in Builder Mono,
-- "Poll" in Builder Extended. (Plain message lines stay single-font; see Theme.FONTS.)
-- @param sender The sender's display name
-- @param timestamp The message timestamp (unix)
-- @param themeColors The current theme color palette
-- @return string RichText-formatted string
--!
function RichTextHelper.buildPollHeader(sender: string, timestamp: number, themeColors: table): string
	local senderColor = UsernameColors.getNameColor(sender)
	local escapedSender = RichTextHelper.escape(sender)
	local timeStr = TimeFormatter.format(timestamp)

	-- Timestamps hidden: omit the time prefix entirely.
	if timeStr == "" then
		return string.format(
			'<font color="%s"><b>%s</b></font>  \u{00B7}  %sPoll</font>',
			RichTextHelper.toHex(senderColor), escapedSender,
			Theme.richFont("extended", "semibold")
		)
	end

	return string.format(
		'<font color="%s">%s%s</font></font>  <font color="%s"><b>%s</b></font>  \u{00B7}  %sPoll</font>',
		RichTextHelper.toHex(themeColors.timestamp), Theme.richFont("mono"), timeStr,
		RichTextHelper.toHex(senderColor), escapedSender,
		Theme.richFont("extended", "semibold")
	)
end

return RichTextHelper