--!strict
--[[
	DeveloperDialog

	The developer portal (Settings > Developer): make and manage your Team
	Chat bots, like Discord's developer portal. Each of your bots shows its
	kind, status and commands; web bots also their URL and token (with Sync
	commands and New token), Studio bots Open script and Reload. Below,
	a form makes a new Studio or web bot. docs/BOTS.md explains bots.
]]

local Bots = require(script.Parent.Parent.Parent.Services.Bots)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.PanelKit)

local Z = 32
local MASKED = string.rep("\u{2022}", 12)

local DeveloperDialog = {}

--!
-- kit: a ModalKit. params: { getThemeColors, openScript: (LuaSourceContainer) -> () }
-- Returns { open(), close(), isVisible(), recolor(), modal }
--!
function DeveloperDialog.create(kit, params)
	local modal = kit.createModal({ name = "DeveloperDialog", title = "Developer", iconKey = "command", zIndex = Z })
	local card = modal.card
	local z = modal.contentZIndex
	local keep = {}
	for _, child in ipairs(card:GetChildren()) do
		keep[child] = true -- the modal's own title, close button and layout
	end

	local shownTokens: { [string]: boolean } = {}
	local newKind = "studio"
	local status = "" -- the last thing that happened ("Created Weather", an error…)

	local self = { modal = modal }
	local render: () -> ()

	local function setStatus(text: string)
		status = text
		render()
	end

	local function botBox(bot, order: number, colors)
		local box = PanelKit.box(card, order, z, colors)
		box.Name = "Bot_" .. bot.id
		local header = PanelKit.row(box, 1, z)
		PanelKit.text(header, "<b>" .. bot.name .. "</b>", "title", 1, z, colors).AutomaticSize = Enum.AutomaticSize.XY
		header:FindFirstChild("Text").Size = UDim2.fromOffset(0, 0)
		PanelKit.pill(
			header,
			Language.t(if bot.kind == "web" then "dev.kindWeb" else "dev.kindStudio"),
			colors.sendButton,
			2,
			z
		)
		local statusKey = if bot.disabled then "dev.disabled" elseif bot.online then "dev.online" else "dev.offline"
		PanelKit.pill(
			header,
			Language.t(statusKey),
			if bot.disabled then colors.danger elseif bot.online then colors.success else colors.timestamp,
			3,
			z
		)
		if bot.description ~= "" then
			PanelKit.text(box, bot.description, "muted", 2, z, colors)
		end
		local commands = {}
		for _, command in ipairs(bot.commands) do
			table.insert(commands, "/" .. command.name)
		end
		PanelKit.text(
			box,
			if #commands > 0 then table.concat(commands, "   ") else Language.t("dev.noCommands"),
			"mono",
			3,
			z,
			colors
		)

		if bot.kind == "web" then
			PanelKit.text(box, Language.t("dev.url"), "heading", 4, z, colors)
			local urlRow = PanelKit.row(box, 5, z)
			local url = PanelKit.input(urlRow, bot.url or "", "https://", 1, z, colors, { width = UDim.new(1, -70) })
			PanelKit.button(urlRow, Language.t("dev.save"), "secondary", 2, z, colors, function()
				setStatus(Language.t(if Bots.updateWeb(bot.id, { url = url.Text }) then "dev.saved" else "dev.badUrl"))
			end)
			PanelKit.text(box, Language.t("dev.token"), "heading", 6, z, colors)
			local tokenRow = PanelKit.row(box, 7, z)
			local token = Bots.tokenOf(bot.id) or ""
			PanelKit.input(
				tokenRow,
				if shownTokens[bot.id] then token else MASKED .. string.sub(token, -4),
				"",
				1,
				z,
				colors,
				{ width = UDim.new(1, -150), readOnly = true, mono = true }
			)
			PanelKit.button(
				tokenRow,
				Language.t(if shownTokens[bot.id] then "dev.hide" else "dev.show"),
				"secondary",
				2,
				z,
				colors,
				function()
					shownTokens[bot.id] = not shownTokens[bot.id]
					render()
				end
			)
			PanelKit.button(tokenRow, Language.t("dev.newToken"), "secondary", 3, z, colors, function()
				Bots.regenerateToken(bot.id)
				shownTokens[bot.id] = true
				setStatus(Language.t("dev.tokenChanged"))
			end)
			PanelKit.text(box, Language.t("dev.tokenHint"), "muted", 8, z, colors)
		end

		local actions = PanelKit.row(box, 9, z)
		if bot.kind == "web" then
			PanelKit.button(actions, Language.t("dev.sync"), "primary", 1, z, colors, function()
				setStatus(Language.t("dev.syncing"))
				task.spawn(function()
					local count, problem = Bots.syncWeb(bot.id)
					setStatus(
						if count
							then Language.t("dev.synced", { count = count })
							else Language.t("dev.syncFailed", { error = tostring(problem) })
					)
				end)
			end)
		else
			PanelKit.button(actions, Language.t("dev.openScript"), "primary", 1, z, colors, function()
				local module = Bots.scriptOf(bot.id)
				if module and params.openScript then
					params.openScript(module)
				end
			end)
			PanelKit.button(actions, Language.t("dev.reload"), "secondary", 2, z, colors, function()
				local names = Bots.reload()
				setStatus(Language.t("bot.reloaded", { names = table.concat(names, ", ") }))
			end)
		end
		PanelKit.button(
			actions,
			Language.t(if bot.disabled then "dev.turnOn" else "dev.turnOff"),
			"secondary",
			3,
			z,
			colors,
			function()
				Bots.setDisabled(bot.id, not bot.disabled)
				render()
			end
		)
		PanelKit.button(actions, Language.t("dev.delete"), "danger", 4, z, colors, function()
			Bots.remove(bot.id)
			setStatus(Language.t("bot.removed", { name = bot.name }))
		end)
	end

	render = function()
		local colors = params.getThemeColors()
		PanelKit.clear(card, keep)
		local order = 2
		local function nextOrder(): number
			order += 1
			return order
		end
		PanelKit.text(card, Language.t("dev.intro"), "muted", nextOrder(), z, colors)
		if status ~= "" then
			PanelKit.text(card, status, "body", nextOrder(), z, colors).Name = "Status"
		end

		PanelKit.text(card, Language.t("dev.yourBots"), "heading", nextOrder(), z, colors)
		local mine = Bots.mine()
		if #mine == 0 then
			PanelKit.text(card, Language.t("dev.noBots"), "muted", nextOrder(), z, colors)
		end
		for _, bot in ipairs(mine) do
			botBox(bot, nextOrder(), colors)
		end

		-- A new bot
		PanelKit.text(card, Language.t("dev.newBot"), "heading", nextOrder(), z, colors)
		local form = PanelKit.box(card, nextOrder(), z, colors)
		form.Name = "NewBot"
		local kinds = PanelKit.row(form, 1, z)
		PanelKit.button(
			kinds,
			Language.t("dev.kindStudio"),
			if newKind == "studio" then "primary" else "secondary",
			1,
			z,
			colors,
			function()
				newKind = "studio"
				render()
			end
		).Name =
			"KindStudio"
		PanelKit.button(
			kinds,
			Language.t("dev.kindWeb"),
			if newKind == "web" then "primary" else "secondary",
			2,
			z,
			colors,
			function()
				newKind = "web"
				render()
			end
		).Name =
			"KindWeb"
		PanelKit.text(
			form,
			Language.t(if newKind == "web" then "dev.webHint" else "dev.studioHint"),
			"muted",
			2,
			z,
			colors
		)
		local name = PanelKit.input(form, "", Language.t("dev.namePlaceholder"), 3, z, colors)
		name.Name = "NameInput"
		local url: TextBox? = nil
		if newKind == "web" then
			url = PanelKit.input(form, "", "https://example.com/teamchat", 4, z, colors);
			(url :: TextBox).Name = "UrlInput"
		end
		PanelKit.button(form, Language.t("dev.create"), "primary", 5, z, colors, function()
			local botName = string.match(name.Text, "^%s*(.-)%s*$") or ""
			if not string.match(botName, "^[%w_]+$") then
				setStatus(Language.t("dev.badName"))
				return
			end
			if newKind == "web" then
				local id, problem = Bots.createWeb(botName, if url then url.Text else "")
				setStatus(
					if id
						then Language.t("dev.createdWeb", { name = botName })
						else Language.t("dev." .. tostring(problem))
				)
			else
				local module, problem = Bots.create(botName)
				if module and params.openScript then
					params.openScript(module)
				end
				setStatus(
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

	function self.open()
		status = ""
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

return DeveloperDialog
