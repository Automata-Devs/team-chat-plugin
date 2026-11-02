--!strict
--[[
	BadgeIcons

	Draws badges next to names. The verified badge is two icons from
	Config/Icons stacked: the backplate in Config/Badges.VERIFIED_COLOR and
	the check in white on top. Other badges are one colored icon.

	Usage:
		BadgeIcons.create(badge, 14).Parent = row     -- a GuiObject
		label.Text = name .. " " .. BadgeIcons.inline(badge, 13)  -- rich text
		BadgeIcons.VERIFIED                           -- { verified = true, name = "Verified" }
]]

local BadgeConfig = require(script.Parent.Parent.Parent.Config.Badges)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local RichText = require(script.Parent.Parent.Parent.Util.RichText)

local BadgeIcons = {}

BadgeIcons.VERIFIED = { verified = true, name = "Verified" } :: RichText.Badge

local function iconLabel(name: string, glyph: string, filled: boolean, color: Color3, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromOffset(size, size)
	label.BackgroundTransparency = 1
	label.FontFace = Icons.font(filled)
	label.Text = glyph
	label.TextSize = size
	label.TextColor3 = color
	return label
end

--[=[
	A badge as a GuiObject of size × size (named "BadgeIcon_<id>").
]=]
function BadgeIcons.create(badge: RichText.Badge, size: number, fallbackColor: Color3?): GuiObject
	if badge.verified then
		local plate = iconLabel("BadgeIcon_verified", Icons.name("verified"), true, BadgeConfig.VERIFIED_COLOR, size)
		local check = iconLabel("Check", Icons.name("verifiedCheck"), true, Color3.new(1, 1, 1), size)
		check.Position = UDim2.fromScale(0, 0)
		check.Parent = plate
		return plate
	end
	return iconLabel(
		"BadgeIcon_" .. tostring((badge :: any).id or "badge"),
		badge.icon or "",
		false,
		badge.color or fallbackColor or Color3.new(1, 1, 1),
		size
	)
end

--[=[
	A badge as inline rich text (the verified badge uses its one-glyph icon).
]=]
function BadgeIcons.inline(badge: RichText.Badge, size: number?): string
	return RichText.buildBadges({ badge }, size)
end

--[=[
	" " plus the inline verified badge when `verified`, else "".
]=]
function BadgeIcons.verifiedSuffix(verified: boolean?, size: number?): string
	return if verified then " " .. BadgeIcons.inline(BadgeIcons.VERIFIED, size) else ""
end

return BadgeIcons
