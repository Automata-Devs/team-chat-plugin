# Privacy Policy

_Last updated: 13 November 2026_

This policy explains what the **Team Chat** plugin for Roblox Studio (the
"Plugin") and the **Team Chat backend** (the server that stores each place's
chat, run by D3veloperHac) do with information.

In short:

- The chat lives **inside the place** you're working on, as it always has.
- When you **sign in with Roblox**, the Plugin also stores the place's chat on
  the Team Chat backend, so it's safe from `/clear`, reverts and lost places.
  Messages are **end-to-end encrypted** before they leave Studio: the backend
  can't read what you write. It does see who wrote a message, when, and where.
- If you don't sign in, nothing of yours is sent to the backend.
- Your settings stay on your own computer.

## What is stored in the place and on your computer

| What | Where it's stored | Who can see it |
|---|---|---|
| Messages, direct messages, replies, polls, reactions, file and image links, and bot messages | Inside the place, in `ServerStorage.TeamChatData`, saved with the place | **Everyone who can edit the place**, including people who open it later. Direct messages are not private from other editors. |
| Ranks, mutes, bans, warnings, the blacklist and whitelist | Inside the place | Everyone who can edit the place |
| The place's backend details: its server, its key on the backend, its secret (which makes the encryption key) and its workspace | Inside the place, in `TeamChatData.Backend` | Everyone who can edit the place |
| Typing status and "who is looking where" (/goto) | Inside the place, while you're in Team Create | Everyone editing the place at the same time |
| Your settings (theme, language, text size, notifications, read status, command usage counts) | Roblox Studio's plugin settings on **your computer** | Only you |
| Your sign-in to the backend, the place secrets you've used, and changes waiting to be stored | Roblox Studio's plugin settings on **your computer** | Only you |
| A local backup of each place's chat | Roblox Studio's plugin settings on **your computer** | Only you |
| Images you attach | Uploaded to Roblox as assets on **your** Roblox account | Anyone the asset is visible to on Roblox |
| Bots people made: their scripts, names and commands | Inside the place (`ServerStorage.TeamChatBots`, `TeamChatData`) | Everyone who can edit the place |
| Your Open Cloud API key for your bots (if you save one with `/bot key`) | Roblox Studio's plugin settings on **your computer** | Only you |

Private bot replies ("Only you can see this") are never saved anywhere.

## The Team Chat backend

### When it's used

The Plugin asks you once per computer to sign in with Roblox. Only after you
sign in does it store anything of yours on the backend, and only for places
whose admins haven't turned it off (`/backend disconnect`). You can sign out
any time with `/backend logout`.

Signing in happens on Roblox's own website: you type a short code at the
backend's sign-in page and approve on roblox.com. The backend never sees your
Roblox password.

### What the backend stores

| What | Readable by the backend? |
|---|---|
| **Your account:** your Roblox user ID, username, display name and avatar link (from Roblox when you sign in), and when you were last active | Yes |
| **Your sign-ins:** a fingerprint of each sign-in (never the sign-in itself), when it started and was last used, and the IP address and browser or app it came from | Yes |
| **The place:** its Roblox place ID, its name, who is in it, and a fingerprint of a fingerprint of its secret (never the secret) | Yes |
| **Messages** you write in the place's team chat, DMs and groups: their text, and their details (sender name, Studio timestamps, replies, polls, files, embeds, bot answers) | **No: end-to-end encrypted** |
| **About each message:** your account as its author, when it was sent and edited, which channel or DM it's in, its size, and whether it was deleted | Yes |
| **Reactions** (which emoji, and who reacted) | Yes |
| **DMs and groups:** who is in them, and their names | Yes |
| **An audit log:** joins, moderation and account changes, with the IP address they came from | Yes |

### End-to-end encryption

The Plugin encrypts each message's text and details in Studio, with a key made
from the place's secret, before sending it. The backend only ever stores
unreadable text, and it never receives the secret or the key: joining a place
sends a fingerprint of the secret instead.

- **Everyone who can edit the place has the key**, because the secret is
  saved in the place, just like the chat itself. So the people who can read
  the chat in the place can also read what's stored for it.
