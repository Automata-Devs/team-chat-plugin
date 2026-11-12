# API

All endpoints are under `/api/v1` (health checks: `/health/*`). Bodies and
answers are JSON. Times are ISO 8601. **IDs are strings.**

## Authentication

| Header | Who |
|---|---|
| `Authorization: Bearer <session token>` | A person, after signing in |
| `Authorization: Bot <bot token>` | A bot ([BOTS.md](BOTS.md)) |

Routes marked **bot** below also accept bot tokens; the rest are for people
only (a bot gets 403). Routes marked **public** need no token.

### Sign in with Roblox (from the plugin)

1. `POST /auth/roblox/start` → `{ loginId, pollSecret, url, expiresIn }`
2. Show `url`; the person opens it in a browser and approves on roblox.com.
3. `POST /auth/roblox/poll { loginId, pollSecret }` every 2 seconds: `202`
   while waiting, then `200 { status: "done", token, user, expiresAt }`
   (or `{ status: "failed", error }`). The result is handed out once.

Calling `start` while signed in links the Roblox account to the current user instead.

## Errors

```json
{ "error": { "code": "forbidden", "message": "You don't have permission to do that", "details": … } }
```

| Status | `code` | When |
|---|---|---|
| 400 | `bad_request` | Invalid body or query (`details` lists the fields). Unknown fields are refused |
| 401 | `unauthorized` | No token, or an expired or revoked one |
| 403 | `forbidden` | Signed in, but not allowed |
| 404 | `not_found` | Doesn't exist **or you can't see it** |
| 409 | `conflict` | Already exists (a username, an installed bot) |
| 410 | `expired` | Used-up invite, expired sign-in |
| 413 | `too_large` | File over `MAX_UPLOAD_BYTES`, body over 256 KB |
| 429 | `rate_limited`, `slowmode` | Wait `Retry-After` seconds |
| 503 | `unavailable` | Database unreachable, or a feature not configured. Retry later |

## Rate limits

Counted per person or bot (per IP when signed out), in fixed windows. Every
answer has `X-RateLimit-Limit`, `-Remaining`, `-Reset-After` and `-Bucket`.

| Bucket | Limit |
|---|---|
| Everything, per person | 300 / minute |
| Everything, per bot | 600 / minute |
| Signed out, per IP | 120 / minute |
| Sign-in and password | 10 / minute |
| Sign-up | 5 / hour |
| Sending messages | 10 / 10 seconds |
| Message batches | 30 / minute |
| Uploads | 20 / minute |
| Search | 30 / minute |
| Bot token and secret resets | 20 / 5 minutes |

Channels can also have slowmode (seconds between messages per member).

## Permissions

Bits in a string (`"1035"`), like Discord's:

| Bit | Name | |
|---|---|---|
| 0 | `VIEW_CHANNEL` | See the channel at all |
| 1 | `SEND_MESSAGES` | |
| 2 | `READ_MESSAGE_HISTORY` | |
| 3 | `ADD_REACTIONS` | Start new reactions (joining one only needs to read) |
| 4 | `ATTACH_FILES` | |
| 5 | `EMBED_LINKS` | Send embeds |
| 6 | `MENTION_EVERYONE` | `@everyone` / `@here` notify |
| 7 | `MANAGE_MESSAGES` | Delete others' messages, pin, clear reactions, skip slowmode |
| 8 | `MANAGE_CHANNELS` | |
| 9 | `MANAGE_ROLES` | Roles below your own, and channel overwrites |
| 10 | `MANAGE_WORKSPACE` | |
| 11 | `KICK_MEMBERS` | Members below your highest role |
| 12 | `CREATE_INVITE` | |
| 13 | `MANAGE_BOTS` | Install and remove bots |
| 14 | `VIEW_AUDIT_LOG` | |
| 15 | `USE_COMMANDS` | Run bot commands |
| 30 | `ADMINISTRATOR` | Everything |

In a channel: @everyone's bits, OR all your roles; the owner and
administrators get everything; then the channel's overwrites for @everyone,
your roles, and you. Private channels also need membership. In DMs and groups,
participants can view, send, read, react, attach, embed and use commands.

