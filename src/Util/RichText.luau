--!strict
--[[
	RichText

	Builds the RichText markup for chat lines: escaping, colors, the
	"<time> [sender]: content" line and the poll header. Links in the content
	are underlined in Theme.LINK_COLOR.

	Usage:
		label.Text = RichText.buildMessage(sender, content, timestamp, palette)
		RichText.escape("a < b & c")   -- "a &lt; b &amp; c"
]]

local BadgeConfig = require(script.Parent.Parent.Config.Badges)
local Icons = require(script.Parent.Parent.Config.Icons)
local Theme = require(script.Parent.Parent.Config.Theme)
local Links = require(script.Parent.Links)
local Mentions = require(script.Parent.Mentions)
local TimeFormat = require(script.Parent.TimeFormat)
local UsernameColors = require(script.Parent.UsernameColors)

type Palette = { [string]: Color3 }

-- A badge next to a name (see Services/Badges)
export type Badge = {
	icon: string?, -- Builder Icons name
	color: Color3?,
	verified: boolean?, -- the verified badge (Icons.NAMES.verified)
	name: string?, -- shown in its tooltip
	description: string?,
}

local RichText = {}

--[=[
	Escapes text so RichText shows it literally (& first, then < >).
]=]
function RichText.escape(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

--[=[
	"#RRGGBB" for a Color3, for <font color="..."> tags.
]=]
function RichText.toHex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	)
end

-- Escaped text with each @mention in the mention colour. The rounded tint
-- behind it is drawn by UI/Text/MentionPills (RichText can't round a <mark>).
-- Only the colour changes, never the font, so measuring the text (link
-- hit-testing, the pills) still matches what's shown.
local function styleMentions(text: string, palette: Palette?): string
	local mentions = Mentions.find(text)
	if #mentions == 0 then
		return RichText.escape(text)
	end
	local colors = palette or Theme.PALETTES.Dark
	local open = string.format('<font color="%s">', RichText.toHex(colors.mentionText))
	local parts = {}
	local position = 1
	for _, mention in ipairs(mentions) do
		table.insert(parts, RichText.escape(string.sub(text, position, mention.start - 1)))
		table.insert(parts, open .. RichText.escape(string.sub(text, mention.start, mention.finish)) .. "</font>")
		position = mention.finish + 1
	end
	table.insert(parts, RichText.escape(string.sub(text, position)))
	return table.concat(parts)
end

--[=[
	Escaped text with each @mention in `color` (one-line previews such as a
	reply line, where there's no room for the highlight).
]=]
function RichText.colorMentions(text: string, color: Color3): string
	local parts = {}
	local position = 1
	for _, mention in ipairs(Mentions.find(text)) do
		table.insert(parts, RichText.escape(string.sub(text, position, mention.start - 1)))
		table.insert(
			parts,
			string.format(
				'<font color="%s">%s</font>',
				RichText.toHex(color),
				RichText.escape(string.sub(text, mention.start, mention.finish))
			)
		)
		position = mention.finish + 1
	end
	table.insert(parts, RichText.escape(string.sub(text, position)))
	return table.concat(parts)
end

--[=[
	Escaped content with every link underlined and colored, and @mentions
	highlighted (in `palette`'s colours; dark by default).
]=]
function RichText.styleContent(content: string?, palette: Palette?): string
	local text = content or ""
	local links = Links.find(text)
	if #links == 0 then
		return styleMentions(text, palette)
	end

	local parts = {}
	local position = 1
	local linkColor = RichText.toHex(Theme.LINK_COLOR)
	for _, link in ipairs(links) do
		if link.start > position then
			table.insert(parts, styleMentions(string.sub(text, position, link.start - 1), palette))
		end
		local shown = link.display or string.sub(text, link.start, link.finish)
		table.insert(parts, string.format('<u><font color="%s">%s</font></u>', linkColor, RichText.escape(shown)))
		position = link.finish + 1
	end
	if position <= #text then
		table.insert(parts, styleMentions(string.sub(text, position), palette))
	end
	return table.concat(parts)
end

--[=[
	The text of a chat line: "<time> [sender]: content" (time omitted when
	timestamps are hidden, ": content" omitted when there's no content).
]=]
function RichText.buildMessage(sender: string, content: string, timestamp: number, palette: Palette): string
	local timeStr = TimeFormat.format(timestamp)
	local name = string.format(
		'<font color="%s">[%s]</font>',
		RichText.toHex(UsernameColors.getNameColor(sender)),
		RichText.escape(sender)
	)
	local time = if timeStr == ""
		then ""
		else string.format('<font color="%s">%s</font> ', RichText.toHex(palette.timestamp), timeStr)
	if content == "" then
		return time .. name
	end
	return string.format(
		'%s%s: <font color="%s">%s</font>',
		time,
		name,
		RichText.toHex(palette.messageText),
		RichText.styleContent(content, palette)
	)
end

--[=[
	A message's text: the content with links styled, plus a small muted
	"(edited)" when it was edited.
]=]
function RichText.buildBody(content: string, edited: boolean?, palette: Palette): string
	local body = RichText.styleContent(content, palette)
	if edited then
		body ..= string.format(' <font size="10" color="%s">(edited)</font>', RichText.toHex(palette.timestamp))
	end
	return body
end

--[=[
	A badge's icon name for inline text, whether it's drawn filled, and its
	color. The verified badge uses Icons.NAMES.verifiedInline in
	Config/Badges.VERIFIED_COLOR (UI/Components/BadgeIcons draws the two-part
	version where a separate element fits).
]=]
function RichText.badgeIcon(badge: Badge): (string?, boolean, Color3?)
	if badge.verified then
		return Icons.name("verifiedInline"), true, BadgeConfig.VERIFIED_COLOR
	end
	return badge.icon, false, badge.color
end

--[=[
	Badges as inline text (colored Builder Icons), e.g. for lists. `size` is
	in pixels (14 by default).
]=]
function RichText.buildBadges(badges: { Badge }?, size: number?): string
	local parts = {}
	for _, badge in ipairs(badges or {}) do
		local icon, filled, color = RichText.badgeIcon(badge)
		if icon then
			local glyph = string.format(
				'<font family="%s"%s size="%d">%s</font>',
				Icons.FONT_FAMILY,
				if filled then ' weight="bold"' else "",
				size or 14,
				icon
			)
			table.insert(
				parts,
				if color then string.format('<font color="%s">%s</font>', RichText.toHex(color), glyph) else glyph
			)
		end
	end
	return table.concat(parts, " ")
end

--[=[
	The header of a poll card: time in Builder Mono, the sender, and "Poll" in
	Builder Extended.
]=]
function RichText.buildPollHeader(sender: string, timestamp: number, palette: Palette): string
	local timeStr = TimeFormat.format(timestamp)
	local name = string.format(
		'<font color="%s"><b>%s</b></font>',
		RichText.toHex(UsernameColors.getNameColor(sender)),
		RichText.escape(sender)
	)
	local poll = Theme.richFont("extended", "semibold") .. "Poll</font>"
	if timeStr == "" then
		return name .. "  \u{00B7}  " .. poll
	end
	local time = string.format(
		'<font color="%s">%s%s</font></font>',
		RichText.toHex(palette.timestamp),
		Theme.richFont("mono"),
		timeStr
	)
	return time .. "  " .. name .. "  \u{00B7}  " .. poll
end

return RichText
