--!strict
--[[
	Edit

	A bot's Edit page: its name, description and avatar as Team Chat shows
	them, and which commands people can use (over what the script or server
	says).
]]

local Language = require(script.Parent.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Parent.Shared)

local Edit = {}

function Edit.build(view: Shared.View, bot, colors, nextOrder: () -> number)
	local card, z = view.card, view.z
	local bots = view.services.bots

	PanelKit.text(card, Language.t("dev.editHint"), "muted", nextOrder(), z, colors)
	local form = PanelKit.box(card, nextOrder(), z, colors)
	form.Name = "EditForm"
	PanelKit.text(form, Language.t("dev.name"), "heading", 1, z, colors)
	local name = PanelKit.input(form, bot.name, bot.name, 2, z, colors)
	name.Name = "NameInput"
	PanelKit.text(form, Language.t("dev.description"), "heading", 3, z, colors)
	local description = PanelKit.input(form, bot.description, Language.t("dev.descriptionPlaceholder"), 4, z, colors)
	description.Name = "DescriptionInput"
	PanelKit.text(form, Language.t("dev.avatar"), "heading", 5, z, colors)
	local avatarRow = PanelKit.row(form, 6, z)
	PanelKit.avatar(avatarRow, nil, 30, 1, z, colors).Image = bot.avatar or ""
	local avatar = PanelKit.input(
		avatarRow,
		bot.avatar or "",
		"rbxassetid://… " .. Language.t("dev.orImageId"),
		2,
		z,
		colors,
		{ width = UDim.new(1, -40) }
	)
	avatar.Name = "AvatarInput"
	PanelKit.button(form, Language.t("dev.saveDetails"), "primary", 7, z, colors, function()
		local ok = bots.editBot(bot.id, { name = name.Text, description = description.Text, avatar = avatar.Text })
		view.setStatus(Language.t(if ok then "dev.saved" else "dev.notYours"))
	end).Name =
		"SaveDetails"

	-- Commands: on or off, and their description
	PanelKit.text(card, Language.t("dev.commands", { count = #bot.commands }), "heading", nextOrder(), z, colors)
	local list = PanelKit.box(card, nextOrder(), z, colors)
	list.Name = "EditCommands"
	if #bot.commands == 0 then
		PanelKit.text(list, Language.t("dev.noCommands"), "muted", 1, z, colors)
		return
	end
	local enabled: { [string]: boolean } = {}
	local notes: { [string]: TextBox } = {}
	for index, command in ipairs(bot.commands) do
		enabled[command.name] = command.enabled
		local row = PanelKit.row(list, index, z)
		row.Name = "Command_" .. command.name
		local toggle: TextButton
		toggle = PanelKit.button(
			row,
			Language.t(if command.enabled then "dev.on" else "dev.off"),
			if command.enabled then "primary" else "secondary",
			1,
			z,
			colors,
			function()
				enabled[command.name] = not enabled[command.name]
				toggle.Text = Language.t(if enabled[command.name] then "dev.on" else "dev.off")
			end
		)
		toggle.Name = "Toggle"
		PanelKit.text(row, "<b>/" .. command.name .. "</b>", "body", 2, z, colors).Size = UDim2.fromOffset(110, 28)
		notes[command.name] = PanelKit.input(
			row,
			command.description,
			Language.t("dev.descriptionPlaceholder"),
			3,
			z,
			colors,
			{ width = UDim.new(1, -190) }
		)
	end
	PanelKit.button(card, Language.t("dev.saveCommands"), "primary", nextOrder(), z, colors, function()
		local off, texts = {}, {}
		for _, command in ipairs(bot.commands) do
			if not enabled[command.name] then
				table.insert(off, command.name)
			end
			texts[command.name] = notes[command.name].Text
		end
		local ok = bots.editBot(bot.id, { disabledCommands = off, commandNotes = texts })
		view.setStatus(Language.t(if ok then "dev.saved" else "dev.notYours"))
	end).Name =
		"SaveCommands"
end

return Edit
