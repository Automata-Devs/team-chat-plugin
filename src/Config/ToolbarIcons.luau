--!strict
--[[
	ToolbarIcons

	The Team Chat toolbar button's icon, with your unread count on it like
	the chat's own badges: a red circle with 1 to 9, then "9+". The images
	are the base icon with the badge drawn on (tools/make_badge_icons.py),
	uploaded as Roblox images.

	Usage:
		toggleButton.Icon = ToolbarIcons.forCount(unread)
]]

local ToolbarIcons = {}

ToolbarIcons.BASE = "rbxassetid://104410097861078"

-- The icon with 1 to 9 unread
ToolbarIcons.COUNTS = {
	"rbxassetid://83839464546544",
	"rbxassetid://91592698991008",
	"rbxassetid://118165358328407",
	"rbxassetid://138409846550135",
	"rbxassetid://136759661875286",
	"rbxassetid://115776250932536",
	"rbxassetid://94373118287646",
	"rbxassetid://111258970639702",
	"rbxassetid://70413635360607",
} :: { [number]: string }

-- The icon with "9+"
ToolbarIcons.MORE = "rbxassetid://98758811306358" :: string?

--[=[
	The icon for `count` unread messages (the plain one for none, or when a
	badge image is missing).
]=]
function ToolbarIcons.forCount(count: number): string
	if count <= 0 then
		return ToolbarIcons.BASE
	end
	if count > 9 then
		return ToolbarIcons.MORE or ToolbarIcons.BASE
	end
	return ToolbarIcons.COUNTS[math.floor(count)] or ToolbarIcons.BASE
end

return ToolbarIcons
