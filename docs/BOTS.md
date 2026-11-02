# Team Chat bots

Make your own bots for Team Chat: commands that anyone in the place can use,
and bots that react to messages. A bot is a ModuleScript written in Luau.

## How bots work

- A bot lives in `ServerStorage.TeamChatBots` in the place. Make one with
  **`/bot create <name>`**: Team Chat creates the script from a template and
  opens it.
- **A bot runs only in its owner's Studio** (whoever made it). Other people's
  code never runs on your computer, and yours never runs on theirs.
- Your plugin publishes your bot's name, avatar and commands (plain data, not
  code) to the place. Everyone's chat shows those commands in autocomplete and
  in `/help`.
- When someone uses your bot's command, their plugin leaves a request in the
  place; **your** plugin runs the command and the bot posts its answer for
  everyone, under "*name* used /command".
- If you're not in the place, your bot is offline: people who use its commands
  are told so.
- Built-in commands always win: a bot command with the same name as one is
  ignored.

## Commands

| Command | What it does |
|---|---|
| `/bot create <name>` | Make a bot from the template (letters, numbers, `_`) |
| `/bot list` | The bots in this place, their owners, commands and whether they're online |
| `/bot reload` | Restart your bots after editing them |
| `/bot remove <name>` | Remove one of your bots |
| `/bot key <api key>` | Save your Open Cloud API key **on this computer only** |
| `/bot key clear` | Remove the saved API key |

## A bot script

```lua
local bot = {
	name = "Weather",                 -- shown as the sender
	description = "Weather for builders",
	avatar = "rbxassetid://1234567",  -- optional picture (a Roblox image)
	commands = {},
}

-- /forecast <city>
bot.commands.forecast = {
	description = "The forecast for a city",
	args = { { name = "city", description = "Which city" } },
	run = function(ctx)
		ctx.reply("Sunny in " .. ctx.text .. "!")
	end,
}

-- Optional: every new message in the team chat
function bot.onMessage(ctx, message)
	if message.text == "ping" then
		ctx.send("pong")
	end
end

-- Optional: when the bot starts (when you open the place, or /bot reload)
function bot.onStart(ctx) end

return bot
```

Command names are lowercase letters, numbers and `_`. After editing, run
**`/bot reload`**.

## `ctx`

| Field / function | What it is |
|---|---|
| `ctx.user` | Who used the command: `{ id, name }` (commands only) |
| `ctx.args` | The words after the command, e.g. `{ "Amsterdam" }` |
| `ctx.text` | The same, as one string |
| `ctx.command` | The command's name |
| `ctx.reply(text or card)` | Answer, shown under "*name* used /command" |
| `ctx.send(text or card)` | Post a message of the bot's own |
| `ctx.http(options)` | A web request (`HttpService:RequestAsync` options); returns the response, or `nil, error` |
| `ctx.openCloud(method, path, body?)` | A Roblox Open Cloud request with your API key; returns the decoded JSON, or `nil, error` |
| `ctx.json.encode(value)` / `ctx.json.decode(text)` | JSON helpers |

Messages support the chat's markdown, @mentions and #tags. A **card** is the
same as for built-in commands:

```lua
ctx.reply({
	title = "Build stats",
	description = "Today",
	color = Color3.fromRGB(88, 101, 242),   -- the edge
	thumbnailUserId = ctx.user.id,           -- an avatar on the right
	fields = {
		{ name = "Parts", value = "1,204", inline = true },
		{ name = "Scripts", value = "37", inline = true },
	},
	footer = "Updated just now",
})
```

## Roblox Open Cloud

[Open Cloud](https://create.roblox.com/docs/cloud) lets bots use Roblox's
APIs: data stores, memory stores, user info, notifications, assets and more
([all endpoints](https://create.roblox.com/docs/cloud/reference/domains/apis)).

1. Create an API key on the [Creator Dashboard](https://create.roblox.com/dashboard/credentials)
   with only the permissions your bot needs.
2. Save it with **`/bot key <your key>`**. It's stored in your plugin settings on
   this computer, never in the place (everyone who can edit the place could read
   it there). Type it as a command: anything without the `/` is sent as a chat
   message.
3. Call it from your bot:

```lua
bot.commands.whois = {
	description = "Look up a Roblox user",
	args = { { name = "userId", description = "Their user ID" } },
	run = function(ctx)
		local user, err = ctx.openCloud("GET", "/cloud/v2/users/" .. ctx.args[1])
		if not user then
			ctx.reply("Couldn't look that up: " .. err)
			return
		end
		ctx.reply({ title = user.displayName, description = "@" .. user.name, thumbnailUserId = tonumber(ctx.args[1]) })
	end,
}

-- Keep a counter in a data store of your experience (check each endpoint's
-- page for its exact request body)
bot.commands.visits = {
	description = "Count a visit",
	run = function(ctx)
		local path = "/cloud/v2/universes/<universe id>/data-stores/Stats/entries/visits:increment"
		local result, err = ctx.openCloud("POST", path, { amount = 1 })
		ctx.reply(if result then "Visits: " .. tostring(result.value) else "Error: " .. err)
	end,
}
```

Studio asks the first time a plugin makes web requests to a site; allow it for
`apis.roblox.com` (and any other site your bot uses).

Roblox has no API for its own chat, friends list or presence, so bots can't
message people outside Team Chat.

## Rules

- Follow the [Roblox Terms of Use](https://en.help.roblox.com/hc/articles/115004647846)
  and Community Standards, and Team Chat's [Terms](../TERMS.md).
- Don't put API keys, passwords or other secrets in a bot script: everyone who
  can edit the place can read it. Use `/bot key`.
- Tell people what your bot does with what they type, especially if it sends
  anything to a website (see [PRIVACY.md](../PRIVACY.md)).
- Bots you make are yours; the Team Chat plugin itself stays under
  [LICENSE.md](../LICENSE.md).
