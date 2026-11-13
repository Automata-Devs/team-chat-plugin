--!strict
--[[
	Premium

	What Team Chat Premium adds: the "premium" badge (Config/Badges, a game
	pass) unlocks these for whoever owns it. Badges stay cosmetic; these are
	the perks.

	Usage:
		local PremiumConfig = require(Config.Premium)
		local max = PremiumConfig.MESSAGE_LENGTH.free
]]

return {
	BADGE = "premium", -- Config/Badges id

	-- Settings > Appearance themes only Premium can pick (Config/Theme PALETTES)
	THEMES = { "Midnight", "Gold" },

	-- Characters in one message (the backend stores up to 4000)
	MESSAGE_LENGTH = { free = 2000, premium = 4000 },

	-- Answers in one poll
	POLL_OPTIONS = { free = 10, premium = 20 },
}
