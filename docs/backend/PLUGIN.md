# Storing Team Chat on the backend

With the backend connected, Team Chat stores **everything you write** in its
database (for example Neon), under your own account:

- messages in the team chat, DMs and group DMs, with their polls, files, bot
  answers and replies
- your edits, your deletes and your reactions
- everything you wrote before connecting

Chat still travels through the place in Team Create, as before, so it stays
instant. The backend is the safe copy: it outlives `/clear`, `/purge`, a
reverted or deleted place, and an admin can bring the team chat back with
`/backend restore`.

## What you need

1. **The backend running on a public HTTPS address.** Roblox has to reach it
   for sign-in, and every teammate's Studio has to reach it.
   [OPERATIONS.md](OPERATIONS.md) has ways to host it, with Neon as the database.
2. **Sign in with Roblox switched on:** an OAuth 2.0 app on create.roblox.com
   with the redirect URL `https://<your backend>/api/v1/auth/roblox/callback`
   and the scopes `openid` and `profile`, and its id and secret in the backend's
   `.env` (`ROBLOX_OAUTH_CLIENT_ID`, `ROBLOX_OAUTH_CLIENT_SECRET`).

## Set up a place (an admin, once)

```text
/backend connect https://chat.example.com
/backend login
```

`login` prints a link in the **Output** window (View > Output): copy it into
your browser, approve on roblox.com, and Team Chat finishes by itself.
An admin's first sign-in creates a workspace for the place on the backend,
uses its #general as the team chat, and saves the server and an invite in the
place, so teammates join automatically.

Studio asks once to allow Team Chat's HTTP requests to the backend's domain.

## Everyone else (once per computer)

```text
/backend login
```

Your sign-in is kept on your computer, never in the place. The Roblox account
you approve must be the one signed in to Studio; another one is signed out
again, so nobody can store messages as someone else.

## Commands

| | |
|---|---|
| `/backend status` | The server, whether you're signed in, whether the place is set up, what's waiting |
| `/backend connect <url>` | Point the place at a backend (admins) |
| `/backend login` / `logout` | Sign in or out on this computer |
| `/backend sync` | Store what's waiting now (it also happens every 5 seconds) |
| `/backend restore` | Bring back team chat messages missing from the place (admins). It only adds; nothing is changed or removed |
| `/backend disconnect` | Stop using the backend in this place (admins). What's stored stays |

## How it works

- **Each person stores their own messages**, with their own sign-in, so every
  stored message has a verified author. A message is stored once: its name in
  the place is its key on the backend, and the backend's id is saved on it
  (`BackendId`). Uploads go in batches of up to 50.
- **Nothing is lost offline.** Messages that aren't stored yet are found again
  in the place (every 2 minutes, and right after you sign in). Edits, deletes
  and reactions wait in plugin settings and survive closing Studio.
- **DMs and groups** become backend DMs and groups with the same people. A
  teammate who hasn't signed in yet has no account there: your DM with them is
  stored once they sign in, and they're added to groups then.
- **`/clear` and `/purge` don't delete anything stored**; deleting one of your
  own messages does.
- **Restore** rebuilds messages as they were (sender, time, poll, file,
  reply) from what their sender's plugin stored.

## Not stored

- Answers only one person sees (ephemeral bot answers).
- Messages of people who never sign in: each person's own plugin stores theirs.
- Pins, and poll votes cast after a message was stored. They stay in the place;
  a restore brings polls back with the votes they had when they were stored.
