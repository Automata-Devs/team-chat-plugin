--!strict
--[[
	NewBot

	The developer portal's New bot form: a Studio bot (a script that runs in
	your Studio) or a web bot (your own server), with a name and a URL.
]]

local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Shared)

local NewBot = {}

function NewBot.build(view: Shared.View, colors, nextOrder: () -> number)
	local card, z, state = view.card, view.z, view.state
	local bots = view.services.bots

	local form = PanelKit.box(card, nextOrder(), z, colors)
	form.Name = "NewBot"
	local kinds = PanelKit.row(form, 1, z)
	PanelKit.button(
		kinds,
		Language.t("dev.kindStudio"),
		if state.newKind == "studio" then "selected" else "choice",
		1,
		z,
		colors,
		function()
			state.newKind = "studio"
			view.render()
		end
	).Name =
		"KindStudio"
	PanelKit.button(
		kinds,
		Language.t("dev.kindWeb"),
		if state.newKind == "web" then "selected" else "choice",
		2,
		z,
		colors,
		function()
			state.newKind = "web"
			view.render()
		end
	).Name =
		"KindWeb"
	PanelKit.text(
		form,
		Language.t(if state.newKind == "web" then "dev.webHint" else "dev.studioHint"),
		"muted",
		2,
		z,
		colors
	)
	local name = PanelKit.input(form, "", Language.t("dev.namePlaceholder"), 3, z, colors)
	name.Name = "NameInput"
	local url: TextBox? = nil
	if state.newKind == "web" then
		url = PanelKit.input(form, "", "https://example.com/teamchat", 4, z, colors);
		(url :: TextBox).Name = "UrlInput"
	end
	PanelKit.button(form, Language.t("dev.create"), "primary", 5, z, colors, function()
		local botName = string.match(name.Text, "^%s*(.-)%s*$") or ""
		if not string.match(botName, "^[%w_]+$") then
			view.setStatus(Language.t("dev.badName"))
			return
		end
		if state.newKind == "web" then
			local id, problem = bots.createWeb(botName, if url then url.Text else "")
			if id then
				state.section = "bots"
				state.openBot = id
				state.page = "overview"
				view.setStatus(Language.t("dev.createdWeb", { name = botName }))
			else
				view.setStatus(Language.t("dev." .. tostring(problem)))
			end
		else
			local module, problem = bots.create(botName)
			if module and view.openScript then
				view.openScript(module)
			end
			if module then
				state.section = "bots"
			end
			view.setStatus(
				if module
					then Language.t("bot.created", { name = botName })
					else Language.t(
						if problem == "exists" then "bot.exists" else "bot.signedOut",
						{ name = botName }
					)
			)
		end
	end).Name =
		"CreateButton"
end

return NewBot
