--!strict
--[[
	Messages

	Builds the rows of the message list, one module per kind of message.
	ChatWindow creates rows through this facade and sets the shared state.

	Usage:
		local row = Messages.text(sender, timestamp, content, imageUrl, palette, replyRef)
		Messages.setTextSize("Large")
		Messages.setJumpHandler(function(timestamp) ... end)
		Messages.recolor(row, palette)
]]

local Announcement = require(script.Announcement)
local Author = require(script.Author)
local FileMessage = require(script.FileMessage)
local Grouping = require(script.Grouping)
local PollMessage = require(script.PollMessage)
local Reactions = require(script.Reactions)
local Recolor = require(script.Recolor)
local Shared = require(script.Shared)
local TextMessage = require(script.TextMessage)

local Messages = {}

Messages.text = TextMessage.create
Messages.setBody = TextMessage.setBody
Messages.announcement = Announcement.create
Messages.poll = PollMessage.create
Messages.updatePollVotes = PollMessage.updateVotes
Messages.file = FileMessage.create
Messages.recolor = Recolor.apply
Messages.setReplyAvatar = Shared.setReplyAvatar
Messages.applyMention = Shared.applyMention
Messages.addOnlyYouNote = Shared.addOnlyYouNote
Messages.markBot = Author.markBot
Messages.mentionsMe = Shared.mentionsMe
Messages.setReactions = Reactions.render
Messages.group = Grouping.attach -- Discord-style groups and the row hover

--[=[
	Sets the message text size ("Small" | "Default" | "Large").
]=]
function Messages.setTextSize(size: number | string)
	Shared.textSize = if type(size) == "number" then size else Shared.TEXT_SIZES[size] or Shared.TEXT_SIZES.Default
end

--[=[
	The current message text size in pixels.
]=]
function Messages.getTextSize(): number
	return Shared.textSize
end

--[=[
	Sets what clicking a reply line does (scroll to and flash the original).
]=]
function Messages.setJumpHandler(handler: (timestamp: number) -> ())
	Shared.jumpToMessage = handler
end

return Messages
