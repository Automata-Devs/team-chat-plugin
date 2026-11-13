# Security Policy

## Reporting a problem

If you find a security problem in Team Chat (for example a way to read
messages you shouldn't see, act with a rank you don't have, get badges
without buying them, run code through the chat, sign in as someone else, or
get into a place's stored chat on the backend), **please don't open a public
issue.**

Instead, report it privately with GitHub's
[private vulnerability reporting](../../security/advisories/new) for this
repository, or message @D3veloperHac on Roblox.

Please include:

- what the problem is and what someone could do with it;
- the steps to reproduce it;
- the plugin version (shown in the chat window's title).

You'll get a reply as soon as possible. Please give a reasonable amount of
time to fix the problem before telling anyone else about it.

## What's in scope

The plugin and backend code in this repository, and the Team Chat backend
that D3veloperHac runs. Don't test against other people's places or accounts,
or in ways that could slow down or break the backend for others. Problems in
Roblox or Roblox Studio themselves should be reported to Roblox through its
[bug bounty program](https://hackerone.com/roblox).

## Good to know

Chat data is stored inside the place, so **anyone who can edit a place can
read and change its chat data**. That is how Team Create works, not a
security problem in the plugin. The same goes for the chat stored on the
backend: it's end-to-end encrypted with a key made from the place's secret,
which is saved in the place, so people who can edit the place can read it.
The backend itself can't. See [PRIVACY.md](PRIVACY.md) and
[docs/backend/PLUGIN.md](docs/backend/PLUGIN.md#end-to-end-encryption).
