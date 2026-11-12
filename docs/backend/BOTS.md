# Bots on the backend

A bot is an account (`users.is_bot`) owned by a person. It acts through the
REST API with its own token, joins a workspace when someone installs it, and
gets the workspace's events as signed HTTPS POSTs.

## Make one

```http
POST /api/v1/bots
Authorization: Bearer <your session>

{ "username": "weather", "description": "Forecasts for builders",
  "eventsUrl": "https://weather.example.com/teamchat",
  "events": ["message.create"], "permissions": "7" }
```

The answer holds `token` and `signingSecret` **once**. The server keeps
only the token's SHA-256 hash and the secret encrypted with `ENCRYPTION_KEY`.

| | |
|---|---|
| `GET /bots`, `GET`/`PATCH`/`DELETE /bots/:id` | Your bots. `PATCH { status: "disabled" }` stops its token at once |
| `POST /bots/:id/token` | A new token; the old one stops working at once |
| `POST /bots/:id/signing-secret` | A new signing secret |

`isPublic: true` lets other people install it; otherwise only you can.

## Install it

```http
POST /api/v1/workspaces/:workspaceId/bots
{ "botId": "…", "permissions": "7" }
```

This needs `MANAGE_BOTS`. The bot joins with a **managed role** holding
`permissions` (default: what the bot asks for). Nobody can give it more
than they have themselves, and only the owner can grant `ADMINISTRATOR`.
Channel overwrites apply to that role like to any other, so a bot only sees
the channels its role can. Removing it (`DELETE /workspaces/:id/bots/:botId`)
removes the role, its membership and its workspace commands.

## Call the API

```http
Authorization: Bot <token>
```

Bots can read and send messages, edit and delete their own, react, upload
files, list channels, members and roles, and stream `/gateway`. They can't
use person-only routes: settings, sign-in, making workspaces, account changes.
They're rate limited at 600 requests a minute, plus the per-route limits.
Only bots can send `components` (buttons).

## Events

Subscribe with `events`: `message.create`, `message.update`,
`message.delete`, `reaction.add`, `member.add`. Commands
(`interaction.create`) always arrive when the bot has an `eventsUrl`.

Each event is a `POST` to `eventsUrl`:

```http
POST /teamchat
Content-Type: application/json
X-TeamChat-Timestamp: 1794509642
X-TeamChat-Signature: 5d41402abc4b2a76b9719d911017c592…

{ "id": "…", "type": "message.create", "workspaceId": "…", "channelId": "…",
  "data": { "message": { … } }, "sentAt": "…" }
```

**Check every request:** the signature is the hex HMAC-SHA256 of
`"<timestamp>.<raw body>"` with your signing secret. Refuse ones with a wrong
signature or a timestamp over 5 minutes old.

```js
import { createHmac, timingSafeEqual } from "node:crypto";

function verify(secret, timestamp, body, signature) {
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;
  const expected = createHmac("sha256", secret).update(`${timestamp}.${body}`).digest();
  const given = Buffer.from(signature, "hex");
  return given.length === expected.length && timingSafeEqual(given, expected);
}
```

Answer `2xx` within 10 seconds. Anything else is retried with backoff (5
attempts over about 2.5 minutes, for commands 2). A bot only gets events from
channels it can read, never its own messages, and nothing while disabled.

`eventsUrl` must be `https://` on a public address. Private, loopback and
link-local addresses are refused when it's saved and again before every
delivery, and redirects aren't followed.

## Commands

Register them with the bot's own token (or as its owner):

```http
PUT /api/v1/bots/:botId/commands
[{ "name": "forecast", "description": "The weather",
   "options": [{ "name": "city", "type": "string", "required": true }] }]
```

This replaces the bot's global commands. `PUT
/bots/:botId/workspaces/:workspaceId/commands` sets commands for one
workspace. Members list a workspace's commands with
`GET /workspaces/:id/commands`.

When someone runs one (`POST /channels/:id/interactions { botId, command,
options }`, needing `USE_COMMANDS`), the bot gets:

```json
{ "type": "interaction.create",
  "data": { "id": "379…", "channelId": "…", "workspaceId": "…",
            "user": { "id": "…", "username": "ana" },
            "command": "forecast", "options": { "city": "Amsterdam" } } }
```

and answers with a normal message carrying the interaction id within 15 minutes:

```http
POST /api/v1/channels/:channelId/messages
Authorization: Bot <token>

{ "content": "Sunny, 21°C", "interactionId": "379…" }
```

That message has `type: "command"` and `metadata.interaction` (who ran
what). An interaction can be answered once, by its own bot, in its own channel.
