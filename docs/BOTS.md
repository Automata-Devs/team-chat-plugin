# Team Chat bots

Make your own bots for Team Chat, like on Discord: slash commands with typed
options, answers with cards and buttons, answers only the user can see, and
"*bot* is thinking…" for answers that take a while.

There are two kinds of bot:

| | Studio bot | Web bot |
|---|---|---|
| Runs | As a ModuleScript in **your** Studio | On **your own server** (any language) |
| Online | While you're in the place | Always (while your server is up) |
| Make one | Settings > Developer, or `/bot create <name>` | Settings > Developer |

## The developer portal

**Settings > Developer** has three tabs:

- **Your bots**: your bots with their status, commands, uses and errors.
  **Manage** opens a bot's page:
  - **Overview**: a health check (is it answering, and how fast), its
    commands, and its actions: open a Studio bot's script, reload it, turn it
    off and on, delete it. For a web bot you also set its URL, see or replace
    its token, and sync its commands.
  - **Test console**: run a command (`/hello Ana`) or click its buttons. The
    answer shows only in the console; nothing is posted in the chat. A Studio
    bot must be running (Reload it first); a web bot gets `"test": true`.
  - **Logs & stats**: its last 40 interactions (who, how long, and the error
    when one failed), how often it's used, its average answer time and its
    most used commands. Tests show in the log but don't count as use.
  - **Edit**: the name, description and avatar Team Chat shows for it (over
    what its script or server says), and each command turned on or off with
    its own description.
- **New bot**: make a Studio or web bot.
- **Docs**: a quick start, what Team Chat sends and expects back, and starter
  servers for Node.js and Python.

Admins and up can turn anyone's bot off or on from **Settings > Admin**.

## How bots work

- Bots live in the place: Studio bot scripts in `ServerStorage.TeamChatBots`,
  and every bot's name, avatar and commands (plain data, not code) in
  `TeamChatData.Bots`. Everyone's chat shows those commands in autocomplete and
  in `/help`.
- **A Studio bot runs only in its owner's Studio.** Other people's code never
  runs on your computer, and yours never runs on theirs. When someone uses its
  command, their plugin leaves a request in the place, and your plugin runs it.
  If you're not in the place, people are told the bot is offline.
- **A web bot runs on your server.** When someone uses its command, *their*
  plugin sends it to your URL and shows what your server answers.
- Answers show under "*name* used /command", for everyone, or only for the
  person who used it (ephemeral).
- Built-in commands always win: a bot command with the same name as one is
  ignored.

## Commands

| Command | What it does |
|---|---|
| `/bot create <name>` | Make a Studio bot from the template (letters, numbers, `_`) |
| `/bot list` | The bots in this place, their owners, commands and whether they're online |
| `/bot reload` | Restart your Studio bots after editing them |
| `/bot remove <name>` | Remove one of your bots |
| `/bot key <api key>` | Save your Open Cloud API key **on this computer only** |
| `/bot key clear` | Remove the saved API key |

## Commands and options

A command has typed **options**, like Discord's slash command options. Team
Chat checks what's typed before your bot sees it, and shows the choices in
autocomplete.

```lua
bot.commands.roll = {
	description = "Roll some dice",
	options = {
		{ name = "dice", description = "How many", type = "integer", required = true },
		{ name = "sides", type = "integer", choices = { 6, 12, 20 }, required = false },
	},
	run = function(ctx)
		ctx.reply("You rolled " .. ctx.options.dice .. "d" .. (ctx.options.sides or 6))
	end,
}
```

| `type` | The value your bot gets |
|---|---|
| `string` (the default) | Text. The last string option takes the rest of the line. |
| `integer`, `number` | A number |
| `boolean` | `true` or `false` (`yes`/`no`, `true`/`false`, `on`/`off`) |
| `user` | `{ id, name }` of a Roblox user (by name, or `@name`) |

`choices` limits an option to a list: plain values, or `{ name, value }`
pairs. Options are required unless `required = false`. The older
`args = { { name, description, optional } }` still works (as string options).

## Messages

A bot sends text, a card, or a message table:

```lua
ctx.reply({
	content = "Here are today's stats",
	embed = {
		title = "Build stats",
		description = "Today",
		color = Color3.fromRGB(88, 101, 242), -- a web bot sends "#5865F2"
		thumbnailUserId = ctx.user.id,
		fields = {
			{ name = "Parts", value = "1,204", inline = true },
			{ name = "Scripts", value = "37", inline = true },
		},
		footer = "Updated just now",
	},
	components = {
		{ label = "Refresh", style = "primary", customId = "refresh" },
		{ label = "Docs", style = "link", url = "https://create.roblox.com/docs" },
	},
	ephemeral = false,
})
```

- **Text** supports the chat's markdown, @mentions and #tags.
- **`components`** are buttons under the message: a list of buttons, or a list
  of rows (lists) of buttons, at most 5 rows of 5. A button is
  `{ label, style, customId, url, disabled }`. `style` is `primary`,
  `secondary`, `success`, `danger` or `link`. Link buttons open their `url`;
  the others send their `customId` to your bot.
- **`ephemeral = true`**: only the person who used the command sees the answer,
  with "Only you can see this" and a Dismiss button.

## Studio bots

