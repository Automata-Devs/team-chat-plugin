# Team database

Team Chat can keep data on **your own server**, reached over HttpService:

- **Chat archive**: every team chat message, kept after `/clear`, `/purge` or
  deleting the place, and searchable with `/database search`.
- **Profiles and stats**: each person's name, when and where they last used
  Team Chat, and how many team chat messages they've sent. These follow them
  across places and computers.
- **Key/value collections**: storage for bots (`ctx.db`) and commands.

Without a server, Team Chat works as before. The chat lives in the place
(`ServerStorage.TeamChatData`) and syncs through Team Create.

## Run the server

`server/` is a small Node.js 18+ server with no dependencies. It keeps
everything in one JSON file.

```bash
cd server
TEAMCHAT_TOKEN="$(node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")" npm start
```

| Variable | Default | |
|---|---|---|
| `TEAMCHAT_TOKEN` | (required) | The team's secret, 16 characters or more |
| `PORT` | `8787` | |
| `DATA_DIR` | `server/data` | Where `teamchat.json` is saved |

Host it anywhere that runs Node and gives you **HTTPS**, such as a VPS behind
Caddy or nginx, Railway, Render or Fly.io. Keep `DATA_DIR` on a persistent
disk and back it up. `npm test` runs the server's tests.

## Connect a place

An admin (rank 2 or higher) runs this once per place:

```text
/database connect https://chat.example.com <token>
```

The URL and token are saved in the place (`TeamChatData.Database`), so
everyone in Team Create uses the same server. The first time Team Chat
contacts the server, Studio asks each person to allow the plugin's HTTP
requests to that domain.

| Command | |
|---|---|
| `/database status` | The server, whether it answers, and what's waiting to be sent |
| `/database connect <url> <token>` | Connect the place (admins) |
| `/database disconnect` | Stop using the server here (admins). Data on the server is kept |
| `/database sync` | Send everything waiting now |
| `/database search <text>` | Search this place's archive |
| `/database profile [user id]` | A profile (yours by default) |

`/db` works too.

## How it behaves

- **Each message is uploaded once**, by the plugin of the person who sent it,
  or of the person who ran the bot command it answers. Uploads go in batches
  every 5 seconds. A message uploaded twice replaces the first copy.
- **Only the team chat is archived.** DMs and group DMs stay in the place,
  between the people in them. Ephemeral bot answers are never archived.
- **Offline**: writes that can't reach the server (archive batches, profile
  updates, `ctx.db` writes) wait in plugin settings on that computer. They're
  sent in order once the server answers again, and are kept if Studio is
  closed (up to 500). Reads fall back to the last answer seen.
- **Disconnecting** forgets what was waiting on that computer.

## Security

- The token gives full read and write access to the team's database. It's
  saved in the place, so **anyone who can edit the place can read it**: the
  same people who can already read the chat in ServerStorage. Use a separate
  server (or token) per team, and change the token if someone leaves.
- Only HTTPS URLs are accepted, except `http://localhost` and
  `http://127.0.0.1` for testing on your own computer.
- The server compares tokens in constant time, checks names (`A-Z a-z 0-9 _ - . :`,
  up to 128 characters) and caps sizes: 1 MB per request, 64 KB per value,
  4000 characters per message.

## For bots

A Studio bot gets its own collection as `ctx.db`:

```lua
local count = (ctx.db:get("uses") or 0) + 1
ctx.db:set("uses", count)
for _, item in ipairs(ctx.db:list("score:")) do
	print(item.key, item.value)
end
```

| Method | Returns |
|---|---|
| `get(key)` | `value, info`. `info.stale` is true when it came from the cache because the server couldn't be reached |
| `set(key, value)` | `ok, problem`. `problem` is `"queued"` when it'll be sent later |
| `delete(key)` | `ok, problem` |
| `list(prefix?)` | `{ { key, value, updatedAt } }, info` |

Plugin code uses the same API: `Database.store("name")`. See
`src/Services/Database/init.luau`.

## HTTP API

All routes are under `/v1` and need the `X-TeamChat-Token` header. Bodies and
answers are JSON, and errors are `{ "error": "..." }`. Times are Unix seconds.

| Route | |
|---|---|
| `GET /health` | `{ ok, time }` |
| `GET /kv/:collection?prefix=&limit=` | `{ items: [{ key, value, updatedAt }] }` |
| `GET /kv/:collection/:key` | `{ key, value, version, updatedAt }`, or 404 |
| `PUT /kv/:collection/:key` | Body `{ value, ifVersion? }`. 409 if `ifVersion` doesn't match |
| `DELETE /kv/:collection/:key` | `{ deleted }` |
| `POST /archive/:place/:conversation` | Body `{ messages: [{ id, sender, senderId, timestamp, content, ... }] }` |
| `GET /archive/:place/:conversation?before=&limit=` | `{ messages }`, oldest first |
| `GET /archive/:place?q=&limit=` | Search: `{ messages }` with `conversation`, newest first |
| `GET /profiles/:userId` | The profile, or 404 |
| `POST /profiles/:userId` | Body `{ set: { username, lastSeen, lastPlace }, increment: { messagesSent } }` |

`:place` is the PlaceId, or `unpublished`.
