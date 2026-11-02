--!strict
-- Counts what's in the place

local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "stats",
	Aliases = { "count" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Studio" },
	Description = "Show counts of parts, scripts and more",
	Contributors = { "D3veloperHac" },
	Args = {},
	Function = function(_speaker, _args, ctx)
		local counts = { total = 0, parts = 0, models = 0, scripts = 0, guis = 0, lights = 0 }
		for _, instance in ipairs(game:GetDescendants()) do
			counts.total += 1
			if instance:IsA("BasePart") then
				counts.parts += 1
			elseif instance:IsA("Model") then
				counts.models += 1
			elseif instance:IsA("LuaSourceContainer") then
				counts.scripts += 1
			elseif instance:IsA("GuiObject") then
				counts.guis += 1
			elseif instance:IsA("Light") then
				counts.lights += 1
			end
		end
		local fields = {}
		for _, key in ipairs({ "total", "parts", "models", "scripts", "guis", "lights" }) do
			table.insert(
				fields,
				{ name = Language.t("embed.stats." .. key), value = tostring(counts[key]), inline = true }
			)
		end
		ctx.addEmbed({ title = Language.t("embed.stats.title"), fields = fields })
	end,
}
