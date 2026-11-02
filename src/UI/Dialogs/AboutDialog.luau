--!
-- AboutDialog
-- The "About" modal (info button in the sidebar): what the plugin is, its
-- version and author, the disclaimer that it isn't affiliated with Roblox,
-- the terms of use and what data it stores.
--!

local ModalKit = require(script.Parent.ModalKit)
local PluginConfig = require(script.Parent.Parent.Parent.Config.Constants)

local Z = 32 -- above the other dialogs

-- Sections: a heading and paragraphs, as Core/Language keys
local SECTIONS = {
	{ heading = "about.disclaimer", body = { "about.disclaimer1", "about.disclaimer2" } },
	{
		heading = "about.terms",
		body = { "about.terms1", "about.terms2", "about.terms3", "about.terms4", "about.terms5" },
	},
	{ heading = "about.data", body = { "about.data1", "about.data2" } },
}

local AboutDialog = {}

--!
-- kit: a ModalKit. params: { getThemeColors: () -> palette }
-- Returns { open(), close(), isVisible(), recolor() }
--!
function AboutDialog.create(kit, params)
	local colors = params.getThemeColors()
	local modal = kit.createModal({ name = "AboutDialog", title = "About Team Chat", iconKey = "about", zIndex = Z })
	local card = modal.card
	local z = modal.contentZIndex

	local order = 2
	local function add(role: string, key: string, vars: { [string]: any }?)
		ModalKit.addTextKey(card, role, key, order, z, colors, vars)
		order += 1
	end

	add(
		"muted",
		"about.byline",
		{ version = tostring(PluginConfig.PLUGIN_VERSION), author = PluginConfig.PLUGIN_AUTHOR }
	)
	add("body", "about.intro")
	for _, section in ipairs(SECTIONS) do
		add("heading", section.heading)
		for _, paragraph in ipairs(section.body) do
			add("body", paragraph)
		end
	end
	add("muted", "about.notAffiliated")

	local self = { modal = modal } -- modal: joined into the Settings tabs

	function self.open()
		card.CanvasPosition = Vector2.zero
		modal.open()
	end

	function self.close()
		modal.close()
	end

	function self.isVisible(): boolean
		return modal.isVisible()
	end

	function self.recolor()
		ModalKit.recolorText(card, params.getThemeColors())
	end

	return self
end

return AboutDialog
