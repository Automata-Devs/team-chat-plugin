--!strict
--[[
	Admin

	The admin dashboard (Settings > Admin), for moderators and up, with a
	tab per section: Overview, Members, Moderation, Audit log and Chat
	tools. It re-draws on open, on theme changes and when the data changes
	elsewhere (commands, other moderators).

	Usage:
		local admin = Admin.create(kit, { getThemeColors = getPalette, services = services })
		admin.open("members")
]]

local Audit = require(script.Audit)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)
local Members = require(script.Members)
local Moderation = require(script.Moderation)
local Overview = require(script.Overview)
local PanelKit = require(script.Parent.Kit.PanelKit)
local Shared = require(script.Shared)
local Tools = require(script.Tools)

local Z = 32
local SECTIONS = { "overview", "members", "moderation", "audit", "tools" }

export type Params = {
	getThemeColors: () -> any,
	services: any, -- { admin, bots, chat }
	openScript: ((LuaSourceContainer) -> ())?,
}

local Admin = {}

--[=[
	kit: a ModalKit. Returns { open(section?), close(), isVisible(), recolor(), modal }.
]=]
function Admin.create(kit, params: Params)
	local modal = kit.createModal({ name = "AdminDialog", title = "Admin", iconKey = "settings", zIndex = Z })
	local card = modal.card
	local z = modal.contentZIndex
	local keep = {}
	for _, child in ipairs(card:GetChildren()) do
		keep[child] = true
	end
	local services = params.services
	local admin = services.admin

	local state: Shared.State = {
		section = "overview",
		period = 7,
		memberQuery = "",
		selected = nil,
		auditQuery = "",
		auditAction = nil,
		auditTarget = nil,
		auditLimit = Audit.PAGE,
		confirming = nil,
		status = "",
	}

	local render: () -> ()
	local refresh: () -> ()

	-- Names of ranked people who aren't here and never wrote, looked up once
	-- in the background: drawing never waits on the web
	local names: { [number]: string | false } = {}

	local view: Shared.View = {
		card = card,
		z = z,
		services = services,
		state = state,
		openScript = params.openScript,
		render = function()
			render()
		end,
		act = function(text: string)
			state.status = text
			state.confirming = nil
			render()
		end,
		confirm = function(key: string): boolean
			if state.confirming == key then
				state.confirming = nil
				return true
			end
			state.confirming = key
			render()
			return false
		end,
		nameOf = function(userId: number): string
			local known = names[userId]
			if known then
				return known
			end
			if known == nil then
				names[userId] = false
				task.spawn(function()
					local name = Identity.nameOf(userId)
					if name then
						names[userId] = name
						refresh()
					end
				end)
			end
			return "User " .. userId
		end,
		rankName = function(rank: number): string
			return Language.tOr("rank." .. rank, admin.getRankName(rank))
		end,
		showAudit = function(userId: number)
			state.section = "audit"
			state.auditTarget = userId
			state.auditLimit = Audit.PAGE
			render()
		end,
	}

	render = function()
		local colors = params.getThemeColors()
		PanelKit.clear(card, keep)
		local myRank = admin.getMyRank()
		local order = 2
		local function nextOrder(): number
			order += 1
			return order
		end
		if myRank < 1 then
			PanelKit.text(card, Language.t("admin.noAccess"), "muted", nextOrder(), z, colors).Name = "NoAccess"
			return
		end
		local tabs = {}
		for _, key in ipairs(SECTIONS) do
			table.insert(tabs, { key = key, label = Language.t("admin.section." .. key) })
		end
		PanelKit.tabs(card, tabs, state.section, nextOrder(), z, colors, function(key)
			state.section = key
			state.selected = nil
			state.confirming = nil
			state.status = ""
			render()
		end)
		if state.status ~= "" then
			PanelKit.text(card, state.status, "body", nextOrder(), z, colors).Name = "Status"
		end
		local section = state.section
		if section == "members" then
			Members.build(view, colors, nextOrder, myRank)
		elseif section == "moderation" then
			Moderation.build(view, colors, nextOrder, myRank)
		elseif section == "audit" then
			Audit.build(view, colors, nextOrder)
		elseif section == "tools" then
			Tools.build(view, colors, nextOrder, myRank)
		else
			Overview.build(view, colors, nextOrder)
		end
	end

	local queued = false
	refresh = function()
		if queued then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			if modal.isVisible() then
				render()
			end
		end)
	end
	Lifetime.add(admin.onAdminEvent(refresh))
	Lifetime.add(admin.AuditLog.onChanged(function()
		if state.section == "audit" then
			refresh()
		end
	end))
	Lifetime.connect(services.chat.getFolder().ChildAdded, function()
		if state.section == "overview" then
			refresh()
		end
	end)

	local self = { modal = modal }

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
	return self
end

return Admin
