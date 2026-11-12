# Team Chat

A Roblox Studio plugin that adds a chat panel for people working on the same
place over Team Create: a team chat pinned to the game, direct messages,
replies, @mentions, polls, images, animated GIFs, audio, file cards, link
previews, Discord-style markdown, #tags for objects in the place, slash
commands with Team Chat's own bot replies (`/help` lists them), and bots you
can make yourself, in Studio or on your own server ([docs/BOTS.md](docs/BOTS.md)), plus an admin dashboard and a developer portal in Settings. Optionally, a team
database in MongoDB (or a JSON file), behind a small server, keeps the chat's
history, profiles and bot data
([docs/DATABASE.md](docs/DATABASE.md)). Available in English,
Nederlands, Deutsch, Español, Français and Português.

Messages are stored in `ServerStorage.TeamChatData` inside the place, so Team
Create syncs them to every collaborator and they are saved with the place.
Personal preferences (theme, language, clock, read state, usage counts) are
saved in plugin settings on each person's computer.

> **Source-available, not open source.** You're welcome to read the code,
> report bugs, suggest features and contribute translations or fixes. You may
> **not** copy, re-upload, redistribute or sell the plugin or its code. See
> [LICENSE.md](LICENSE.md).

Team Chat is not made, endorsed, sponsored by or affiliated with Roblox
Corporation.

## Install

Install **Team Chat** from its
[Roblox Creator Store listing](https://create.roblox.com/store/asset/78044069343761), or go to [Releases](https://github.com/Automata-Devs/team-chat-plugin/releases). 
That is the only official version.

## Legal

| Document | What it covers |
|---|---|
| [LICENSE.md](LICENSE.md) | What you may and may not do with the code; how contributions are licensed |
| [TERMS.md](TERMS.md) | Terms of use for the plugin, badges and purchases |
| [PRIVACY.md](PRIVACY.md) | What the plugin stores, where, and who can see it |
| [SECURITY.md](SECURITY.md) | How to report a security problem privately |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | How to behave in this repository |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | Licences of included third-party material (the spell check word list) |

## Contributing

Translations, bug fixes and features are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) first: it explains how to set up, what to
check before opening a pull request, and the contribution terms.

## Develop

Tools are pinned in `aftman.toml` (Rojo, StyLua, Selene):

```bash
aftman install
rojo serve dev.project.json
```

Connect from the Rojo plugin in Studio. `dev.project.json` syncs `src/` into
`ReplicatedStorage.TeamChatPlugin` and `tests/` into
`ServerStorage.TeamChatTests`. Both services keep unknown children, so the
place's real `TeamChatData` is never touched. While Rojo is connected, edit the
files on disk, not the copies in Studio.

Checks:

```bash
stylua --check src tests          # formatting
selene src                        # lint (0 warnings expected)
python tools/analyze.py src       # unresolved requires, cycles, dead modules
```

Tests run inside Studio (command bar) against a separate copy of the plugin
and a separate data folder:

```lua
print(require(game.ServerStorage.TeamChatTests.Runner).run())          -- all specs
print(require(game.ServerStorage.TeamChatTests.Runner).run("Smoke"))   -- by name
```

A local build for testing your changes:

```bash
rojo build default.project.json -o build/TeamChatPlugin.rbxm
```

Builds are for your own testing only; publishing or sharing them isn't allowed
(see [LICENSE.md](LICENSE.md)).

The version is the `Version` attribute in `src/init.meta.json`; "What's New"
notes live in `src/Config/Changelog.luau` (the plugin shows the entry whose
version matches once after an update). `CHANGELOG.md` is the developer-facing
history.

## Folders

| Path | What's in it |
|---|---|
| `src/init.server.luau` | Entry point: starts `App`, stops it on unload. The only Script. |
| `src/App.luau` | Composition root: starts services, builds the window, wires controllers. |
| `src/Config/` | Constants, setting keys, theme, icons, changelog, badges, languages. |
| `src/Config/Languages/` | One module per language; English (`en.luau`) has every key. |
| `src/Util/` | Pure helpers: Janitor, Signal, Duration, RichText, Links, Mentions, emoji, GIF decoding. |
| `src/Core/` | Plugin plumbing: Lifetime, Logger, Settings, Identity, Language, PlaceStorage, Browser. |
| `src/Services/` | Chat (messages, DMs, polls, pins, reactions, typing, backups), Admin, Bots, Database (the team database), Badges, History (undo), ObjectTags, Profiles, StudioCollab, Usage. |
| `server/` | The team database server (Node.js) and its tests. |
| `src/Commands/` | One module per slash command, discovered automatically. |
| `src/Controllers/` | Glue between the UI and the services. |
| `src/UI/` | `ChatWindow/` (the dock widget, split into Feed, Composer, Sidebar...), `Messages/`, `Components/`, `Dialogs/`, `Embeds/`, `Text/` (text layout and styling) and `Common/` (animation, styling, display preferences). |
| `src/Packages/` | Vendored third-party code (Abbreviate). |
| `lang/` | The languages as JSON (`tools/lang_to_json.py` makes them from `src/Config/Languages`). |
| `tests/` | Studio test harness, runner and specs. |
| `tools/` | Python helpers for checks and conversions. |
| `docs/` | `ARCHITECTURE.md` (design, rules, how to extend), `BOTS.md` (making bots), `DATABASE.md` (the team database) and `AUDIT.md` (findings). |

Adding a command: copy `src/Commands/_Template.luau` into a category folder and
fill it in. See `docs/ARCHITECTURE.md` for everything else.

---

Copyright (c) 2026 D3veloperHac. All rights reserved.
