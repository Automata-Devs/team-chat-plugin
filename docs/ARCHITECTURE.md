# Architecture

Team Chat is a Roblox Studio plugin: a chat panel (team chat + direct
messages) for people working in the same place over Team Create. Messages are
shared through folders in `ServerStorage.TeamChatData`, which Team Create
syncs and saves with the place.

## Folder tree

```
default.project.json        Rojo: builds the plugin (`rojo build -o TeamChatPlugin.rbxm`)
dev.project.json            Rojo: live-syncs src/ into ReplicatedStorage.TeamChatPlugin for testing
src/
  init.server.luau          Entry point, the only Script. Bootstraps App and handles unloading.
  init.meta.json            Plugin version (`Version` attribute).
  App.luau                  Composition root: starts services, builds the UI, wires controllers.
  Types.luau                Shared Luau types (messages, conversations, commands, palettes...).
  Config/                   Plain data. No logic, no requires except other Config.
    Constants.luau          Names, setting keys, folder names, limits, log level, version.
    Theme.luau              Palettes, fonts, sizes.
    Icons.luau              Builder Icons names.
    Changelog.luau          "What's New" entries.
    AllowedUsers.luau       Users granted a rank on load.
    Languages/              One module per language (en, nl, de, es, fr, pt): code, name, strings.
    Badges.luau             Badge definitions, game pass ids, custom badges per user.
  Util/                     Pure helpers. Depend only on Config and other Util.
    Janitor.luau            Tracks connections/instances/threads/callbacks; Cleanup() tears all down.
    Signal.luau             Small typed event (Connect/Fire/Destroy).
    Duration.luau           Parses "1h30m" style durations.
    Links.luau              Finds links in message text; text layout for click hit-tests.
    RichText.luau           Escaping and message/header markup (links underlined).
    TimeFormat.luau         Clock formatting, ids.
    UsernameColors.luau     Stable name colors.
    EmojiData.luau          Emoji table + search.
    GifDecoder.luau         GIF decoding (frames for GifPlayer).
  Core/                     Plugin plumbing shared by everything below App.
    Lifetime.luau           The plugin's root Janitor; `alive` flag; stopped on Unloading.
    Logger.luau             Leveled logging (debug/info/warn/error), level from Constants.
    Settings.luau           Safe plugin:GetSetting/SetSetting, JSON values, per-place keys.
    PlaceStorage.luau       ServerStorage.TeamChatData folders.
    Identity.luau           The signed-in Studio user (resolved once), cached name lookups.
    Language.luau           Translations: t(key, vars), bind(), set(); finds Config/Languages.
    Browser.luau            Opens links (browser, clipboard fallback).
  Services/                 Data and behavior; no UI.
    Chat/                   Facade (init) + ChatState, MessageStore, Polls, Typing,
                            Conversations (team chat + DMs), VersionHistory.
    Admin/                  Facade (init) + AdminState, Ranks, Moderation, UserResolver.
    StudioCollab.luau       Claims and shared camera positions (/claim, /goto).
    History.luau            ChangeHistoryService wrapper (undo recordings).
    Usage.luau              Command/emoji usage counts (autocomplete order).
    Badges.luau             Who has which badge (verified, custom, game passes); store, purchase watch.
    Profiles.luau           Display names and verified flags (batched, cached).
  Commands/                 Chat commands ("features"). Auto-discovered.
    Registry.luau           Finds, registers and runs commands; built-in /help.
    _Template.luau          Copy this to make a command (skipped: names starting with "_").
    <Category>/<Name>.luau  One module per command.
  Controllers/              Glue between UI and services.
    PluginController.luau   Toolbar, widget visibility, conversations <-> UI.
    MessageController.luau  Sending, Enter handling, running commands.
  UI/                       Instances only; talks to the rest through callbacks.
    ChatWindow/             The dock widget: init (layout, composer, public API), Header,
                            ContextMenu, TypingBar, Pointer (mouse helpers).
    Messages/               Builders for each message kind + recoloring.
    Components/             Reusable pieces (ConversationList, Autocomplete, AttachmentCards,
                            AudioPlayback, GifPlayer, MediaFocus).
    Dialogs/                ModalKit + Settings, Create a Poll, What's New, New message,
                            Badges, Checkout (PurchaseDialog), About; SettingsTabs joins
                            Settings, Badges, What's New and About into one tabbed window.
    Preferences.luau        Display settings several UI modules read (names, badges, ...).
    Animation.luau          The animation controller: every tween, fade and pop goes through it.
    Embeds/                 Link previews (providers auto-discovered).
    LinkHelper.luau         Clickable links inside message text.
  Packages/Abbreviate/      Vendored third-party formatter (unchanged).
tests/                      Studio test harness, runner and specs (synced by dev.project.json).
tools/                      Python helpers (Studio export import, migration, static analysis).
legacy/                     Untouched v1.5.1 export, kept until the refactor is verified.
docs/                       AUDIT.md, ARCHITECTURE.md.
```

