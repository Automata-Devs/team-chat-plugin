--!strict
--[[
	Shared

	What the developer portal's sections and bot pages share: the portal's
	state and actions (View), text helpers and the bot status pill.
]]

local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)

export type State = {
	section: string,
	openBot: string?, -- the bot whose page is open
	page: string,
	shownTokens: { [string]: boolean },
	consoles: { [string]: { any } }, -- each bot's test results, newest first
	consoleInput: { [string]: string },
	running: boolean, -- a test or health check is on its way
	newKind: string, -- "studio" | "web"
	confirming: string?, -- an action waiting for a second click
	status: string, -- the last thing that happened ("Created Weather", an error...)
}

export type View = {
	card: ScrollingFrame,
	z: number,
	services: any,
	state: State,
	render: () -> (),
	-- Shows a status line and re-draws
	setStatus: (text: string) -> (),
	openScript: ((LuaSourceContainer) -> ())?,
	-- The portal's public object (the console exposes runTest on it for tests)
	dialog: { [string]: any },
}

local Shared = {}

function Shared.escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

function Shared.when(time: number?): string
	return if time and time > 0 then os.date("%d/%m %H:%M", time) else "-"
end

function Shared.statusPill(parent: Instance, bot, order: number, colors, z: number)
	PanelKit.pill(
		parent,
		Language.t(if bot.disabled then "dev.disabled" elseif bot.online then "dev.online" else "dev.offline"),
		if bot.disabled then colors.danger elseif bot.online then colors.success else colors.timestamp,
		order,
		z
	)
end

return Shared
