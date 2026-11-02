--!strict
--[[
	Links

	Finds web links in message text and describes where they sit in the
	rendered line, so UI/LinkHelper can tell which link was clicked.

	Usage:
		Links.find("see www.roblox.com")   -- { { start = 5, finish = 18, url = "https://www.roblox.com", display = "www.roblox.com" } }
		local meta = Links.buildMeta(sender, content, timestamp)
		Links.relayout(meta)                -- after the clock format changed
]]

local TimeFormat = require(script.Parent.TimeFormat)

export type Link = {
	start: number, -- byte index into the content
	finish: number,
	url: string, -- always with a scheme
	display: string?, -- what was typed, when it differs from url
}

export type LinkMeta = {
	sender: string,
	content: string,
	timestamp: number,
	links: { Link },
	timeStr: string,
	plainText: string, -- the label's text without RichText tags
	contentOffset: number, -- where the content starts in plainText
}

-- Full http(s) URLs and bare "www." addresses. The last character class
-- avoids swallowing sentence punctuation.
local HTTP_URL = "https?://[%.%w%-]+[%.%w%-_/:?&=#+~%%]*[%w/]"
local WWW_URL = "www%.[%.%w%-]+[%.%w%-_/:?&=#+~%%]*[%w/]"

local Links = {}

--[=[
	Every link in `content`, in order.
]=]
function Links.find(content: string?): { Link }
	local links: { Link } = {}
	if not content or content == "" then
		return links
	end

	for start, url in string.gmatch(content, "()(" .. HTTP_URL .. ")") do
		local first = start :: number
		table.insert(links, { start = first, finish = first + #url - 1, url = url })
	end
	for start, url in string.gmatch(content, "()(" .. WWW_URL .. ")") do
		local first = start :: number
		local insideHttp = false -- "www." that is part of a full http(s) URL
		for _, link in ipairs(links) do
			if first >= link.start and first <= link.finish then
				insideHttp = true
				break
			end
		end
		if not insideHttp then
			table.insert(links, { start = first, finish = first + #url - 1, url = "https://" .. url, display = url })
		end
	end

	table.sort(links, function(a, b)
		return a.start < b.start
	end)
	return links
end

--[=[
	Recomputes the plain-text layout of a message's text label. Messages show
	the author in a separate header (Messages/Author), so the label holds just
	the content.
]=]
function Links.relayout(meta: LinkMeta)
	meta.timeStr = TimeFormat.format(meta.timestamp)
	meta.plainText = meta.content
	meta.contentOffset = 0
end

--[=[
	Hit-test data for a message line.
]=]
function Links.buildMeta(sender: string, content: string?, timestamp: number): LinkMeta
	local text = content or ""
	local meta: LinkMeta = {
		sender = sender,
		content = text,
		timestamp = timestamp,
		links = Links.find(text),
		timeStr = "",
		plainText = "",
		contentOffset = 0,
	}
	Links.relayout(meta)
	return meta
end

return Links