## Dependency rules

```
Config < Util < Core < Services < Commands, UI < Controllers < App < init.server
```

- A module may require modules in its own layer or any layer to its left,
  never to its right (Util never requires Core, Services never require UI).
- UI and Commands are siblings: UI never requires Services or Commands, and
  Commands never require UI. Data reaches the UI through the API that
  `UI/ChatWindow` returns, called by Controllers.
- Core (Lifetime, Logger, Settings, Browser) is usable from every layer above it.
- Facades (`Services/Chat`, `Services/Admin`) are what Controllers and
  Commands use; sub-modules are internal to their folder.
- No cycles (checked by `python tools/analyze.py src`).
- Every `require` uses an instance path (`script.Parent...`), so the plugin
  works the same built by Rojo or pasted into Studio by hand.

## Lifecycle

- `Core/Lifetime` owns the root `Janitor`. Every long-lived connection,
  instance, thread and timer is added to it (or to a child Janitor that is).
- `init.server.luau` connects `plugin.Unloading` to `App.stop`, which calls
  `Lifetime.stop()`: everything is disconnected/destroyed, loops see
  `Lifetime.alive == false` and exit.
- The dock widget is created with a fixed id, so a reload reuses it; its old
  contents are cleared before the new UI is built.

## Undo policy (ChangeHistoryService)

- `Services/History.record(name, fn)` wraps a change in
  `TryBeginRecording`/`FinishRecording`, so it's one Ctrl+Z step, and cancels
  the recording if `fn` errors.
- Used for changes to **the user's place content** made on their behalf.
  Today that is only `/waypoint` (sets a waypoint); no command edits user
  instances.
- Chat data in `ServerStorage.TeamChatData` (messages, DMs, typing status,
  claims) is shared plugin state, not the user's work. It is deliberately not
  recorded: an undo step per message would let Ctrl+Z delete messages for the
  whole team.

## Conventions

- `--!strict` in every file we own (`Packages/` is vendored).
- PascalCase module files and module tables; camelCase functions and locals;
  UPPER_SNAKE constants; types PascalCase and exported from `Types` when shared.
- Each file starts with a header: what it is for and how to use it. Public
  functions get a `--[=[ ... ]=]` doc comment.
- No globals (`_G`, `shared`), no deprecated APIs (`wait`, `spawn`, `delay`,
  `Instance.new(class, parent)`): use `task.*`.
- Risky Studio calls (`GetSetting`, web calls, asset uploads, `require` of
  discovered modules) are wrapped in `pcall` and reported through `Logger`
  with a message the user can act on.
- Strings, colors, sizes, setting keys and limits live in `Config/`.
- Formatting: StyLua (`stylua.toml`). Linting: Selene (`selene.toml`).

## How to extend

- **New command:** copy `Commands/_Template.luau` into a category folder
  (`Commands/Utility/MyCommand.luau`), fill in the fields. It's picked up
  automatically: no registry edits. Give `Args` a name and description each:
  they're shown above the message box while the command is typed.
- **New badge:** add it to `Config/Badges.DEFINITIONS` and `ORDER`; give it a
  `gamePassId` to sell it, or list user ids in `USERS` to give it out.
- **New service:** add `Services/MyService.luau` with `init()` (and `stop()` if
  it owns resources, or add them to `Lifetime`), then start it in `App.luau`.
- **New dialog:** add `UI/Dialogs/MyDialog.luau` built on `ModalKit`, create
  it in `UI/ChatWindow/init.luau` and expose an opener through the window API.
- **New link preview:** add a provider module to `UI/Embeds/Providers/`.
- **New language:** copy `Config/Languages/en.luau` to `<code>.luau`, set
  `code`, `name` (in that language) and `englishName`, and translate the
  strings. It shows up in Settings > Language by itself; the Language spec
  checks it has every key and the same `{placeholders}`.
- **New text in the UI:** add a key to `en.luau` (and the other languages),
  then use `Language.t(key)` or `Language.bind(label, "Text", key)` so it
  follows language changes.
- **New setting:** add its key to `Config/Constants.SETTING_KEYS`, read and write
  it through `Core/Settings`.

## Migration map

Generated by `tools/migrate.py` (old path under `legacy/TeamChatPlugin/` ->
new path under `src/`). "removed" files stay in `legacy/` only.

