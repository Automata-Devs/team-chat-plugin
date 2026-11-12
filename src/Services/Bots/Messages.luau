--!strict
--[[
	Messages

	Bot messages: text, a card and buttons, saved in a conversation (for
	everyone or only one person) or shown only in this chat (a web bot's
	ephemeral answer, through the ui hooks the controller sets).
]]

local HttpService = game:GetService("HttpService")

local ChatState = require(script.Parent.Parent.Chat.ChatState)
local Conversations = require(script.Parent.Parent.Chat.Conversations)
local Manifests = require(script.Parent.Manifests)
local TimeFormat = require(script.Parent.Parent.Parent.Util.TimeFormat)

local BUTTON_STYLES = { primary = true, secondary = true, success = true, danger = true, link = true }

type BotIdentity = Manifests.BotIdentity
export type Message = {
	content: string?,
	embed: { [string]: any }?,
	components: { any }?,
	ephemeral: boolean?,
}
export type Interaction = {
	byId: number?,
	byName: string?,
	command: string?, -- "/name" shown above the answer
	conversation: string?,
	message: Instance?, -- the message whose button was clicked
}

local Messages = {}

-- Hooks into the chat window for messages that are never saved (a web bot's
-- ephemeral answers): set by the controller
Messages.ui = nil :: {
	showLocal: (entry: { [string]: any }) -> Instance?,
	removeLocal: (Instance) -> (),
	say: (text: string) -> (),
}?

function Messages.say(text: string)
	if Messages.ui then
		Messages.ui.say(text)
	end
end

-- Text, a card, or { content, embed, components, ephemeral }
function Messages.normalize(message: any): Message
	if type(message) == "string" then
		return { content = message }
	elseif type(message) == "table" then
		if
			message.content == nil
			and message.embed == nil
			and message.components == nil
			and (message.title or message.fields or message.description)
		then
			return { embed = message } -- a card on its own
		end
		return {
			content = if message.content ~= nil then tostring(message.content) else nil,
			embed = if type(message.embed) == "table" then message.embed else nil,
			components = if type(message.components) == "table" then message.components else nil,
			ephemeral = message.ephemeral == true,
		}
	end
	return { content = tostring(message) }
end

local function encodeEmbed(embed: { [string]: any }?): string?
	if not embed then
		return nil
	end
	local copy = table.clone(embed)
	if typeof(copy.color) == "Color3" then
		copy.color = copy.color:ToHex()
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, copy)
	return if ok then json else nil
end

--[=[
	Buttons under a message, cleaned up: rows of up to 5 buttons, up to 5
	rows. A button is { label, style, customId, url, disabled }; a flat list
	of buttons is one row.
]=]
function Messages.cleanComponents(components: any): { { { [string]: any } } }?
	if type(components) ~= "table" or #components == 0 then
		return nil
	end
	local rows = if type(components[1]) == "table" and components[1].label ~= nil then { components } else components
	local clean = {}
	for _, row in ipairs(rows) do
		if type(row) == "table" and #clean < 5 then
			local buttons = {}
			for _, button in ipairs(row) do
				if type(button) == "table" and button.label ~= nil and #buttons < 5 then
					local style = if BUTTON_STYLES[button.style] then button.style else "secondary"
					local url = if type(button.url) == "string" and string.match(button.url, "^https://")
						then button.url
						else nil
					if url then
						style = "link"
					end
					table.insert(buttons, {
						label = string.sub(tostring(button.label), 1, 80),
						style = style,
						customId = if button.customId ~= nil
							then string.sub(tostring(button.customId), 1, 100)
							else nil,
						url = url,
						disabled = button.disabled == true,
					})
				end
			end
			if #buttons > 0 then
				table.insert(clean, buttons)
			end
		end
	end
	return if #clean > 0 then clean else nil
end

local function writeMessage(target: Instance, bot: BotIdentity, message: Message, interaction: Interaction?)
	target:SetAttribute("Sender", bot.name)
	target:SetAttribute("SenderId", 0)
	target:SetAttribute("BotId", bot.id)
	target:SetAttribute("BotOwner", bot.ownerId or 0)
	target:SetAttribute("BotAvatar", bot.avatar)
	target:SetAttribute("Content", message.content or "")
	target:SetAttribute("Embed", encodeEmbed(message.embed))
	local components = Messages.cleanComponents(message.components)
	target:SetAttribute("Components", if components then HttpService:JSONEncode(components) else nil)
	target:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_TEXT)
	if interaction and interaction.command then
		target:SetAttribute("SaidBy", interaction.byId)
		target:SetAttribute("SaidByName", interaction.byName)
		target:SetAttribute("Command", interaction.command)
	end
end

--[=[
	Saves a bot message in a conversation (everyone sees it, or only
	`visibleTo`). Returns it.
]=]
function Messages.post(
	bot: BotIdentity,
	message: Message,
	conversation: string?,
	interaction: Interaction?,
	options: { visibleTo: number?, thinking: boolean? }?
): Instance?
	local folder = Conversations.getFolder(conversation or Conversations.MAIN, true)
	if not folder then
		return nil
	end
	local saved = Instance.new("Folder")
	saved.Name = "bot_" .. TimeFormat.generateId()
	writeMessage(saved, bot, message, interaction)
	saved:SetAttribute("Timestamp", os.time())
	if options and options.visibleTo then
		saved:SetAttribute("VisibleTo", options.visibleTo)
	end
	if options and options.thinking then
		saved:SetAttribute("Thinking", true)
	end
	saved.Parent = folder
	ChatState.saveHistory()
	return saved
end

--[=[
	Changes a saved bot message in place (a deferred answer arriving, or a
	button's "update"). The chat re-draws it where it was.
]=]
function Messages.edit(saved: Instance, bot: BotIdentity, message: Message, interaction: Interaction?)
	writeMessage(saved, bot, message, interaction)
	saved:SetAttribute("Thinking", nil)
	saved:SetAttribute("Revision", (saved:GetAttribute("Revision") or 0) + 1)
	ChatState.saveHistory()
end

-- An answer that's never saved (a web bot's ephemeral answer): only in this chat
function Messages.showLocal(
	bot: BotIdentity,
	message: Message,
	interaction: Interaction?,
	thinking: boolean?
): Instance?
	if not Messages.ui then
		return nil
	end
	return Messages.ui.showLocal({
		botId = bot.id,
		botName = bot.name,
		botAvatar = bot.avatar,
		botOwner = bot.ownerId,
		content = message.content or "",
		embed = message.embed,
		components = Messages.cleanComponents(message.components),
		saidBy = interaction and interaction.byId,
		saidByName = interaction and interaction.byName,
		command = interaction and interaction.command,
		timestamp = os.time(),
		ephemeralLocal = true,
		thinking = thinking,
	})
end

return Messages
