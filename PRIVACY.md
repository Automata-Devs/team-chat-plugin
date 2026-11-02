# Privacy Policy

_Last updated: 2 November 2026_

This policy explains what the **Team Chat** plugin for Roblox Studio (the
"Plugin") does with information. In short: **the Plugin keeps your chat inside
the place you're working on and your settings on your own computer. It sends
nothing to D3veloperHac or to any server other than Roblox's.**

## What is stored, and where

| What | Where it's stored | Who can see it |
|---|---|---|
| Messages, direct messages, replies, polls, reactions to polls, file and image links, and Team Chat's public bot messages | Inside the place, in `ServerStorage.TeamChatData`, saved with the place | **Everyone who can edit the place**, including people who open it later. Direct messages are not private from other editors. |
| Ranks, mutes, bans, warnings, the blacklist and whitelist | Inside the place | Everyone who can edit the place |
| Typing status and "who is looking where" (/goto) | Inside the place, while you're in Team Create | Everyone editing the place at the same time |
| Your settings (theme, language, text size, notifications, read status, command usage counts) | Roblox Studio's plugin settings on **your computer** | Only you |
| A local backup of each place's chat | Roblox Studio's plugin settings on **your computer** | Only you |
| Images you attach | Uploaded to Roblox as assets on **your** Roblox account | Anyone the asset is visible to on Roblox |

Private bot replies ("Only you can see this") are never saved anywhere.

## What the Plugin sends, and to whom

The Plugin only talks to **Roblox**, through Roblox Studio's own services, to:

- show avatars, usernames, display names and verified badges;
- check which badges (game passes) you own;
- open Roblox.com pages when you choose to buy a badge;
- upload images you choose to attach (to your own Roblox account).

The Plugin does **not** send your messages, settings or any other information
to D3veloperHac, to analytics services or to any other server. D3veloperHac
cannot read your chats unless they can edit your place.

Roblox's own [Privacy and Cookie Policy](https://en.help.roblox.com/hc/articles/115004630823)
covers what Roblox does with information.

## Deleting your information

- **Messages:** you can delete your own messages from the chat. Anyone who can
  edit the place can delete chat data by removing `ServerStorage.TeamChatData`
  and saving the place. The `/clear` command only clears your own view.
- **Settings and local backups:** uninstall the Plugin, or delete its plugin
  settings in Roblox Studio.
- **Images:** manage your uploaded assets on Roblox.com.

## Children

Roblox has its own rules for younger users. The Plugin doesn't collect
anything beyond what's described above, for anyone of any age.

## Changes

This policy can change with Plugin updates. The current version is always in
this file, with the date it was last updated.

## Contact

Privacy questions: open an issue in this repository (don't post personal
information in it) or message [d3v_c](https://discord.com/users/1140557619208130641) on Discord.
