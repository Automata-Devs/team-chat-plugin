# Architecture

Team Chat is a Roblox Studio plugin: a chat panel (team chat + direct
messages) for people working in the same place over Team Create. Messages are
shared through folders in `ServerStorage.TeamChatData`, which Team Create
syncs and saves with the place.

## Folder tree

```text
default.project.json        Rojo: builds the plugin (`rojo build -o TeamChatPlugin.rbxm`)
dev.project.json            Rojo: live-syncs src/ into ReplicatedStorage.TeamChatPlugin for testing
src/
  init.server.luau          Entry point, the only Script: starts App, stops it on unload.
  init.meta.json            Plugin version (`Version` attribute).
  App.luau                  Composition root: starts services, builds the UI, wires controllers.
  Config/                   Plain data: Constants, Theme, Icons, ToolbarIcons, Badges,
                            Changelog, AllowedUsers, Languages/, Dictionary/.
  Util/                     Pure helpers: Janitor, Signal, Duration, Links, RichText,
                            Markdown, Mentions, SpellCheck, TimeFormat, EmojiData, GifDecoder...
  Core/                     Plugin plumbing: Lifetime, Logger, Settings, PlaceStorage,
                            Identity, Language, Browser.
  Services/                 Data and behaviour; no UI.
    Chat/                   Facade (init) + ChatState, MessageStore, Polls, Typing,
                            Conversations, Pins, Reactions, Stats, VersionHistory.
    Admin/                  Facade (init) + AdminState, Ranks, Moderation, UserResolver,
                            AuditLog, ChatRules.
    Bots/                   Facade (init) + Options, Manifests, Messages, Studio (bots that
                            run in Studio), Web (bots on a server), Portal (developer portal).
    Badges, Profiles, Usage, ObjectTags, StudioCollab, History
  Commands/                 Slash commands, auto-discovered.
    Registry.luau           Finds, registers and runs commands; built-in /help.
    _Template.luau          Copy this to make a command (names starting with "_" are skipped).
    <Category>/<Name>.luau  One module per command.
  Controllers/              PluginController (toolbar, conversations <-> UI),
                            MessageController (sending, Enter, running commands).
  UI/                       Instances only; never requires Services or Commands.
    ChatWindow/             The dock widget. init builds it from its parts and returns the API:
                            Feed (message list), Composer (message box, reply bar),
                            Suggestions (autocomplete), Attachments (preview, uploads,
                            drag and drop), Sidebar, Dialogs, Header, ContextMenu,
                            EmojiPicker, PinsPanel, TeamCreateNotice, TypingBar, Pointer.
    Messages/               Builders for each message kind, grouping and recoloring.
    Components/             Reusable pieces: ConversationList/ (init, Row, Footer, Tooltip),
                            Autocomplete, Controls, Toasts, Tooltip, GifPlayer...
    Dialogs/                Kit/ (ModalKit, PanelKit), Settings/ (the tabbed window and its
                            General page), Changelog/, Admin/ and Developer/ (a module per
                            section), About, Badges, CreatePoll, NewMessage, Purchase.
    Embeds/                 Link previews and command cards (providers auto-discovered).
    Text/                   Text layout and styling: MessageText, TextLayout, ComposerText,
                            MentionPills, SpellingMarks.
    Common/                 Animation, Foundation (control styling), Preferences.
  Packages/Abbreviate/      Vendored third-party formatter (unchanged).
tests/                      Studio test harness, runner and specs (synced by dev.project.json).
tools/                      Python helpers: analyze, build_versions, lang_to_json,
                            make_dictionary, make_badge_icons.
docs/                       ARCHITECTURE.md, BOTS.md, AUDIT.md.
```

## Dependency rules

```text
Config < Util < Core < Services < Commands, UI < Controllers < App < init.server
```

- A module may require modules in its own layer or any layer to its left,
  never to its right (Util never requires Core, Services never require UI).
- UI and Commands are siblings: UI never requires Services or Commands, and
  Commands never require UI. `App` passes the services the UI uses
  (`{ admin, bots, chat, objectTags, usage }`) into `ChatWindow.create`;
  everything else reaches the UI through the API `ChatWindow` returns,
  called by Controllers.
- Facades (`Services/Chat`, `Services/Admin`, `Services/Bots`) are what
  Controllers, Commands and the UI use; their sub-modules are internal.
- A folder module's parts share state through one table passed to each part
  (ChatWindow's `ctx`, the dashboards' `view`), not through globals.
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
- ChatWindow builds its parts in a fixed order: siblings with the same
  ZIndex draw in the order they were added.

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

- PascalCase module files and module tables; camelCase functions and locals;
  UPPER_SNAKE constants; types PascalCase.
- Each file starts with a `--[[ Name ... ]]` header saying what it is for and
  how to use it. Public functions get a `--[=[ ... ]=]` doc comment. Other
  comments explain why, not what the code already says.
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
  If the UI needs it, add it to the services table `App` passes to
  `ChatWindow.create`.
- **New dialog:** add `UI/Dialogs/MyDialog.luau` built on `Dialogs/Kit/ModalKit`,
  create it in `UI/ChatWindow/Dialogs.luau` and expose an opener through the
  window API in `UI/ChatWindow/init.luau`.
- **New part of the chat window:** add `UI/ChatWindow/MyPart.luau` with
  `create(ctx, hooks)` returning its API (and `recolor()`), create it in
  `ChatWindow/init.luau` and call its `recolor` from `applyTheme`.
- **New link preview:** add a provider module to `UI/Embeds/Providers/`.
- **New language:** copy `Config/Languages/en.luau` to `<code>.luau`, set
  `code`, `name` (in that language) and `englishName`, and translate the
  strings. It shows up in Settings > Language by itself; the Language spec
  checks it has every key and the same `{placeholders}`.
- **New text in the UI:** add a key to `en.luau` (and the other languages),
  then use `Language.t(key)` or `Language.bind(label, "Text", key)` so it
  follows language changes.
- **New setting:** add its key to `Config/Constants`, read and write it
  through `Core/Settings`.
