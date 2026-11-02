--!strict
--[[
	Browser

	Opens web links from the plugin. Studio has no documented API for this;
	StudioService:OpenInBrowser_DONOTUSE is the undocumented one plugins use
	(Plugin:OpenWikiPage only opens Roblox's documentation). Anything that
	isn't an http(s) link, or fails to open, is copied to the clipboard so the
	user can paste it.

	Usage:
		if not Browser.open("www.roblox.com") then
			-- it was copied to the clipboard instead
		end
]]

local StudioService = game:GetService("StudioService")

local Logger = require(script.Parent.Logger)

local log = Logger.scope("Browser")

local Browser = {}

--[=[
	Opens `url` in the default browser. Returns true if it opened, false if it
	was copied to the clipboard instead.
]=]
function Browser.open(url: string): boolean
	if not string.match(url, "^%a+://") then
		url = "https://" .. url -- "www.example.com" style links
	end

	if string.match(string.lower(url), "^https?://") then
		local ok = pcall(function()
			(StudioService :: any):OpenInBrowser_DONOTUSE(url)
		end)
		if ok then
			return true
		end
		log.debug("Couldn't open %s in the browser; copying it instead", url)
	end

	pcall(function()
		StudioService:CopyToClipboard(url)
	end)
	return false
end

return Browser
