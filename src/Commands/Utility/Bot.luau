--!strict
-- Make and manage your own Team Chat bots (Services/Bots, docs/BOTS.md)

local Bots = require(script.Parent.Parent.Parent.Services.Bots)
local Language = require(script.Parent.Parent.Parent.Core.Language)

local USAGE = "/bot create <name> | list | reload | remove <name> | key <api key|clear>"

return {
	Name = "bot",
	Aliases = { "bots" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Make your own bots and see the bots in this place",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "action", description = "create, list, reload, remove or key" },
		{ name = "name", description = "The bot's name (or your API key)", optional = true },
	},
	Function = function(_speaker, args, ctx)
		local action = string.lower(args[1] or "list")
		local name = args[2]

		if action == "create" then
			if not name or not string.match(name, "^[%w_]+$") then
				ctx.addSystemMessage(Language.t("commands.usage", { usage = "/bot create <name>" }))
				return
			end
			local module, problem = Bots.create(name)
			if not module then
				ctx.addSystemMessage(
					Language.t(if problem == "exists" then "bot.exists" else "bot.signedOut", { name = name })
				)
				return
			end
			if ctx.openScript then
				ctx.openScript(module)
			end
			ctx.addEmbed({
				title = Language.t("bot.created", { name = name }),
				description = Language.t("bot.createdText"),
				color = Color3.fromRGB(88, 101, 242),
				footer = "ServerStorage." .. Bots.SCRIPTS_FOLDER .. "." .. name,
			})
		elseif action == "list" then
			local bots = Bots.list()
			if #bots == 0 then
				ctx.addSystemMessage(Language.t("bot.none"))
				return
			end
			local fields = {}
			for _, bot in ipairs(bots) do
				local commands = {}
				for _, command in ipairs(bot.commands) do
					table.insert(commands, "/" .. tostring(command.name))
				end
				table.insert(fields, {
					name = (if bot.online then "\u{1F7E2} " else "\u{26AA} ") .. bot.name,
					value = Language.t("bot.listEntry", {
						owner = bot.ownerName,
						commands = if #commands > 0 then table.concat(commands, "  ") else "-",
					}),
				})
			end
			ctx.addEmbed({ title = Language.t("bot.listTitle", { count = #bots }), fields = fields })
		elseif action == "reload" then
			local names = Bots.reload()
			ctx.addSystemMessage(
				if #names > 0
					then Language.t("bot.reloaded", { names = table.concat(names, ", ") })
					else Language.t("bot.noneYours")
			)
		elseif action == "remove" and name then
			ctx.addSystemMessage(
				Language.t(if Bots.remove(name) then "bot.removed" else "bot.notYours", { name = name })
			)
		elseif action == "key" and name then
			if string.lower(name) == "clear" then
				Bots.setApiKey(nil)
				ctx.addSystemMessage(Language.t("bot.keyCleared"))
			else
				Bots.setApiKey(name)
				ctx.addSystemMessage(Language.t("bot.keySaved", { ending = string.sub(name, -4) }))
			end
		else
			ctx.addSystemMessage(Language.t("commands.usage", { usage = USAGE }))
		end
	end,
}
