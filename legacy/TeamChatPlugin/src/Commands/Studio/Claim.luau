--!strict
-- Claims your current selection so others know you're editing it
-- Uses StudioNetwork for shared claim storage

local Selection = game:GetService("Selection")
local StudioNetwork = require(script.Parent.Parent.Parent.Networking.StudioNetwork)

return {
	Name = "claim",
	Aliases = {"lock"},
	Prefixes = {"/"},
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = {"Studio"},
	Description = "Claim the selected instances (others are warned if they edit them)",
	Contributors = {"D3veloperHac"},
	Args = {"[note]"},
	Function = function(speaker, args, ctx)
		local selected = Selection:Get()
		if #selected == 0 then
			ctx.addSystemMessage("Select something to claim first.")
			return
		end

		local note = #args > 0 and table.concat(args, " ") or nil
		local claimed, conflicts = 0, {}

		for _, instance in selected do
			local ok, owner = StudioNetwork.claim(instance, speaker.userId, note)
			if ok then
				claimed += 1
			else
				table.insert(conflicts, `{instance.Name} ({owner})`)
			end
		end

		ctx.addSystemMessage(`Claimed {claimed} instance(s).`)
		if #conflicts > 0 then
			ctx.addSystemMessage("Already claimed: " .. table.concat(conflicts, ", "))
		end
	end,
}