| Old | New |
|---|---|
| `init.server.luau` | `init.server.luau` (rewritten: bootstrap only) + `App.luau` |
| `src/Commands/CommandHandler` | `Commands/Registry` |
| `src/Commands/Template` | `Commands/_Template` |
| `src/Commands/<Category>/<Name>` | `Commands/<Category>/<Name>` |
| `src/Config/PluginConfig` | `Config/Constants` |
| `src/Config/{Theme, Icons, Changelog, AllowedUsers}` | `Config/` (same names) |
| `src/Config/Types` | `Types` (rewritten) |
| `src/Core/Lifetime` | `Core/Lifetime` (rebuilt on `Util/Janitor`) |
| `src/Core/PluginController` | `Controllers/PluginController` |
| `src/Core/MessageController` | `Controllers/MessageController` |
| `src/Networking/PlaceStorage` | `Core/PlaceStorage` |
| `src/Networking/ChatNetwork` | `Services/Chat/init` |
| `src/Networking/Chat/ChatState` | `Services/Chat/ChatState` |
| `src/Networking/Chat/MessageStore` | `Services/Chat/MessageStore` |
| `src/Networking/Chat/PollManager` | `Services/Chat/Polls` |
| `src/Networking/Chat/TypingIndicator` | `Services/Chat/Typing` |
| `src/Networking/Chat/Conversations` | `Services/Chat/Conversations` |
| `src/Networking/Chat/VersionHistory` | `Services/Chat/VersionHistory` |
| `src/Networking/Chat/MessageEvents` | removed (unused since DMs) |
| `src/Networking/AdminNetwork` | `Services/Admin/init` |
| `src/Networking/Admin/AdminState` | `Services/Admin/AdminState` |
| `src/Networking/Admin/RankManager` | `Services/Admin/Ranks` |
| `src/Networking/Admin/ModerationManager` | `Services/Admin/Moderation` |
| `src/Networking/Admin/UserResolver` | `Services/Admin/UserResolver` |
| `src/Networking/StudioNetwork` | `Services/StudioCollab` |
| `src/Utils/UsageTracker` | `Services/Usage` |
| `src/Utils/LinkHelper` | `UI/LinkHelper` (click hit-test) + `Util/Links` (finding links) + `Core/Browser` (opening) |
| `src/Utils/RichTextHelper` | `Util/RichText` |
| `src/Utils/TimeFormatter` | `Util/TimeFormat` |
| `src/Utils/{EmojiData, GifDecoder, UsernameColors}` | `Util/` (same names) |
| `src/UI/ChatUI` | `UI/ChatWindow/{init, Header, ContextMenu, TypingBar, Pointer}` + `UI/Messages/{init, TextMessage, Announcement, PollMessage, FileMessage, Recolor, Shared}` |
| `src/UI/{ModalKit, SettingsDialog, CreatePollDialog, ChangelogDialog, ChangelogView, NewMessageDialog}` | `UI/Dialogs/` |
| `src/UI/Components/{AttachmentCards, AudioPlayback, Autocomplete, ConversationList, GifPlayer, MediaFocus}` | `UI/Components/` |
| `src/UI/Components/{AttachMenu, DropOverlay, EmptyState, FileCard, InputBar, MessageItem, PollCard, PollDialog, PreviewBar, SystemMessage}` | removed (dead duplicates) |
| `src/UI/Embeds/**` | `UI/Embeds/**` |
| `src/Packages/Abbreviate/**` | `Packages/Abbreviate/**` |
| new | `Util/{Janitor, Signal, Duration, Links}`, `Core/{Logger, Settings, Identity, Browser}`, `Services/History`, `App`, `tests/*` |

## Execution plan

Each step ends with the checks in brackets; the project stays runnable.
Status: steps 1-3 done and verified in Studio; step 4 done for the header,
context menu, typing bar, pointer and every message builder (the composer is
still in `ChatWindow/init`); step 5 done for formatting and lint, `--!strict`
on 58 of 105 files; step 6 docs done.

1. **Move.** `tools/migrate.py` copies legacy files to the new tree and rewrites
   requires; add Rojo projects, StyLua/Selene configs. [build, analyze: no
   unresolved/cycles, Studio smoke test: plugin loads, send/DM/poll]
2. **Foundations.** Janitor, Signal, Logger, Settings, Identity; rebuild Lifetime
   on Janitor; route settings and logging through them. [same checks]
3. **Services.** Dedupe identity/settings/duration code, fix AUDIT bugs (H2,
   H3, M1, M9), History service, Browser service. [same + targeted tests]
4. **Split ChatUI** into ChatWindow/* and Messages/*. [full UI test in Studio]
5. **Strict + clean.** `--!strict` everywhere, shared Types, StyLua, Selene
   clean, docs comments. [selene 0 errors, stylua --check, Studio test]
6. **Ship.** README, CHANGELOG, build the plugin, install and check Output on
   load/use/unload/reload.
