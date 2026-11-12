--!strict
--[[
	Developer

	The developer portal (Settings > Developer), like Discord's: your bots,
	a New bot form and the Docs. Each bot has its own page (BotPage) with
	Overview, Console, Logs and Edit.

	Usage:
		local developer = Developer.create(kit, { getThemeColors = getPalette, services = services })
		developer.openBot(id, "console")
]]

local BotList = require(script.BotList)
local BotPage = require(script.BotPage)
local Docs = require(script.Docs)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local NewBot = require(script.NewBot)
local PanelKit = require(script.Parent.Kit.PanelKit)
local Shared = require(script.Shared)

local Z = 32
local SECTIONS = { "bots", "new", "docs" }

export type Params = {
	getThemeColors: () -> any,
	services: any, -- { bots }
	openScript: ((LuaSourceContainer) -> ())?,
}

local Developer = {}

--[=[
	kit: a ModalKit. Returns { open(section?), close(), isVisible(), recolor(), openBot(id, page?), modal }.
]=]
function Developer.create(kit, params: Params)
	local modal = kit.createModal({ name = "DeveloperDialog", title = "Developer", iconKey = "command", zIndex = Z })
	local card = modal.card
	local z = modal.contentZIndex
	local keep = {}
	for _, child in ipairs(card:GetChildren()) do
		keep[child] = true -- the modal's own title, close button and layout
	end
	local bots = params.services.bots

	local state: Shared.State = {
		section = "bots",
		openBot = nil,
		page = "overview",
		shownTokens = {},
		consoles = {},
		consoleInput = {},
		running = false,
		newKind = "studio",
		confirming = nil,
		status = "",
	}

	local self: { [string]: any } = { modal = modal }
	local render: () -> ()

	local view: Shared.View = {
		card = card,
		z = z,
		services = params.services,
		state = state,
		openScript = params.openScript,
		dialog = self,
		render = function()
			render()
		end,
		setStatus = function(text: string)
			state.status = text
			state.confirming = nil
			render()
		end,
	}

	local function botById(id: string)
		for _, bot in ipairs(bots.mine()) do
			if bot.id == id then
				return bot
			end
		end
		return nil
	end

	render = function()
		local colors = params.getThemeColors()
		PanelKit.clear(card, keep)
		local order = 2
		local function nextOrder(): number
			order += 1
			return order
		end
		local tabs = {}
		for _, key in ipairs(SECTIONS) do
			table.insert(tabs, { key = key, label = Language.t("dev.section." .. key) })
		end
		PanelKit.tabs(card, tabs, state.section, nextOrder(), z, colors, function(key)
			state.section = key
			state.openBot = nil
			state.confirming = nil
			state.status = ""
			render()
		end)
		if state.status ~= "" then
			PanelKit.text(card, state.status, "body", nextOrder(), z, colors).Name = "Status"
		end
		if state.section == "new" then
			NewBot.build(view, colors, nextOrder)
		elseif state.section == "docs" then
			Docs.build(view, colors, nextOrder)
		else
			local bot = if state.openBot then botById(state.openBot) else nil
			if bot then
				BotPage.build(view, bot, colors, nextOrder)
			else
				state.openBot = nil
				BotList.build(view, colors, nextOrder)
			end
		end
	end

	function self.open(sectionKey: string?)
		state.status = ""
		state.confirming = nil
		if sectionKey and table.find(SECTIONS, sectionKey) then
			state.section = sectionKey
		end
		render()
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
		if modal.isVisible() then
			render()
		end
	end
	--[=[
		Shows one of your bots' pages.
	]=]
	function self.openBot(id: string, pageKey: string?)
		state.section = "bots"
		state.openBot = id
		state.page = pageKey or "overview"
		render()
	end
	return self
end

return Developer
