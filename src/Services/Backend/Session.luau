--!strict
--[[
	Session

	My sign-in to a backend: its session token and who I am there, kept in
	plugin settings on this computer (never in the place), one per server URL.
]]

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)

export type Session = { token: string, userId: string, username: string? }

local Session = {}

local function all(): { [string]: Session }
	local saved = Settings.getJson(BackendConfig.SETTING_KEY_SESSIONS, {})
	return if type(saved) == "table" then saved else {}
end

function Session.get(url: string): Session?
	local session = all()[url]
	if type(session) == "table" and type(session.token) == "string" and type(session.userId) == "string" then
		return session
	end
	return nil
end

function Session.set(url: string, session: Session)
	local sessions = all()
	sessions[url] = session
	Settings.setJson(BackendConfig.SETTING_KEY_SESSIONS, sessions)
end

function Session.clear(url: string)
	local sessions = all()
	sessions[url] = nil
	Settings.setJson(BackendConfig.SETTING_KEY_SESSIONS, sessions)
end

return Session
