# Team database

Team Chat can keep data in **MongoDB** (or a JSON file), through a small server
reached over HttpService:

- **Chat archive**: every team chat message, kept after `/clear`, `/purge` or
  deleting the place, and searchable with `/database search`.
- **Profiles and stats**: each person's name, when and where they last used
  Team Chat, and how many team chat messages they've sent. These follow them
  across places and computers.
- **Key/value collections**: storage for bots (`ctx.db`) and commands.

Without a server, Team Chat works as before. The chat lives in the place
(`ServerStorage.TeamChatData`) and syncs through Team Create.

## How it fits together

Roblox can only make HTTP requests, and MongoDB doesn't accept them, so a small
server sits in between:

```text
Team Chat (Studio)  --HTTPS + token-->  server/  ---->  MongoDB Atlas
```

`server/` is a small Node.js 18+ app. It keeps the data in **MongoDB** when
`MONGODB_URI` is set, and otherwise in one JSON file on its own disk.

## Set up MongoDB Atlas

MongoDB Atlas hosts the database for you, with a free tier.

1. Create a free cluster on [mongodb.com/atlas](https://www.mongodb.com/atlas).
2. Under **Database Access**, add a database user with a password.
3. Under **Network Access**, allow the address of the server from the next
   step (or `0.0.0.0/0` if your host doesn't have a fixed address).
4. Under **Connect > Drivers**, copy the connection string
   (`mongodb+srv://user:password@cluster0.xxxxx.mongodb.net/`).

The server creates its collections (`kv`, `archive`, `profiles`) and indexes
on its own.

## Run the server

```bash
cd server
npm install
TEAMCHAT_TOKEN="$(node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")" MONGODB_URI="mongodb+srv://..." npm start
```

| Variable | Default | |
|---|---|---|
| `TEAMCHAT_TOKEN` | (required) | The team's secret, 16 characters or more |
| `MONGODB_URI` | | MongoDB connection string. Without it the data goes in a JSON file |
| `MONGODB_DB` | `teamchat` | The database to use |
| `PORT` | `8787` | |
| `DATA_DIR` | `server/data` | Where `teamchat.json` is saved when there's no `MONGODB_URI` |

Host it anywhere that runs Node and gives you **HTTPS**. With MongoDB the
server keeps nothing on its own disk, so free hosts work well:

- **Render**: `render.yaml` in this repository sets it up. Create a Blueprint
  from your fork, then fill in `MONGODB_URI` (the token is generated for you,
  under Environment). Free services sleep when idle, so the first request
  after a while takes a few seconds; Team Chat retries on its own.
- Railway, Fly.io, or a VPS behind Caddy or nginx: run `npm start` in
  `server/` with the variables above.

`npm test` runs the server's tests. Set `MONGODB_TEST_URI` to also run them
against MongoDB (they use and then drop a throwaway database).

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
- The MongoDB connection string (with its password) stays on the server.
  Team Chat only ever sees the server's URL and token.
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