```lua
local bot = {
	name = "Weather",                 -- shown as the sender
	description = "Weather for builders",
	avatar = "rbxassetid://1234567",  -- optional picture (a Roblox image)
	commands = {},
}

bot.commands.forecast = {
	description = "The forecast for a city",
	options = { { name = "city", description = "Which city", type = "string" } },
	run = function(ctx)
		ctx.defer() -- "Weather is thinking…" while it looks it up
		local response = ctx.http({ Url = "https://example.com/weather?city=" .. ctx.options.city })
		ctx.reply({
			content = if response then response.Body else "Couldn't look that up.",
			components = { { label = "Again", customId = "again" } },
		})
	end,
}

-- Optional: a button under one of the bot's messages was clicked
function bot.onButton(ctx, customId)
	if customId == "again" then
		ctx.update("Updated just now") -- changes the message the button is on
	end
end

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

Command and option names are lowercase letters, numbers and `_`. After
editing, run **`/bot reload`** (or Reload in the portal).

### `ctx`

| Field / function | What it is |
|---|---|
| `ctx.user` | Who used the command or clicked the button: `{ id, name }` |
| `ctx.command` | The command's name |
| `ctx.options` | The options' values, by name |
| `ctx.args` / `ctx.text` | The words after the command, as a list and as one string |
| `ctx.customId` | The clicked button's `customId` (in `onButton`) |
| `ctx.message` | The message the clicked button is on (in `onButton`) |
| `ctx.reply(message)` | Answer, under "*name* used /command" |
| `ctx.defer({ ephemeral? })` | Show "*bot* is thinking…" now; the next `ctx.reply` replaces it |
| `ctx.update(message)` | After a button click: change the message the button is on |
| `ctx.send(message)` | Post a message of the bot's own (not an answer) |
| `ctx.http(options)` | A web request (`HttpService:RequestAsync` options); returns the response, or `nil, error` |
| `ctx.openCloud(method, path, body?)` | A Roblox Open Cloud request with your API key; returns the decoded JSON, or `nil, error` |
| `ctx.json.encode(value)` / `ctx.json.decode(text)` | JSON helpers |

## Web bots

A web bot is an HTTPS endpoint. Make one in **Settings > Developer > New bot >
Web** with its URL; Team Chat makes a token for it. Then:

1. Check every request's `X-TeamChat-Token` header against your token, and
   answer `401` when it's wrong.
2. Answer `ping` with your bot's commands, and click **Sync commands**.

Every request is a `POST` with a JSON body, and every answer is JSON.

### `ping`: your bot's commands

```json
{ "type": "ping", "bot": { "id": "…" } }
```

```json
{
  "type": "pong",
  "name": "Weather",
  "description": "Weather for builders",
  "avatar": "rbxassetid://1234567",
  "commands": [
    {
      "name": "forecast",
      "description": "The forecast for a city",
      "options": [{ "name": "city", "type": "string", "required": true }]
    }
  ]
}
```

### `command` and `button`

```json
{
  "type": "command",
  "id": "8F1C…",
  "test": false,
  "bot": { "id": "…" },
  "user": { "id": 156, "name": "builderman" },
  "place": { "id": 1818 },
  "conversation": "main",
  "command": "forecast",
  "options": { "city": "Amsterdam" },
  "args": ["Amsterdam"]
}
```

A button click is the same with `"type": "button"`, `"customId"`, and
`"message": { "id", "content" }` (the message the button is on) instead of
`command`, `options` and `args`.

`"test": true` means it comes from the portal's test console: answer as usual
(nothing is posted), but don't do anything you only want for real use, like
saving to a database.

### Answers

| `type` | What happens |
|---|---|
| `message` (the default) | Post the answer: `content`, `embed`, `components`, `ephemeral` as in [Messages](#messages) |
| `update` | After a button click: change the message the button is on |
| `deferred` | Show "*bot* is thinking…" (add `"ephemeral": true` to show it only to the user). Team Chat then asks for the answer |
| `none` | Show nothing |

After a `deferred` answer, Team Chat sends `{ "type": "followup", "id": "<the
interaction's id>" }` every 2 seconds, for up to 60 seconds. Answer it with
`{ "type": "none" }` until your answer is ready, then with the message.

### Keep the token safe

- The token is stored in the place, so **everyone who can edit the place can
  see it**. It keeps the rest of the internet out of your endpoint, not the
  place's collaborators. Use a token for one bot and one place only, and click
  **New token** when someone leaves the team.
- Requests come from the Studio of the person who used the command (Studio
  asks them once to allow your site). Treat what they send like any user
  input.
- Use HTTPS. Team Chat only sends to `http://` on this computer
  (`http://localhost` or `http://127.0.0.1`), for testing.

## Roblox Open Cloud

[Open Cloud](https://create.roblox.com/docs/cloud) lets Studio bots use
Roblox's APIs: data stores, memory stores, user info, notifications, assets and
more ([all endpoints](https://create.roblox.com/docs/cloud/reference/domains/apis)).
Web bots can call Open Cloud from their server with their own key.

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
	options = { { name = "user", description = "Who", type = "user" } },
	run = function(ctx)
		local id = ctx.options.user.id
		local user, err = ctx.openCloud("GET", "/cloud/v2/users/" .. id)
		if not user then
			ctx.reply({ content = "Couldn't look that up: " .. err, ephemeral = true })
			return
		end
		ctx.reply({ title = user.displayName, description = "@" .. user.name, thumbnailUserId = id })
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
- Tell people what your bot does with what they type, especially a web bot,
  which sends it to your server (see [PRIVACY.md](../PRIVACY.md)).
- Bots you make are yours; the Team Chat plugin itself stays under
  [LICENSE.md](../LICENSE.md).
