--!
-- LinkHelper
-- Clickable link support for chat messages.
-- Detects URLs in message content, styles them as standard blue underlined
-- rich text, performs mouse hit-testing against the rendered TextLabel
-- (Roblox RichText has no native hyperlink support), and opens links via the
-- plugin API. Embed cards live in UI/Embeds (see EmbedManager).
--!

local TextService = game:GetService("TextService")
local StudioService = game:GetService("StudioService")

local TimeFormatter = require(script.Parent.TimeFormatter)
local Theme = require(script.Parent.Parent.Config.Theme)

local FONT = Theme.FONT

local LinkHelper = {}

-- Standard web link blue
LinkHelper.LINK_COLOR = Color3.fromRGB(0, 88, 204)

-- URL patterns: full http(s) URLs and bare "www." addresses.
-- The trailing character class avoids swallowing sentence punctuation.
local HTTP_URL = "https?://[%.%w%-]+[%.%w%-_/:?&=#+~%%]*[%w/]"
local WWW_URL = "www%.[%.%w%-]+[%.%w%-_/:?&=#+~%%]*[%w/]"

local function toHex(color)
	return string.format("#%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255))
end

--!
-- Escapes a plain text segment for safe RichText rendering.
--!
local function escapeSegment(text)
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

--!
-- Finds all URLs in a message content string.
-- @return array of { start, finish, url, display } (byte indices into content)
--!
function LinkHelper.findLinks(content)
	local links = {}
	if not content or content == "" then
		return links
	end

	for start, url in string.gmatch(content, "()" .. "(" .. HTTP_URL .. ")") do
		table.insert(links, {
			start = start,
			finish = start + #url - 1,
			url = url,
		})
	end
	for start, url in string.gmatch(content, "()" .. "(" .. WWW_URL .. ")") do
		-- Skip "www." matches that are already part of a full http(s) URL
		local insideHttp = false
		for _, link in ipairs(links) do
			if start >= link.start and start <= link.finish then
				insideHttp = true
				break
			end
		end
		if not insideHttp then
			table.insert(links, {
				start = start,
			finish = start + #url - 1,
				url = "https://" .. url,
				display = url,
			})
		end
	end

	table.sort(links, function(a, b)
		return a.start < b.start
	end)
	return links
end

--!
-- Converts message content into RichText with links styled as standard
-- blue underlined text. Non-link segments are escaped normally.
-- @return styledRichText string, links array
--!
function LinkHelper.styleContent(content)
	local links = LinkHelper.findLinks(content)
	if #links == 0 then
		return escapeSegment(content or ""), links
	end

	local parts = {}
	local pos = 1
	for _, link in ipairs(links) do
		if link.start > pos then
			parts[#parts + 1] = escapeSegment(content:sub(pos, link.start - 1))
		end
		parts[#parts + 1] = string.format(
			'<u><font color="%s">%s</font></u>',
			toHex(LinkHelper.LINK_COLOR),
			escapeSegment(link.display or content:sub(link.start, link.finish))
		)
		pos = link.finish + 1
	end
	if pos <= #content then
		parts[#parts + 1] = escapeSegment(content:sub(pos))
	end
	return table.concat(parts), links
end

--!
-- (Re)computes the plain-text layout of a message label. It must exactly
-- match what RichTextHelper.buildMessage renders (tags stripped):
-- "<time> [<sender>]: <content>", or "[<sender>]: <content>" when
-- timestamps are hidden.
--!
local function computeLayout(meta)
	local timeStr = TimeFormatter.format(meta.timestamp)
	local prefix = if timeStr == "" then "" else timeStr .. " "
	meta.timeStr = timeStr
	meta.plainText = prefix .. "[" .. meta.sender .. "]: " .. meta.content
	meta.contentOffset = #prefix + #meta.sender + 4
end

--!
-- Builds hit-test metadata for a rendered message label.
-- @return { plainText, contentOffset, links, ... }
--!
function LinkHelper.buildMeta(sender, content, timestamp)
	content = content or ""
	local meta = {
		sender = sender,
		content = content,
		timestamp = timestamp,
		links = LinkHelper.findLinks(content),
	}
	computeLayout(meta)
	return meta
end

--!
-- Measures text with the same engine the TextLabel uses for wrapping.
--!
local function measure(text, font, textSize, width)
	local ok, size = pcall(function()
		return TextService:GetTextBoundsAsync(text, font, textSize, Vector2.new(width, 100000))
	end)
	if ok and size then
		return size
	end
	return Vector2.zero
end

-- Per-label cache of the measured line height (keyed by text + width)
local labelCache = {}

--!
-- Finds the smallest prefix length of `text` whose rendered height
-- reaches `lineCount` lines (binary search over GetTextBoundsAsync).
--!
local function firstCharOfLine(text, n, font, textSize, width, lineCount, lineH)
	local lo, hi = 1, n
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		local h = measure(text:sub(1, mid), font, textSize, width).Y
		if h >= lineCount * lineH - 0.5 then
			hi = mid
		else
			lo = mid + 1
		end
	end
	return lo
end

--!
-- Hit-tests a mouse position (relative to the label's top-left corner)
-- against the link ranges of a message.
-- @return the link table under the mouse, or nil
--!
function LinkHelper.hitTest(textLabel, meta, mouseX, mouseY)
	local width = textLabel.AbsoluteSize.X
	if width <= 0 or mouseY < 0 then return nil end

	-- The clock format / timestamp setting may have changed since the label
	-- was built (the label is re-rendered); keep the layout in sync.
	if meta.timestamp and TimeFormatter.format(meta.timestamp) ~= meta.timeStr then
		computeLayout(meta)
	end

	local font = textLabel.Font
	local textSize = textLabel.TextSize
	local text = meta.plainText
	local n = #text
	if n == 0 then return nil end

	-- Cache the line height for this label/text/width combination
	local cacheKey = meta.plainText .. "|" .. tostring(width)
	local cache = labelCache[textLabel]
	if not cache or cache.key ~= cacheKey then
		local lineH = measure("Ag", font, textSize, width).Y
		cache = { key = cacheKey, lineHeight = math.max(lineH, 1) }
		labelCache[textLabel] = cache
	end
	local lineH = cache.lineHeight

	local totalHeight = measure(text, font, textSize, width).Y
	local totalLines = math.max(1, math.ceil(totalHeight / lineH - 0.01))
	local line = math.floor(mouseY / lineH)
	if line >= totalLines then return nil end

	local lineStart = firstCharOfLine(text, n, font, textSize, width, line + 1, lineH)
	local lineEnd = n
	if line + 1 < totalLines then
		lineEnd = firstCharOfLine(text, n, font, textSize, width, line + 2, lineH) - 1
	end
	if lineEnd < lineStart then return nil end

	-- Binary search within the line: the largest prefix that fits before mouseX
	local lineText = text:sub(lineStart, lineEnd)
	local lo, hi = 0, #lineText
	while lo < hi do
		local mid = math.ceil((lo + hi) / 2)
		local w = measure(lineText:sub(1, mid), font, textSize, width).X
		if w <= mouseX then
			lo = mid
		else
			hi = mid - 1
		end
	end

	-- The click lands on the character just after the fitting prefix
	local rel = lineStart + lo - meta.contentOffset + 1
	local relNext = rel + 1
	for _, link in ipairs(meta.links) do
		if (rel >= link.start and rel <= link.finish)
			or (relNext >= link.start and relNext <= link.finish) then
			return link
		end
	end
	return nil
end

--!
-- Opens a web link in the user's default browser. Studio has no documented
-- API for this; StudioService:OpenInBrowser_DONOTUSE is the undocumented one
-- plugins use (Plugin:OpenWikiPage only opens Roblox's documentation site).
-- Only http(s) links are opened; anything else, or a failed open, is copied
-- to the clipboard instead so the user can paste it.
-- @return true if it opened, false if it was copied instead
--!
function LinkHelper.openUrl(_pluginRef, url: string): boolean
	if not string.match(url, "^%a+://") then
		url = "https://" .. url -- "www.example.com" style links
	end

	local isWebLink = string.match(string.lower(url), "^https?://") ~= nil
	if isWebLink and pcall(function()
		StudioService:OpenInBrowser_DONOTUSE(url)
	end) then
		return true
	end

	pcall(function()
		StudioService:CopyToClipboard(url)
	end)
	return false
end

--!
-- Attaches click behavior to a message's TextLabel so links inside it are
-- clickable (opens the URL). Links are shown underlined; plugins can't
-- change the mouse cursor, so there is no pointing-hand hover.
--!
function LinkHelper.attachLinkInteractions(textLabel, meta, pluginRef, onOpenFail)
	if #meta.links == 0 then return end

	textLabel.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		local mx = input.Position.X - textLabel.AbsolutePosition.X
		local my = input.Position.Y - textLabel.AbsolutePosition.Y
		local link = LinkHelper.hitTest(textLabel, meta, mx, my)
		if link then
			if not LinkHelper.openUrl(pluginRef, link.url) and onOpenFail then
				onOpenFail(link.url)
			end
		end
	end)
end

return LinkHelper