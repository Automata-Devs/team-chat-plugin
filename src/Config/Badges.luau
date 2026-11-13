--!strict
--[[
	Badges

	The badges shown next to names in the chat. Three kinds:
	  - Verified: for verified Roblox accounts (looked up automatically). It's
	    Icons.NAMES.verified in VERIFIED_COLOR with Icons.NAMES.verifiedCheck
	    on top in white.
	  - Custom: given to specific users in USERS below (any number each).
	  - Bought: sold as game passes. Create a game pass on Roblox (Creator
	    Hub > your experience > Monetization > Passes), then put its id in
	    `gamePassId`. Badges with gamePassId 0 show as "Coming soon".

	`icon` is a Builder Icons name (see Config/Icons for the list link) and
	`color` its color. Badges are shown in the order of ORDER.
]]

export type BadgeDefinition = {
	name: string,
	description: string,
	icon: string,
	color: Color3,
	gamePassId: number?, -- set to sell the badge; 0 or nil = not for sale
}

local Badges = {}

-- Color of the verified badge (Roblox blue)
Badges.VERIFIED_COLOR = Color3.fromRGB(0, 120, 255)

Badges.DEFINITIONS = {
	developer = {
		name = "Plugin Developer",
		description = "Made the Team Chat plugin",
		icon = "code",
		color = Color3.fromRGB(88, 101, 242),
	},
	premium = {
		name = "Premium",
		description = "Team Chat Premium",
		icon = "crown",
		color = Color3.fromRGB(255, 196, 46),
		gamePassId = 2064101597,
	},
	supporter = {
		name = "Supporter",
		description = "Supports the Team Chat plugin",
		icon = "heart",
		color = Color3.fromRGB(240, 82, 140),
		gamePassId = 2064097630,
	},
	star = {
		name = "Star",
		description = "A shiny gold star next to your name",
		icon = "star",
		color = Color3.fromRGB(250, 190, 40),
		gamePassId = 2064356385,
	},
	diamond = {
		name = "Diamond",
		description = "The rarest badge in the chat",
		icon = "diamond",
		color = Color3.fromRGB(80, 210, 230),
		gamePassId = 2063835954,
	},
} :: { [string]: BadgeDefinition }

-- Display order (custom badges first, then the ones you can buy)
Badges.ORDER = { "developer", "premium", "diamond", "star", "supporter" }

-- Custom badges for specific users: [userId] = { badge ids }. People can have
-- several badges; they show in ORDER, after the verified badge.
Badges.USERS = {
	[7091790691] = { "developer" }, -- D3veloperHac
} :: { [number]: { string } }

return Badges
