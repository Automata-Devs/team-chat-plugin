# Security Policy

## Reporting a problem

If you find a security problem in Team Chat (for example a way to read
messages you shouldn't see, act with a rank you don't have, get badges
without buying them, or run code through the chat), **please don't open a
public issue.**

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

The plugin's code in this repository. Problems in Roblox or Roblox Studio
themselves should be reported to Roblox through its
[bug bounty program](https://hackerone.com/roblox).

## Good to know

Chat data is stored inside the place, so **anyone who can edit a place can
read and change its chat data**. That is how Team Create works, not a
security problem in the plugin. See [PRIVACY.md](PRIVACY.md).
