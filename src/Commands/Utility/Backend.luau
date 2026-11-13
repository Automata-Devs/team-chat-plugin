--!strict
-- Store everything in the Team Chat backend (Services/Backend, docs/backend)

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local Backend = require(script.Parent.Parent.Parent.Services.Backend)
local Language = require(script.Parent.Parent.Parent.Core.Language)

local USAGE = "/backend status | connect <url> | login | logout | sync | restore | disconnect"
local COLOR = Color3.fromRGB(88, 101, 242)

local function t(key: string, default: string, vars: { [string]: any }?): string
	return Language.tOr("backend." .. key, default, vars)
end

local function problemText(problem: string?): string
	if problem == "notConnected" then
		return t(
			"notConnected",
			"This place isn't stored on a backend: none is set up in Team Chat, or the place was disconnected. An admin can use /backend connect <url>."
		)
	elseif problem == "signedOut" then
		return t("signedOut", "You're not signed in to the backend. Use /backend login.")
	elseif problem == "noWorkspace" then
		return t("noWorkspace", "This place's workspace isn't ready yet. It's made by itself once you're signed in.")
	elseif problem == "alreadySigningIn" then
		return t(
			"alreadySigningIn",
			"A sign-in is already waiting: open the link in the Output window (View > Output)."
		)
	elseif problem == "wrongAccount" then
		return t("wrongAccount", "That Roblox account isn't the one signed in to Studio, so it was signed out again.")
	elseif problem == "timedOut" then
		return t("timedOut", "The sign-in wasn't finished in time. Try /backend login again.")
	elseif problem == "unreachable" then
		return t(
			"unreachable",
			"The backend didn't answer. Check its URL, that it's running, and that Studio may reach it."
		)
	end
	return t("error", "The backend answered: {problem}", { problem = tostring(problem) })
end

return {
	Name = "backend",
	Aliases = {},
	Prefixes = { "/" },
	Enabled = true,
	Rank = 0,
	RankLock = false,
	Loopable = false,
	Tags = { "Utility" },
	Description = "Store everything you write on the Team Chat backend, under your own account",
	Contributors = { "D3veloperHac" },
	Args = {
		{ name = "action", description = "status, connect, login, logout, sync, restore or disconnect" },
		{ name = "url", description = "The backend's URL (for connect)", optional = true },
	},
	Function = function(speaker, args, ctx)
		local action = string.lower(args[1] or "status")
		local isAdmin = (speaker.rank or 0) >= BackendConfig.MANAGE_RANK

		if action == "status" then
			local status = Backend.status()
			if not status.connected then
				ctx.addSystemMessage(problemText("notConnected"))
				return
			end
			ctx.addEmbed({
				title = t("statusTitle", "Team Chat backend"),
				color = COLOR,
				fields = {
					{ name = t("server", "Server"), value = status.url or "-" },
					{
						name = t("you", "You"),
						value = if status.signedIn
							then "@" .. tostring(status.username)
							else t("notSignedIn", "Not signed in"),
						inline = true,
					},
					{
						name = t("place", "This place"),
						value = if status.workspace then t("ready", "Set up") else t("notSetUp", "Not set up yet"),
						inline = true,
					},
					{ name = t("waiting", "Waiting to be stored"), value = tostring(status.waiting), inline = true },
				},
			})
		elseif action == "connect" then
			if not isAdmin then
				ctx.addSystemMessage(t("adminOnly", "Only admins can connect or disconnect the backend."))
				return
			end
			local url = args[2]
			if not url or url == "" then
				ctx.addSystemMessage(Language.t("commands.usage", { usage = "/backend connect <url>" }))
				return
			end
			if not Backend.connect(url) then
				ctx.addSystemMessage(t("badUrl", "The URL must start with https:// (or http://localhost for testing)."))
				return
			end
			ctx.addSystemMessage(
				t(
					"connected",
					"This place now uses that server. Everyone's chat here is stored there once they're signed in."
				)
			)
		elseif action == "login" then
			ctx.addSystemMessage(t("loginStarting", "Starting the Roblox sign-in..."))
			task.spawn(function()
				local ok, problem = Backend.signIn(function(url, code, linkUrl)
					-- Plugins can't open a browser or copy: a short address and code to type, and the link in Output
					local chatText, outputText = Backend.signInText(url, code, linkUrl)
					print(outputText)
					ctx.addSystemMessage(chatText)
				end)
				if ok then
					ctx.addSystemMessage(
						t(
							"signedIn",
							"Signed in. Everything you write here is now stored on the backend, including what you wrote before."
						)
					)
				else
					ctx.addSystemMessage(problemText(problem))
				end
			end)
		elseif action == "logout" then
			Backend.signOut()
			ctx.addSystemMessage(
				t("loggedOut", "Signed out on this computer. What you write isn't stored until you sign in again.")
			)
		elseif action == "sync" then
			local sent, problem = Backend.sync()
			if problem then
				ctx.addSystemMessage(problemText(problem))
			else
				ctx.addSystemMessage(t("synced", "Stored {count} waiting items.", { count = sent }))
			end
		elseif action == "restore" then
			if not isAdmin then
				ctx.addSystemMessage(t("adminOnlyRestore", "Only admins can restore the team chat."))
				return
			end
			local count, problem = Backend.restore()
			if count == nil then
				ctx.addSystemMessage(problemText(problem))
			else
				ctx.addSystemMessage(t("restored", "Restored {count} messages from the backend.", { count = count }))
			end
		elseif action == "disconnect" then
			if not isAdmin then
				ctx.addSystemMessage(t("adminOnly", "Only admins can connect or disconnect the backend."))
				return
			end
			Backend.disconnect()
			ctx.addSystemMessage(
				t(
					"disconnected",
					"This place isn't stored any more. What's stored stays on the backend; /backend connect turns it back on."
				)
			)
		else
			ctx.addSystemMessage(Language.t("commands.usage", { usage = USAGE }))
		end
	end,
}
