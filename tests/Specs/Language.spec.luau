--[[
	Languages: every language file has every English key (with the same
	{placeholders}), lookups fall back to English, and switching language in
	Settings re-labels the plugin right away.
]]

local Harness = require(script.Parent.Parent.Harness)

local function placeholders(text: string): string
	local found = {}
	for name in string.gmatch(text, "{(%w+)}") do
		table.insert(found, name)
	end
	table.sort(found)
	return table.concat(found, ",")
end

return function(t)
	local app = Harness.boot({ settings = { TeamChatAboutSeen_v1 = true, TeamChatLastSeenVersion_v1 = "x" } })
	local ok, err = pcall(function()
		local ui, gui = app.ui, app.gui
		local Language = require(app.copy.Core.Language) :: any
		local Constants = require(app.copy.Config.Constants) :: any

		-- Every language is complete and keeps the placeholders
		local english
		for _, info in ipairs(Language.list()) do
			if info.code == "en" then
				english = info.strings
			end
		end
		t.check("English is there", english ~= nil)
		t.check("there are several languages (" .. #Language.list() .. ")", #Language.list() >= 6)
		for _, info in ipairs(Language.list()) do
			local missing, extra, badVars = {}, {}, {}
			for key, text in pairs(english) do
				local translated = info.strings[key]
				if translated == nil then
					table.insert(missing, key)
				elseif placeholders(translated) ~= placeholders(text) then
					table.insert(badVars, key)
				end
			end
			for key in pairs(info.strings) do
				if english[key] == nil then
					table.insert(extra, key)
				end
			end
			t.check(
				("%s is complete (missing: %s; unknown: %s; placeholders: %s)"):format(
					info.code,
					table.concat(missing, " "),
					table.concat(extra, " "),
					table.concat(badVars, " ")
				),
				#missing == 0 and #extra == 0 and #badVars == 0
			)
		end

		-- Lookups
		t.equal("t() fills placeholders", Language.t("composer.placeholderDm", { name = "Bob" }), "Message Bob")
		t.equal("unknown keys come back as the key", Language.t("no.such.key"), "no.such.key")

		-- Switching in Settings re-labels at once and is saved
		ui.openSettings()
		Harness.settle(2)
		local page = gui:FindFirstChild("SettingsDialog", true) :: Frame
		local languageCard = page:FindFirstChild("Setting_language", true) :: Frame
		t.check(
			"Settings has a Language dropdown",
			languageCard and languageCard:FindFirstChild("Dropdown", true) ~= nil
		)
		local controls = ui.getSettingControls()
		controls.language.open()
		Harness.settle()
		local list = page:FindFirstChild("DropdownList", true) :: Frame
		t.check(
			"it lists Auto and each language in its own name",
			list ~= nil
				and list:FindFirstChild("Option_auto") ~= nil
				and (list:FindFirstChild("Option_nl") :: TextButton).Text == "Nederlands"
		)
		controls.language.choose("nl")
		Harness.settle()
		t.equal("the choice is saved", app.settings[Constants.SETTING_KEY_LANGUAGE], "nl")
		t.equal("in use right away", Language.current(), "nl")

		local title = page:FindFirstChild("Title", true) :: TextLabel
		t.equal("window titles change", title.Text, "Instellingen")
		t.equal(
			"setting names change",
			((page:FindFirstChild("Setting_theme", true) :: Frame):FindFirstChild("Title", true) :: TextLabel).Text,
			"Thema"
		)
		t.equal(
			"dropdown choices change",
			((page:FindFirstChild("Setting_theme", true) :: Frame):FindFirstChild("Value", true) :: TextLabel).Text,
			"Automatisch"
		)
		local general = page:FindFirstChild("Tab_General", true) :: TextButton
		t.equal("tab names change", (general:FindFirstChild("Label") :: TextLabel).Text, "Algemeen")
		ui.closeSettings()
		t.equal("the message box changes", ui.textBox.PlaceholderText, "Typ een bericht...")
		local menu = gui:FindFirstChild("ContextMenu", true) :: Frame
		t.equal(
			"the right-click menu changes",
			((menu:FindFirstChild("ReplyItem") :: TextButton):FindFirstChild("Label") :: TextLabel).Text,
			"Beantwoorden"
		)

		-- Text built elsewhere: command replies and descriptions, What's New notes
		t.equal("command replies change", Language.t("reply.clear.done"), "Chat gewist.")
		t.equal(
			"command descriptions change",
			Language.tOr("command.coinflip.description", "Flip a coin"),
			"Gooi een munt op"
		)
		t.equal("translated notes pick the language", Language.pick({ en = "Fixed", nl = "Opgelost" }), "Opgelost")
		t.equal("untranslated notes stay English", Language.pick({ en = "Fixed" }), "Fixed")
		t.equal("plain notes stay as they are", Language.pick("Fixed"), "Fixed")

		-- Back to English
		app.setSetting("language", "en")
		Harness.settle()
		t.equal("and back", ui.textBox.PlaceholderText, "Type a message...")
		app.setSetting("language", "auto")
		t.equal("Auto is saved as auto", app.settings[Constants.SETTING_KEY_LANGUAGE], "auto")
	end)
	app.stop()
	if not ok then
		error(err, 0)
	end
end
