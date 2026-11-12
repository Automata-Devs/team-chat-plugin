--!strict
--[[
	Shared

	What the admin dashboard's sections share: the dashboard's state and
	actions (View) and two text helpers.
]]

export type State = {
	section: string,
	period: number, -- days the numbers cover (7 or 30)
	memberQuery: string,
	selected: number?, -- the member whose details are shown
	auditQuery: string,
	auditAction: string?,
	auditTarget: number?,
	auditLimit: number,
	confirming: string?, -- an action waiting for a second click
	status: string,
}

export type View = {
	card: ScrollingFrame,
	z: number,
	services: any,
	state: State,
	render: () -> (),
	-- Shows a status line after an action and re-draws
	act: (text: string) -> (),
	-- A second click confirms: true when this click is it
	confirm: (key: string) -> boolean,
	nameOf: (userId: number) -> string,
	rankName: (rank: number) -> string,
	-- Opens the audit log filtered to one person
	showAudit: (userId: number) -> (),
	openScript: ((LuaSourceContainer) -> ())?,
}

local Shared = {}

function Shared.when(time: number?): string
	return if time and time > 0 then os.date("%d/%m %H:%M", time) else "-"
end

function Shared.escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

return Shared
