--[[
	Tests for the pure helpers (Duration, RichText, Links) and the services
	fixed during the restructure (StudioCollab camera sharing and claims,
	Lifetime-cancelled timers).
]]

local Harness = require(script.Parent.Parent.Harness)

return function(t)
	local app = Harness.boot()
	local timerFired = false
	local ok, err = pcall(function()
		local copy = app.copy
		local Duration = require(copy.Util.Duration) :: any
		local RichText = require(copy.Util.RichText) :: any
		local Links = require(copy.Util.Links) :: any
		local StudioCollab = require(copy.Services.StudioCollab) :: any
		local Identity = require(copy.Core.Identity) :: any

		-- Duration
		t.equal("1h30m", Duration.parse("1h30m"), 5400)
		t.equal("plain seconds", Duration.parse("45"), 45)
		t.equal("1mo", Duration.parse("1mo"), 2592000)
		t.equal("unknown unit", Duration.parse("3x"), nil)

		-- RichText
		t.equal("escape handles & < >", RichText.escape("a < b & c > d"), "a &lt; b &amp; c &gt; d")
		t.equal("entities are shown literally", RichText.escape("&lt;"), "&amp;lt;")
		local styled = RichText.styleContent("see www.roblox.com now")
		t.check(
			"links are underlined: " .. styled,
			string.find(styled, "<u><font color=", 1, true) ~= nil
				and string.find(styled, "www.roblox.com</font></u> now", 1, true) ~= nil
		)

		-- Links
		local found = Links.find("go to https://example.com/a?b=1, or www.test.org.")
		t.equal("two links found", #found, 2)
		t.equal("trailing punctuation excluded", found[1].url, "https://example.com/a?b=1")
		t.equal("www link gets a scheme", found[2].url, "https://www.test.org")
		local meta = Links.buildMeta("Bob", "hi www.x.com", os.time())
		t.check(
			"the text label holds just the content (author is in the header)",
			meta.plainText == "hi www.x.com" and meta.contentOffset == 0
		)

		-- StudioCollab: camera is published after init and reads back
		if Identity.userId > 0 then
			task.wait(0.2)
			local shared = StudioCollab.getUserCameraCFrame(Identity.userId)
			local camera = workspace.CurrentCamera
			t.check(
				"camera position is shared (/goto)",
				shared ~= nil and (shared.Position - camera.CFrame.Position).Magnitude < 0.01
			)
		end

		-- StudioCollab: claims (names with characters attributes don't allow)
		local target = Instance.new("Folder")
		target.Name = "Weird name-with.dots & stuff"
		target.Parent = app.dataFolder()
		local claimed = StudioCollab.claim(target, 1, "note")
		t.check("claiming works for any instance name", claimed == true)
		local again, owner = StudioCollab.claim(target, 2, nil)
		t.check("someone else's claim is reported", again == false and type(owner) == "string")
		StudioCollab.unclaim(target)
		t.check("unclaim frees it", (StudioCollab.claim(target, 2, nil)) == true)

		-- Clicking a link inside message text finds it (UI/Text/TextLayout hit-test),
		-- also after bold text, which is wider
		local MessageText = require(copy.UI.Text.MessageText) :: any
		local TextLayout = require(copy.UI.Text.TextLayout) :: any
		local Theme = require(copy.Config.Theme) :: any
		local TextService = game:GetService("TextService")
		local label = Instance.new("TextLabel")
		label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
		label.TextSize = 14
		label.Size = UDim2.fromOffset(600, 20)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Parent = app.gui
		MessageText.set(label, "**open** www.roblox.com please", Theme.PALETTES.Dark)
		local params = Instance.new("GetTextBoundsParams")
		params.Text = "<b>open</b> "
		params.RichText = true
		params.Font = label.FontFace
		params.Size = 14
		params.Width = 600
		local x = TextService:GetTextBoundsAsync(params).X
		local hit = TextLayout.hitTest(label, x + 8, 5)
		t.check("clicking inside the link finds it", hit ~= nil and hit.style.url == "https://www.roblox.com")
		local before = TextLayout.hitTest(label, 2, 5)
		t.check("clicking before the link finds no link", before == nil or before.style.url == nil)
		label:Destroy()

		-- Timers started through Lifetime (like /timer) are cancelled on unload
		local Lifetime = require(copy.Core.Lifetime) :: any
		Lifetime.delay(0.2, function()
			timerFired = true
		end)
	end)
	local Lifetime = require(app.copy.Core.Lifetime) :: any
	app.stop()
	task.wait(0.3)
	t.check("Lifetime timers don't fire after unload", Lifetime.alive == false and not timerFired)
	if not ok then
		error(err, 0)
	end
end
