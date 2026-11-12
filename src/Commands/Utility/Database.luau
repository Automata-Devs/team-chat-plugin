--!strict
-- Connect the place to the team database and use it (Services/Database, docs/DATABASE.md)

local DatabaseConfig = require(script.Parent.Parent.Parent.Config.Database)
local Database = require(script.Parent.Parent.Parent.Services.Database)
local Identity = require(script.Parent.Parent.Parent.Core.Identity)
local Language = require(script.Parent.Parent.Parent.Core.Language)

local USAGE = "/database status | connect <url> <token> | disconnect | sync | search <text> | profile [user id]"
local COLOR = Color3.fromRGB(88, 101, 242)

local function t(key: string, default: string, vars: { [string]: any }?): string
	return Language.tOr("database." .. key, default, vars)
end

local function problemText(problem: string?): string
	if problem == "notConnected" then
		return t(
			"notConnected",
			"This place isn't connected to a database. An admin can use /database connect <url> <token>."
		)
	elseif problem == "unreachable" then
		return t(
			"unreachable",
			"The database server didn't answer. Check its URL, that it's running, and that Studio may reach it."
		)
	end
	return t("error", "The database answered: {problem}", { problem = tostring(problem) })
end

local function when(seconds: any): string
	return if type(seconds) == "number" then os.date("%d/%m/%Y %H:%M", seconds) :: string else "-"
end

return {
	Name = "database",
	Aliases = { "db" },
	Prefixes = { "/" },
	Enabled = true, -- If the command is enabled
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "The team database: chat archive, profiles and bot storage on your own server",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "action", description = "status, connect, disconnect, sync, search or profile" },
		{ name = "value", description = "The server URL, search text or user id", optional = true },
		{ name = "token", description = "The server's token (for connect)", optional = true },
	},
	Function = function(speaker, args, ctx)
		local action = string.lower(args[1] or "status")
		local canManage = (speaker.rank or 0) >= DatabaseConfig.MANAGE_RANK

		if action == "status" then
			local status = Database.status()
			if not status.connected then
				ctx.addSystemMessage(problemText("notConnected"))
				return
			end
			local online = Database.ping()
			ctx.addEmbed({
				title = t("statusTitle", "Team database"),
				color = COLOR,
				fields = {
					{ name = t("server", "Server"), value = status.url or "-" },
					{
						name = t("state", "State"),
						value = if online then t("online", "Online") else t("offline", "Can't be reached"),
						inline = true,
					},
					{
						name = t("waiting", "Waiting to send"),
						value = tostring(status.queued + status.pending),
						inline = true,
					},
				},
			})
		elseif action == "connect" then
			if not canManage then
				ctx.addSystemMessage(t("adminOnly", "Only admins can connect or disconnect the database."))
				return
			end
			local url, token = args[2], args[3]
			if not url or not token then
				ctx.addSystemMessage(Language.t("commands.usage", { usage = "/database connect <url> <token>" }))
				return
			end
			local ok, problem = Database.connect(url, token)
			if not ok then
				ctx.addSystemMessage(t("badUrl", "The URL must start with https:// (or http://localhost for testing)."))
			elseif problem then
				ctx.addSystemMessage(t("connectedOffline", "Saved, but the server didn't answer yet: {problem}", {
					problem = problemText(problem),
				}))
			else
				ctx.addSystemMessage(
					t("connected", "Connected to {url}. The team chat is archived from now on.", { url = url })
				)
			end
		elseif action == "disconnect" then
			if not canManage then
				ctx.addSystemMessage(t("adminOnly", "Only admins can connect or disconnect the database."))
				return
			end
			Database.disconnect()
			ctx.addSystemMessage(t("disconnected", "Disconnected. Nothing is sent to the database any more."))
		elseif action == "sync" then
			local sent, problem = Database.sync(true)
			ctx.addSystemMessage(
				if problem then problemText(problem) else t("synced", "Sent {count} waiting items.", { count = sent })
			)
		elseif action == "search" then
			local text = table.concat(args, " ", 2)
			if text == "" then
				ctx.addSystemMessage(Language.t("commands.usage", { usage = "/database search <text>" }))
				return
			end
			local messages, problem = Database.archive.search(text)
			if not messages then
				ctx.addSystemMessage(problemText(problem))
				return
			end
			if #messages == 0 then
				ctx.addSystemMessage(t("noResults", 'Nothing in the archive matches "{text}".', { text = text }))
				return
			end
			local fields = {}
			for _, message in ipairs(messages) do
				table.insert(fields, {
					name = string.format("%s · %s", tostring(message.sender), when(message.timestamp)),
					value = string.sub(tostring(message.content), 1, 200),
				})
			end
			ctx.addEmbed({
				title = t("resultsTitle", 'Archive: "{text}"', { text = text }),
				color = COLOR,
				fields = fields,
			})
		elseif action == "profile" then
			local userId = tonumber(args[2]) or Identity.userId
			local profile, problem = Database.profiles.get(userId)
			if not profile then
				ctx.addSystemMessage(
					if problem then problemText(problem) else t("noProfile", "No profile for that user yet.")
				)
				return
			end
			local stats = if type(profile.stats) == "table" then profile.stats else {}
			ctx.addEmbed({
				title = tostring(profile.username or userId),
				thumbnailUserId = userId,
				color = COLOR,
				footer = if problem
					then t("stale", "The server can't be reached: this is the last copy seen.")
					else nil,
				fields = {
					{
						name = t("messagesSent", "Messages sent"),
						value = tostring(stats.messagesSent or 0),
						inline = true,
					},
					{ name = t("firstSeen", "First seen"), value = when(profile.firstSeen), inline = true },
					{ name = t("lastSeen", "Last seen"), value = when(profile.lastSeen), inline = true },
					{
						name = t("lastPlace", "Last place"),
						value = if type(profile.lastPlace) == "table" then tostring(profile.lastPlace.name) else "-",
					},
				},
			})
		else
			ctx.addSystemMessage(Language.t("commands.usage", { usage = USAGE }))
		end
	end,
}
