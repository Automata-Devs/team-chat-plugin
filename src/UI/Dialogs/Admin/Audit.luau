--!strict
--[[
	Audit

	The admin dashboard's Audit log section: every moderation action
	(Services/Admin/AuditLog), searchable and filtered by action or person,
	a page at a time.
]]

local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Shared)

local escape = Shared.escape
local when = Shared.when

local Audit = {}

-- Entries shown at first and added by "Show more"
Audit.PAGE = 40

function Audit.build(view: Shared.View, colors, nextOrder: () -> number)
	local card, z, state = view.card, view.z, view.state
	local log = view.services.admin.AuditLog
	local search = PanelKit.input(card, state.auditQuery, Language.t("admin.searchLog"), nextOrder(), z, colors)
	search.Name = "LogSearch"
	search.FocusLost:Connect(function()
		if search.Text ~= state.auditQuery then
			state.auditQuery = search.Text
			state.auditLimit = Audit.PAGE
			view.render()
		end
	end)
	local filters = PanelKit.row(card, nextOrder(), z)
	filters.Name = "LogFilters"
	PanelKit.button(
		filters,
		Language.t("admin.allActions"),
		if state.auditAction == nil then "selected" else "choice",
		0,
		z,
		colors,
		function()
			state.auditAction = nil
			view.render()
		end
	)
	for index, action in ipairs(log.actions()) do
		PanelKit.button(
			filters,
			Language.tOr("admin.action." .. action, action),
			if state.auditAction == action then "selected" else "choice",
			index,
			z,
			colors,
			function()
				state.auditAction = action
				state.auditLimit = Audit.PAGE
				view.render()
			end
		).Name = "Filter_"
			.. action
	end
	if state.auditTarget then
		PanelKit.button(card, Language.t("admin.clearPerson"), "secondary", nextOrder(), z, colors, function()
			state.auditTarget = nil
			view.render()
		end).Name =
			"ClearPerson"
	end
	local all = log.list({ query = state.auditQuery, action = state.auditAction, targetId = state.auditTarget })
	PanelKit.text(card, Language.t("admin.logCount", { count = #all }), "heading", nextOrder(), z, colors)
	local box = PanelKit.box(card, nextOrder(), z, colors)
	box.Name = "AuditLog"
	if #all == 0 then
		PanelKit.text(box, Language.t("admin.logEmpty"), "muted", 1, z, colors)
	end
	for index, entry in ipairs(all) do
		if index > state.auditLimit then
			break
		end
		local line = Language.t("admin.logLine", {
			actor = "<b>" .. escape(entry.actorName) .. "</b>",
			action = Language.tOr("admin.action." .. entry.action, entry.action),
			target = if entry.targetName or entry.targetId
				then "<b>" .. escape(tostring(entry.targetName or entry.targetId)) .. "</b>"
				else "",
		})
		local extra = {}
		if entry.detail then
			table.insert(extra, escape(entry.detail))
		end
		if entry.reason then
			table.insert(extra, "\u{201C}" .. escape(entry.reason) .. "\u{201D}")
		end
		PanelKit.text(
			box,
			'<font transparency="0.4">'
				.. when(entry.time)
				.. "</font>  "
				.. line
				.. (if #extra > 0 then "  \u{00B7}  " .. table.concat(extra, "  \u{00B7}  ") else ""),
			"body",
			index,
			z,
			colors
		).Name = "Entry_"
			.. index
	end
	if #all > state.auditLimit then
		PanelKit.button(card, Language.t("admin.showMore"), "secondary", nextOrder(), z, colors, function()
			state.auditLimit += Audit.PAGE
			view.render()
		end).Name =
			"ShowMore"
	end
end

return Audit