- **The backend, its database and whoever runs them can't read messages.** They
  can see the information marked "Yes" above.
- Before Team Chat 1.33 (13 November 2026), stored messages weren't encrypted.
  The hosted backend holds none of those any more, and a place's workspace
  refuses unencrypted messages.

### Where it's hosted

The backend runs on [Render](https://render.com/privacy) and its database on
[Neon](https://neon.com/privacy-policy), both in Frankfurt, Germany (EU). They
host the service for D3veloperHac. The server's logs (which include IP
addresses and the addresses of requests, but never sign-in tokens) are kept by
Render for a limited time.

### How long it's kept

- **Messages** stay until you delete them, or until the place's workspace is
  deleted. A deleted message's text and details are wiped; an empty
  placeholder stays so replies still work.
- **Sign-ins** end after 30 days without use, or when you sign out, and are
  removed 30 days after that.
- **Your account** stays until you ask for it to be deleted (see below).
- The database keeps a short history for recovering from mistakes (Neon's
  restore window); deleted data leaves it when that window passes.

## The team database (optional)

Admins can also connect a place to a **team database on their own server**
with `/database connect`. Then the place's team chat is sent there **readable,
not encrypted**, and that server's owner is responsible for it. D3veloperHac
doesn't run or see those servers.

## What else the Plugin sends, and to whom

- **Roblox**, through Roblox Studio's own services: avatars, usernames, display
  names and verified badges; which badges (game passes) you own, and the
  names and prices of the ones for sale; images you attach (to your own
  Roblox account). Roblox's [Privacy and Cookie Policy](https://en.help.roblox.com/hc/articles/115004630823)
  covers what Roblox does with information.
- **Bots** (see below).

The Plugin doesn't use analytics, ads or tracking. The backend's sign-in pages
load nothing from other websites and set no cookies.

## Bots people make

Team Chat lets people make their own bots ([docs/BOTS.md](docs/BOTS.md)). A
Studio bot runs in its **owner's** Studio; a web bot runs on its owner's own
server. Either way, its owner decides what it does. When you use a bot's
command, or a bot reads the team chat, what you typed goes to that bot, and its
owner's code could send it to Roblox's Open Cloud or other websites. When you
use a **web bot's** command or button, your Studio sends it straight to the
bot's server, with your Roblox user ID and username, the place ID and the
conversation.
D3veloperHac doesn't make, check or control bots other people make. Only use
bots from people you trust, and ask a bot's owner what it does with messages.

## Deleting your information

- **Messages:** delete your own messages in the chat; that deletes them on the
  backend too. Anyone who can edit the place can delete the place's chat by
  removing `ServerStorage.TeamChatData` and saving the place. `/clear` only
  clears your own view, and `/purge` deletes messages in the place but not
  what's stored on the backend.
- **Signing out:** `/backend logout` ends your sign-in on this computer.
- **A place:** admins can stop storing a place with `/backend disconnect`. To
  delete everything stored for a place, contact D3veloperHac.
- **Your account:** contact D3veloperHac to delete it. Your name, avatar,
  Roblox link and sign-ins are removed and you're shown as "Deleted User". Your
  messages stay (encrypted) unless you delete them first.
- **Settings and local backups:** uninstall the Plugin, or delete its plugin
  settings in Roblox Studio.
- **Images:** manage your uploaded assets on Roblox.com.

## Your rights

You can ask D3veloperHac for a copy of the information the backend has about
you, to correct it, to delete it, or to stop processing it. The backend stores
your information to provide the service you sign in for, and keeps IP
addresses and the audit log to keep the service secure. If you live in the EU
or UK, you can also complain to your data protection authority.

## Children

Team Chat is for people who use Roblox Studio, and follows Roblox's age rules.
Signing in uses your existing Roblox account; the backend only stores what's
described above, for anyone of any age.

## Changes

This policy can change with Plugin updates. The current version is always in
this file, with the date it was last updated. **What's New** in the Plugin
lists important changes.

## Contact

Privacy questions or requests: message [d3v_c](https://discord.com/users/1140557619208130641)
on Discord, or open an issue in this repository (don't post personal
information in it).
