--!strict
-- Claims your current selection so others know you're editing it
-- Uses StudioCollab for shared claim storage

local Selection = game:GetService("Selection")
local StudioCollab = require(script.Parent.Parent.Parent.Services.StudioCollab)
local Language = require(script.Parent.Parent.Parent.Core.Language)

return {
	Name = "claim",
	Aliases = { "lock" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Studio" },
	Description = "Claim the selected instances (others are warned if they edit them)",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "note", description = "What you're working on", optional = true },
	},
	Function = function(speaker, args, ctx)
		local selected = Selection:Get()
		if #selected == 0 then
			ctx.addSystemMessage(Language.t("reply.claim.selectFirst"))
			return
		end

		local note = #args > 0 and table.concat(args, " ") or nil
		local claimed, conflicts = 0, {}

		for _, instance in selected do
			local ok, owner = StudioCollab.claim(instance, speaker.userId, note)
			if ok then
				claimed += 1
			else
				table.insert(conflicts, `{instance.Name} ({owner})`)
			end
		end

		ctx.addSystemMessage(Language.t("reply.claim.done", { count = claimed }))
		if #conflicts > 0 then
			ctx.addSystemMessage(Language.t("reply.claim.already", { names = table.concat(conflicts, ", ") }))
		end
	end,
}