## Endpoints

### Auth and account

| | | |
|---|---|---|
| `POST /auth/register` | public | `{ username, password, displayName? }` → `201 { user, token, expiresAt }`. Off when `ALLOW_PASSWORD_SIGNUP=false` |
| `POST /auth/login` | public | `{ username, password }` → `{ user, token, expiresAt }` |
| `POST /auth/logout` | | Ends this session |
| `GET /auth/sessions` | | Your signed-in devices (`current` marks this one) |
| `DELETE /auth/sessions/:id` | | Sign one out |
| `POST /auth/password` | | `{ currentPassword?, newPassword }`: signs out your other sessions |
| `GET /auth/connections` | | Linked accounts (Roblox) |
| `POST /auth/roblox/start`, `/poll`, `GET /callback` | public | Sign in with Roblox (above) |
| `GET /users/@me` | bot | You |
| `PATCH /users/@me` | | `{ username?, displayName?, avatarUrl? }` |
| `DELETE /users/@me` | | `{ password? }`: deletes your account ([retention](SCHEMA.md#retention-and-cascades)) |
| `GET /users/:id` | bot | Anyone's public profile |
| `GET /users/@me/relationships` | | Who you blocked or muted |
| `PUT /users/@me/relationships/:userId` | | `{ type: "block" \| "mute" }` |
| `DELETE /users/@me/relationships/:userId?type=` | | |
| `GET /users/@me/audit-log` | | Your account's security history |

### Settings

| | |
|---|---|
| `GET /users/@me/settings` | `{ settings, overrides, version }`: `settings` is the defaults with your overrides |
| `PATCH /users/@me/settings` | Deep-merges the body; `null` resets that setting to its default |
| `GET /settings/defaults` | |
| `PATCH /channels/:id/settings` | Your own `{ muted, mutedUntil, notificationLevel, archived }` for one channel or conversation |

Sections: `notifications` (desktop, sound, defaultLevel, directMessages,
mentions, replies, everyone), `appearance` (theme, compact, fontScale,
showAvatars), `messages` (showEmbeds, showReactions, groupMessages,
timestampFormat), `privacy` (allowDirectMessages, showActivity),
`language`, `accessibility` (reducedMotion, highContrast, screenReaderHints),
`account` (timezone, developerMode).

### Workspaces, members, roles, invites

| | | |
|---|---|---|
| `POST /workspaces` | | `{ name, description?, iconUrl? }`: comes with @everyone, a category and #general |
| `GET /workspaces` | bot | Yours |
| `GET /workspaces/:id` | bot | With your `permissions` |
| `PATCH /workspaces/:id` | | `MANAGE_WORKSPACE` |
| `DELETE /workspaces/:id` | | Owner |
| `POST /workspaces/:id/transfer` | | `{ userId }`, owner |
| `GET /workspaces/:id/members?after=&limit=` | bot | Paged by user id |
| `GET /workspaces/:id/members/roblox/:robloxUserId` | bot | The member signed in with that Roblox account, or 404 (the plugin uses it for DMs) |
| `PATCH /workspaces/:id/members/@me` | | `{ nickname }` |
| `DELETE /workspaces/:id/members/:userId` | | Yourself: leave. Others: `KICK_MEMBERS` and a higher role |
| `PUT`/`DELETE /workspaces/:id/members/:userId/roles/:roleId` | | `MANAGE_ROLES`, roles below yours |
| `GET /workspaces/:id/roles` | bot | |
| `POST /workspaces/:id/roles` | | `{ name, color?, permissions?, position?, mentionable? }` |
| `PATCH`/`DELETE /workspaces/:id/roles/:roleId` | | |
| `POST /workspaces/:id/invites` | | `{ maxUses?, expiresInSeconds? }`, `CREATE_INVITE` |
| `GET /workspaces/:id/invites` | | `MANAGE_WORKSPACE` |
| `GET /invites/:code` | | Preview |
| `POST /invites/:code` | | Join |
| `DELETE /invites/:code` | | Its creator or `MANAGE_WORKSPACE` |
| `GET /workspaces/:id/audit-log?before=&action=` | | `VIEW_AUDIT_LOG` |

### Channels

| | | |
|---|---|---|
| `GET /workspaces/:id/channels` | bot | The ones you can see, with your `permissions` |
| `POST /workspaces/:id/channels` | | `{ type: "text" \| "category", name, topic?, parentId?, position?, isPrivate?, slowmodeSeconds? }` |
| `GET /channels/:id` | bot | A channel, or a conversation |
| `PATCH /channels/:id` | | `MANAGE_CHANNELS` |
| `DELETE /channels/:id` | | `MANAGE_CHANNELS`; purged in the background |
| `GET /channels/:id/permissions` | | Overwrites |
| `PUT /channels/:id/permissions/:role\|member/:targetId` | | `{ allow, deny }` |
| `DELETE /channels/:id/permissions/:role\|member/:targetId` | | |
| `PUT`/`DELETE /channels/:id/members/:userId` | | Private channel membership |

### Conversations (DMs and groups)

| | |
|---|---|
| `POST /conversations` | `{ recipients: [id], name? }`. One recipient without a name: their DM (the existing one if any). More: a new group, at most 10 people |
| `GET /conversations?archived=&before=&limit=` | Yours, by latest activity, with `recipients`, `unreadCount` (up to 100), `readState`, `settings` |
| `GET /conversations/:id` | |
| `PATCH /conversations/:id` | `{ name?, iconUrl? }` (groups) |
| `PUT /conversations/:id/recipients/:userId` | Add someone (groups) |
| `DELETE /conversations/:id/recipients/:userId` | Yourself: leave. Others: owner only |

Starting a conversation respects blocks and the recipient's
`privacy.allowDirectMessages`.

### Messages

| | | |
|---|---|---|
| `GET /channels/:id/messages?before\|after\|around=&limit=` | bot | [Pagination](MESSAGES.md#pagination) |
| `POST /channels/:id/messages` | bot | `{ content?, replyTo?, attachments?, embeds?, components? (bots), flags?, nonce?, interactionId? (bots), clientData? }` |
| `GET /channels/:id/messages/:messageId` | bot | |
| `POST /channels/:id/messages/batch` | bot | Up to 50 of your own messages: `{ messages: [{ content, nonce, flags?, clientData? }] }` → `{ messages: [{ nonce, id, created }] }`. A nonce already stored is reported, not stored again, so a batch can be retried whole. No slowmode; 30 batches a minute |
| `PATCH /channels/:id/messages/:messageId` | bot | Author only: `{ content?, embeds?, components?, flags?, clientData? }` |
| `DELETE /channels/:id/messages/:messageId` | bot | Author, or `MANAGE_MESSAGES` |
| `GET /channels/:id/pins` | bot | |
| `PUT`/`DELETE /channels/:id/pins/:messageId` | bot | `MANAGE_MESSAGES` (anyone in a conversation) |
| `POST /channels/:id/ack` | | `{ messageId? }`: read up to there (default: the newest), clears the mention badge |

A message:

```json
{
  "id": "379340915523428352", "channelId": "…", "type": "reply",
  "author": { "id": "…", "username": "ana", "displayName": "Ana", "avatarUrl": null, "isBot": false },
  "content": "Lighting is done <@379…>", "flags": 0,
  "replyTo": { "id": "…", "author": { … }, "content": "Who has the map?", "deleted": false },
  "mentions": ["379…"], "mentionEveryone": false,
  "embeds": [], "components": [], "metadata": {},
  "attachments": [{ "id": "…", "filename": "map.png", "contentType": "image/png", "size": 1234 }],
  "reactions": [{ "emoji": "👍", "count": 2, "me": true }],
  "nonce": null, "createdAt": "…", "editedAt": null
}
```

`clientData` (an object, at most 8 KB) is what the sending client wants to keep about a message, such as the plugin's sender name and Studio timestamp. It comes back as `metadata.client`. It's display data: the author, id and time that count are the server's.

Mentions are written `<@userId>` and parsed by the server. `flags`:
`4` hides link embeds, `4096` sends without notifying.

### Reactions

| | |
|---|---|
| `PUT`/`DELETE /channels/:id/messages/:messageId/reactions/:emoji/@me` | Yours (bot) |
| `DELETE /channels/:id/messages/:messageId/reactions/:emoji` | Clear one emoji (`MANAGE_MESSAGES`) |
| `GET /channels/:id/messages/:messageId/reactions/:emoji?after=&limit=` | Who reacted |

`:emoji` is a URL-encoded Unicode emoji or `name:id`. At most 20 different
emoji per message.

### Attachments

1. `POST /channels/:id/attachments { filename, contentType, size }` →
   `{ attachment, upload: { url, method: "PUT", headers, expiresIn } }`
2. `PUT` the bytes to `upload.url` with exactly those headers (within 15 minutes).
3. `POST /attachments/:id/complete`: checks size and type against what was stored.
4. Send it: `POST /channels/:id/messages { attachments: [id] }`.

`GET /attachments/:id` → `{ attachment, url }`, a download link valid for 5
minutes, for anyone who can read the message. `DELETE /attachments/:id`
cancels an upload that isn't on a message yet. All accept bots.

### Search

`GET /search/messages?q=&channelId=|workspaceId=&authorId=&after=&before=&cursor=&limit=`

Full-text: every word must match, the last one as a prefix. Dates are ISO
8601. Without `channelId` or `workspaceId`, it searches every channel and
conversation you can read. Results are newest first; pass `nextCursor` as
`cursor` for the next page.

### Notifications and read states

| | |
|---|---|
| `GET /notifications?before=&limit=&unread=` | Mentions, replies and DMs, newest first |
| `POST /notifications/read` | `{ ids }` or `{ upTo }` |
| `GET /users/@me/read-states` | Last read message and mention count per channel |

### Bots

See [BOTS.md](BOTS.md): `/bots`, `/bots/:id`, `/bots/:id/token`,
`/bots/:id/signing-secret`, `/bots/:id/commands`,
`/bots/:id/workspaces/:workspaceId/commands`, `/workspaces/:id/bots`,
`/workspaces/:id/commands`, `/channels/:id/interactions`.

### Health

| | |
|---|---|
| `GET /health/live` | The process is up |
| `GET /health/ready` | `200` when the database and cache answer (`503` otherwise), with waiting and failed job counts |

## Live events

`GET /api/v1/gateway` (bot) is a [Server-Sent Events](https://html.spec.whatwg.org/multipage/server-sent-events.html)
stream of everything you can see happen:

```text
event: message.create
data: {"id":"…","channelId":"…","content":"…",…}
```

It starts with `ready`. A comment line every 25 seconds keeps it open.

| Event | Data |
|---|---|
| `message.create`, `message.update` | The message |
| `message.delete` | `{ id, channelId }` |
| `reaction.add`, `reaction.remove`, `reaction.clear` | `{ channelId, messageId, emoji, userId? }` |
| `pin.add`, `pin.remove` | `{ channelId, messageId }` |
| `channel.create`, `channel.update`, `channel.delete` | The channel |
| `channels.changed` | Something about channels you may see changed: fetch the list again |
| `conversation.create`, `conversation.update`, `conversation.delete` | `{ id, … }` |
| `conversation.recipient_add`, `conversation.recipient_remove` | `{ channelId, userId }` |
| `workspace.join`, `workspace.leave`, `workspace.update`, `workspace.delete` | |
| `member.add`, `member.update`, `member.remove` | `{ workspaceId, userId }` |
| `role.create`, `role.update`, `role.delete`, `commands.update` | |
| `notification.create` | `{ notification, message }`, unless that channel is muted or below your notification level |
| `read_state.update`, `settings.update`, `channel_settings.update`, `relationship.add`, `relationship.remove`, `user.update` | Your own changes, for your other devices |

A stream only gets events for channels you can see. Joining, leaving or
gaining access updates it at once; access that other people change
reaches it within a minute.
