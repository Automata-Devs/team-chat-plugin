# Storing Team Chat on the backend

Team Chat stores **every place's chat** in the backend's database (for example
Neon), organised like Discord: each place is a **workspace** (a "server"),
and everything said in that place lives under it:

```text
Your backend
└── Place "Obby" (place:1077...)        one workspace per place, made by itself
    ├── #team-chat                       the place's team chat
    ├── DM Ana ↔ Bo                      DMs, only for the two people in them
    └── Group "Builders"                 group DMs, only for their members
└── Place "Racing" (place:2093...)
    └── ...                              the same people have separate DMs here
```

Stored: messages (with their polls, files, bot answers and replies), edits,
deletes and reactions, and everything written before storing started. Chat
still travels through the place in Team Create as before, so it stays
instant; the backend is the safe copy. It outlives `/clear`, `/purge`, a
reverted or deleted place.

## Nothing to set up per place

1. **Once, for your team:** put the backend online on HTTPS
   ([OPERATIONS.md](OPERATIONS.md)) with Sign in with Roblox switched on (an
   OAuth 2.0 app on create.roblox.com with the redirect URL
   `https://<your backend>/api/v1/auth/roblox/callback` and the scopes `openid`
   and `profile`). Set its address as `DEFAULT_URL` in `src/Config/Backend.luau`
   and build the plugin.
2. **Once per person and computer:** when Studio opens, Team Chat asks you to
   sign in with Roblox. The link is in the **Output** window (View > Output):
   open it in your browser and approve. Plugins can't open a browser
   themselves, and this is how the backend knows it's really you.

That's all. When anyone opens a place with Team Chat, its workspace is found,
or made on the spot, and everyone in the place joins it automatically. No
commands, no admins.

Studio asks once to allow Team Chat's HTTP requests to the backend's domain.

## How a place is recognised

- A published place is `place:<PlaceId>`. An unpublished one gets a random key,
  saved in the place.
- The place keeps a **secret** in `TeamChatData.Backend`. Joining its workspace
  needs proof of it, so only people who can open the place can get its chat;
  knowing a PlaceId isn't enough. Your computer remembers the secret too, so a
  reverted place still finds its workspace.
- Your sign-in is kept on your computer, never in the place. The Roblox
  account you approve must be the one signed in to Studio; another one isn't
  used, so nobody can store messages as someone else.

## End-to-end encryption

Everything stored is sealed in Studio before it's sent, so the server, its
database (Neon) and whoever runs them only ever hold unreadable text.

- **The key is made from the place's secret**, so everyone who can open the
  place has it and nobody else does. The secret itself never leaves Studio:
  joining sends `sha256(secret)` as a proof, and the database keeps only
  `sha256` of that. Neither can be turned back into the secret or the key.
- **What's sealed:** each message's text, and all its client data (sender
  name, timestamps, replies, polls, files, embeds, bot answers), with
  ChaCha20 and an HMAC-SHA256 tag, so changed text is noticed too. The format
  is in [MESSAGES.md](MESSAGES.md#end-to-end-encryption).
- **What the server still sees:** who wrote a message and when (its account and
  id), which channel or DM it's in, its size, reactions (emoji), and the
  names of the place, its channels and its members. It needs those to keep
  DMs private, order messages and restore them.
- **The server refuses readable text in a place's workspace**, so an older
  Team Chat can't store any. Older versions (1.32 and before) are told to
  update.
- **Messages stored before 1.33** were readable. Each person's Team Chat seals
  their own again by itself (it edits them, which replaces the text on the
  server), for every message still in the place. What's no longer in the place
  stays readable until it's deleted: see
  [OPERATIONS.md](OPERATIONS.md#messages-stored-before-end-to-end-encryption).
- **Not available on sealed messages:** the server's search and @mention
  notifications (it can't read the text). Team Chat doesn't use either.
- **Anyone who can open the place can read its stored chat**, just as they can
  read the chat in the place itself (it's saved in `TeamChatData`, DMs too).
  Someone who loses access to the place can't join its workspace any more,
  but anything they already copied stays with them.

## How storing works

- **Each person stores their own messages**, under their own account, so every
  stored message has a verified author. A message is stored once: its name in
  the place is its key on the backend, and the backend's id is saved on it
  (`BackendId`). Uploads go in batches of up to 50.
- **Nothing is lost offline.** Messages not stored yet are found again in the
  place (every 2 minutes, and when you sign in). Edits, deletes and reactions
  wait in plugin settings and survive closing Studio.
- **A place's DMs and groups belong to its workspace.** Someone who hasn't
  signed in yet has no account there: your DM with them is stored once they
  sign in, and they're added to groups then.
- **`/clear` and `/purge` don't delete anything stored**; deleting one of your
  own messages does.
- **Restore** (`/backend restore`, admins) rebuilds team chat messages missing
  from the place exactly as they were. It only adds.

## Optional commands

| | |
|---|---|
| `/backend status` | The server, whether you're signed in, whether the place is set up, what's waiting |
| `/backend login` / `logout` | Sign in again, or out, on this computer |
| `/backend sync` | Store what's waiting now (it happens every 5 seconds anyway) |
| `/backend restore` | Bring back team chat messages missing from the place (admins) |
| `/backend connect <url>` | Use another server than the default for this place (admins) |
| `/backend disconnect` | Stop storing this place (admins). What's stored stays, and connecting again finds the same workspace |

## Not stored

- Answers only one person sees (ephemeral bot answers).
- Messages of people who never sign in: each person's own plugin stores theirs.
- Pins, and poll votes cast after a message was stored. They stay in the place;
  a restore brings polls back with the votes they had when stored.
