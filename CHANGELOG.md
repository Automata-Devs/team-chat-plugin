# Changelog

Developer-facing history of the codebase. User-facing notes ("What's New")
are in `src/Config/Changelog.luau`. Format: [Keep a Changelog](https://keepachangelog.com).

## [1.32.2] - 2026-11-13

### Changed
- `BackendConfig.DEFAULT_URL` is the team's backend on Render
  (`https://teamchat-backend-a9f5.onrender.com`): every place is stored there
  once people sign in.
- `Backend.Connection`: copies of the plugin run by the specs
  (`__TeamChatUnderTest`) ignore `DEFAULT_URL`, so tests never reach the real
  server; a spec still points its copy at a fake one with `Backend.connect`.

## [1.32.1] - 2026-11-13

### Added
- `backend/render.yaml`: a Render Blueprint for the backend (free web service
  in Frankfurt, `rootDir: backend`, `npm ci && npm run build`, `npm start`,
  `/health/ready`), prompting for `DATABASE_URL` and the Roblox OAuth app and
  generating `ENCRYPTION_KEY`. Set its Blueprint Path to `backend/render.yaml`.
  Steps in `docs/backend/OPERATIONS.md`.
- `loadConfig`: without `PUBLIC_URL`, Render's `RENDER_EXTERNAL_URL` is used.

### Fixed
- `backend/src/modules/bots/` was never committed: the repository's `bots/`
  ignore rule matched it, so the backend on GitHub didn't build since 1.30.0.
  Found by a clean build like Render's.

### Changed
- `backend/package.json` engines: `>=20 <25` (Render picks the newest match).

## [1.32.0] - 2026-11-13

Every place is stored on the backend by itself, as its own workspace.

### Added
- Backend: `POST /places/:placeKey/workspace` finds or makes a place's workspace
  (`workspaces.place_key` unique, `place_secret_hash`, `team_chat_channel_id`;
  migration `0001_places`). Whoever calls it first makes it with its
  `#team-chat`; others join with the place's secret (403 otherwise).
  Simultaneous first calls end in one workspace.
- Backend: DMs and groups can belong to a workspace (`workspaceId` on
  `POST /conversations`, a filter on `GET /conversations` and search). Their
  members must be in it, the same pair has a separate DM per workspace, they
  never show in the workspace's channel list, and leaving or deleting the
  workspace takes them along.
- Plugin: `BackendConfig.DEFAULT_URL` (the team's server, set before building)
  and `AUTO_SIGN_IN`. On start the plugin asks to sign in with Roblox by itself
  (once per session, the link in the chat and the Output window), then joins or
  makes the place's workspace (`Backend.join`, `Backend.tick`). A place's key
  (`place:<PlaceId>` or a saved `local:<id>`) and secret live in
  `TeamChatData.Backend`; the secret is also remembered per computer, so a
  reverted place keeps its workspace. `Backend.onNotice` shows messages in the chat.

### Changed
- Plugin: no admin step. `/backend connect` only overrides the default server
  for a place; `/backend disconnect` marks the place `Disabled` and keeps its
  key and secret. DMs and groups are made in the place's workspace.
- Backend: the channels check allows a workspace on DMs and groups; workspace
  channel lists, gateway topics and search only list text channels, and a
  place's conversations go by membership.

## [1.31.0] - 2026-11-12

Team Chat stores everything on the backend (`docs/backend/PLUGIN.md`).

### Added
- `Services/Backend` (`Connection`, `Session`, `Client`, `Channels`, `Mirror`,
  `Outbox`, `Restore`) and `/backend status | connect | login | logout | sync |
  restore | disconnect`.
  - Sign in with Roblox from Studio: the link goes to the Output window, the
    plugin polls, and the Roblox account must be Studio's own
    (`/auth/connections`), else it's signed out again. Sessions are kept per
    server in plugin settings, never in the place.
  - An admin's first sign-in creates the place's workspace (#general as the
    team chat) and saves the server, workspace, channel and an invite in
    `TeamChatData.Backend`; teammates join with the invite.
  - Each plugin stores its own user's messages (team chat, DMs, groups) in
    batches of 50, with `readEntry`'s fields as client data and the message's
    name as the nonce, and keeps the backend's id on it (`BackendId`). Older
    messages are flagged not to notify. Edits, deletes (`ChatState.onDelete`,
    so not `/clear`) and reactions go through a persisted outbox. A rescan every
    2 minutes finds anything not stored yet.
  - DMs and groups map to backend conversations (groups keep `BackendChannel`
    on their folder); teammates without an account are retried every 5 minutes.
  - `Restore.teamChat` rebuilds missing messages with their original names.
- `ChatState.buildMessage(entry, name?)` and `ChatState.onDelete`.
- Backend: `clientData` on messages (`metadata.client`, at most 8 KB),
  `POST /channels/:id/messages/batch` (up to 50 own messages, retry-safe),
  `GET /workspaces/:id/members/roblox/:robloxUserId`.
- Specs: `Backend.spec` (against a fake backend); backend tests for the batch
  endpoint, the lookup, and the plugin's exact request sequence.

## [1.30.1] - 2026-11-12

### Changed
- `backend/docker-compose.yml`: a `DATABASE_URL` in `.env` (a hosted
  PostgreSQL such as Neon or Supabase) is used instead of the bundled
  PostgreSQL; empty, it falls back to the bundled one. `.env.example` leaves
  `DATABASE_URL` empty and says to use the direct, non-pooled string.

### Fixed
- `backend`: empty values in `.env` (`S3_ENDPOINT=`, `WORKER_ID=`, ...) were
  validated as given and stopped the server starting; they now count as not set.

## [1.30.0] - 2026-11-12

A Discord-style backend in `backend/` (docs in `docs/backend/`). The plugin
doesn't use it yet; `server/` stays the team database it uses.

### Added
- `backend/`: Node.js 20+ and TypeScript, Fastify, zod, Drizzle on
  PostgreSQL 15+, Redis (optional), S3-compatible storage.
  - Accounts: scrypt passwords, sessions stored as SHA-256 hashes, Roblox
    OAuth 2.0 + PKCE sign-in shaped for Studio (start, open in a browser,
    poll), session lists and revoking, password changes signing out other
    devices.
  - Workspaces with @everyone and roles (Discord-style permission bits, role
    order), members, invites (uses counted atomically), ownership transfer,
    a per-workspace audit log.
  - Channels: text and category, private channels with members, permission
    overwrites, slowmode, per-user mute, notification level and archive.
  - Conversations: one DM per pair (also when opened from both sides at
    once), group DMs of up to 10 with owner hand-over, blocks and a
    "who may DM me" setting.
  - Messages: snowflake ids (worker ids leased from Redis), id-cursor
    pagination (`before`, `after`, `around`), replies, server-parsed mentions,
    embeds, bot buttons, edits, tombstone deletes, retry-safe `nonce`, pins,
    read states with unread counts and mention badges.
  - Reactions (20 emoji per message), attachments uploaded and downloaded with
    signed S3 URLs and checked on completion, full-text search limited to
    what the searcher can read, a notification inbox.
  - Bots: accounts with hashed tokens and encrypted signing secrets, a managed
    role per installation, commands and interactions, HMAC-signed event POSTs
    with retries, and checks that refuse private addresses (SSRF).
  - A Postgres job queue filled in the same transaction as each change:
    notifications, bot events, channel and workspace purges, clean-up.
  - Server-Sent Events gateway (`/api/v1/gateway`) over Redis pub/sub.
  - Rate limits per user, bot and IP; `/health/live` and `/health/ready`;
    `503` with `Retry-After` while the database is down, recovering by itself.
  - Dockerfile, docker-compose (PostgreSQL, Redis, MinIO, API), `.env.example`,
    `scripts/backup.sh` and `scripts/restore.sh`.
  - 95 tests (Vitest) against a real PostgreSQL started by the test run
    (embedded-postgres), including concurrency, permission and outage tests.
- `docs/backend/`: architecture, schema with an ER diagram and the retention
  rules, API, message ids and storage scaling, bots, operations.

## [1.29.0] - 2026-11-12

The database server can keep its data in MongoDB.

### Added
- `server/stores/mongo.js`: a MongoDB store, used when `MONGODB_URI` is set
  (`MONGODB_DB`, default `teamchat`). Collections `kv`, `archive` and
  `profiles` with their indexes are created on start. Key/value values are
  kept as JSON text and stat names escape `.`, so any value or stat name
  works.
- `render.yaml`: a Render Blueprint for the server (free plan, generated
  token, `MONGODB_URI` to fill in).
- `GET /` answers `{ ok: true }` without a token, for hosts' health checks.
  `/v1/health` also returns `store` (`mongodb`, `file` or `memory`).

### Changed
- The JSON-file store moved to `server/stores/file.js`. Route handlers
  validate input and call a store (`kvList`, `kvGet`, `kvPut`, `kvDelete`,
  `archivePut`, `archiveHistory`, `archiveSearch`, `profileGet`,
  `profileUpdate`, `close`); `createServer({ token, store })`.
- `server/` depends on the `mongodb` driver (`npm install`).
- `ifVersion` must be a number (400 otherwise); search text is capped at 200
  characters.
- Server tests run against each store; set `MONGODB_TEST_URI` to include
  MongoDB.
- `docs/DATABASE.md`: MongoDB Atlas setup and hosting.

## [1.28.0] - 2026-11-12

A team database on your own server (`docs/DATABASE.md`).

### Added
- `Services/Database`: facade plus `Connection` (URL and token in
  `TeamChatData.Database`), `Client` (HttpService, token header, problems,
  swappable transport), `Outbox` (queued writes in plugin settings), `Cache`
  (last answers for offline reads), `Store` (key/value collections),
  `Archive` (uploads your own team chat messages in batches; history and
  search) and `UserStats` (profiles and a `messagesSent` count).
- `Config/Database.luau` for its keys, timings and limits.
- `/database` (`/db`): status, connect and disconnect (admins), sync, search
  and profile.
- Studio bots get `ctx.db`, their own collection.
- `server/`: a Node.js 18+ server with no dependencies (JSON file store,
  constant-time token check, size and name limits) and its tests (`npm test`).
- `tests/Specs/Database.spec.luau` against a fake server.

## [1.27.1] - 2026-11-12

A restructure with no behaviour or visual change.

### Changed
- `UI/ChatWindow` is a composition root (about 420 lines, was about 3,200)
  over `Feed`, `Composer`, `Suggestions`, `Attachments`, `Sidebar` and
  `Dialogs`, which share one context table (`ctx`). Parts are created in the
  old order, so equal ZIndexes still draw the same.
- The UI no longer requires Services: `App` passes
  `{ admin, bots, chat, objectTags, usage }` into `ChatWindow.create`, and
  the Admin and Developer dialogs take them as `params.services`.
- Split by section: `Dialogs/Admin` (Overview, Members, Moderation, Audit,
  Tools, Shared), `Dialogs/Developer` (BotList, NewBot, Docs, Shared,
  `BotPage/` with Overview, Console, Logs, Edit),
  `Components/ConversationList` (Row, Footer, Tooltip, Shared).
- `Services/Bots` is a facade over Options, Manifests, Messages, Studio, Web
  and Portal, with the same `Bots.*` API; the chat window hooks are set with
  `Bots.setUi` instead of assigning `Bots.ui`.
- `Services/Chat` exposes `Stats` and `VersionHistory`; the backup commands
  and the admin dashboard use them through the facade.
- Folders: `UI/Common` (Animation, Foundation, Preferences), `UI/Text`
  (ComposerText, MentionPills, MessageText, SpellingMarks, TextLayout),
  `Dialogs/Kit` (ModalKit, PanelKit), `Dialogs/Settings` (the tabbed window,
  `General` page), `Dialogs/Changelog` (`UpdateView`); the other dialogs drop
  their `Dialog` suffix (`About`, `Badges`, `CreatePoll`, `NewMessage`,
  `Purchase`). GUI instance names are unchanged.
- One comment style: `--[[ Name ]]` headers and `--[=[ ]=]` docs on public
  functions; comments that restated code or named old modules are gone.
- `tests/Harness.luau` patches the new modules; `docs/ARCHITECTURE.md` and
  the README describe the new layout.

### Removed
- `legacy/` (the v1.5.1 export) and the one-off migration tools
  (`migrate.py`, `split_messages.py`, `section_deps.py`, `import_export.py`).

## [1.27.0] - 2026-11-07

### Added
- `UI/Foundation`: Roblox Foundation looks on the palette's new `tint` (a
  see-through blue-grey): `input` (tint + outline), `stroke` ("FoundationStroke",
  muted/default/emphasis) and `button` variants (emphasis, standard,
  subEmphasis, alert) with hover and press states.
- `UI/Messages/Grouping` (`Messages.group`): Discord-style groups. A message
  from the same sender within 7 minutes hides its `Author` header (`Grouped`
  attribute) and shows its time in the gutter on hover; replies, system and
  only-you messages, the New line and other rows start a group. Message rows
  get a soft hover highlight.
- `Theme.RADIUS` (Foundation's 2/4/8/16/round), `Theme.STATE`, `Theme.STROKE`.
- Header: a `#` / `@` before the name (`TitleOptions.icon`; Icons `channel`,
  `dmHeader`).

### Changed
- `Theme.PALETTES` rebuilt from Roblox's Foundation tokens (read from
  roblox.com): dark surfaces #121215-#272930 with #F7F7F8 / #D5D7DD / #BCBEC8
  text, light white / #F7F7F8 with #202227 / #494D5A / #6A6F81; overlays baked
  onto their surface. Mentions use Roblox blue (soft emphasis,
  `MENTION_TRANSPARENCY` 0.65), `LINK_COLOR` is #4078FF, and the display and
  heading fonts are Builder Sans Bold instead of Builder Extended.
- Corner radii on Foundation's scale across the UI: 8 for buttons, inputs,
  cards and menus, 16 for modals and the Settings window, 4 for tags and
  tooltips.
- Headings are sentence case (no `string.upper`): Settings sections and tab
  groups, the sidebar, the poll and new message dialogs, ModalKit's
  "heading" role (14px) and PanelKit's (12px).
- `PanelKit.button` is 32px with Foundation variants, plus chip styles for
  pick-one switches: "choice", and "selected" for the chosen one (admin
  periods, slowmode, audit filters, backups, the developer bot kind);
  `PanelKit.tabs` are chips. `PanelKit.input` is a Foundation input and
  `pill` isn't in capitals.
- `Controls`: dropdowns are Foundation inputs (the outline turns blue on
  hover); toggle and slider tracks use the contrast stroke (`scrollBar`).
- Search boxes (sidebar, Settings, emoji picker, new message) are Foundation
  inputs; the sidebar's and the emoji picker's have a magnifying glass.
- Dialog buttons (poll, purchase, badges) and the What's New version tabs
  use Foundation buttons; bots' secondary and link buttons are a tint, 32px.
- `Messages/PollMessage`: a message row with an author header and a
  `PollCard` (Question, VoteSummary, Option_<i>, at most 460px wide);
  `ui.addPollMessage(..., senderId)`.
- `Messages/Announcement`: its text is in a `Content` frame; the header shows
  the plain time.
- ModalKit: Roblox's scrim colour, a 20px title, a title icon in the text
  colour.

### Fixed
- Announcement cards grew far taller than their text: the accent bar was in
  the card's list layout at the card's full height.
- Specs: the title checks allow the Development Mode tag, About's terms check
  ignores case, and the composer's marker colour comes from the palette.

## [1.26.2] - 2026-11-07

### Changed
- `UI/Messages/Reactions`: your own reactions are softer, filled with
  `messageText` at 0.25 transparency (0.33 hovered, 0.4 pressed) instead of
  solid, so they're a light gray in Dark and a dark gray in Light rather than
  white and black.

## [1.26.1] - 2026-11-07

### Changed
- `UI/Messages/Reactions`: Roblox-style chips instead of Discord-style pills.
  Capsules (`UICorner` 1,0) with no outline, 26px high; others' reactions on a
  see-through tint of `messageText` (0.9, 0.84 hovered, 0.78 pressed, so they
  suit tinted rows), yours filled with `messageText` and drawn in `scrollBack`;
  the emoji a size up from the bold count; the add button a round icon
  button. Hover and press states repaint from the bar's latest palette, which
  `recolor` keeps.
- The title checks in the Reactions and Social specs expect the
  Development Mode tag when `DEVELOPMENT_MODE` is on.

## [1.26.0] - 2026-11-06

### Added
- `Services/Chat/Reactions` (`ChatNetwork.Reactions`): emoji reactions saved
  on the message as a `Reactions` attribute (JSON `[{e, u, n}]`, at most 20
  different emoji), kept in chat history. `toggle` takes the message's name
  (or a timestamp) and adds or removes yours; `read` gives
  `{emoji, count, users, names, mine}`.
- `UI/ChatWindow/EmojiPicker`: search, a grid ordered by `Usage` emoji counts
  and the hovered `:name:`. Opened by the context menu's Add Reaction (now its
  first item, shown with `canReact`) and by the button after a message's
  reactions.
- `UI/Messages/Reactions`: the pills under a message (yours outlined), a
  hover tooltip with who reacted, re-themed by `Recolor`.
- Rows of saved messages get a `MessageId` (`ui.tagMessage`, from
  `PluginController.showMessage`), so reactions reach the right message when
  two share a second; `ui.setReactions` / `ui.onReact`.
- `Config/ToolbarIcons`: the toolbar button's icon with the unread count
  (1-9, 9+), uploaded images made by `tools/make_badge_icons.py`;
  `PluginController` sets it from the conversation list.
- Reactions spec.

### Changed
- The widget title puts the unread count last: `Team Chat 1.26.0 (3)`.

### Removed
- `:melting:` and `:saluting:` from `Util/EmojiData` (Emoji 14: Roblox draws
  them as empty boxes).

## [1.25.1] - 2026-11-06

### Changed
- `SettingsTabs`: the tab column and the open dialog's card are one window.
  A `SettingsWindow` frame behind both draws the background, the outline
  (the card's own `DialogStroke` is turned off), a divider and a
  `CornerFill` that squares the card's left corners; the column no longer
  tucks under the card. Tabs take a `group` and are listed under its
  heading (`Group_<group>`, `tab.group.*`; a thin rule when narrow); the
  plugin version (`tab.version`) is at the bottom. The open tab's `Pill`
  sits inside its highlight. New palette colours `navBack` and
  `navSelected`. Tabs are ordered General, Badges | Admin, Developer |
  What's New, About.
- Polish spec checks the window, the groups and the version.

## [1.25.0] - 2026-11-06

### Added
- `Services/Admin/AuditLog`: every moderation action, one folder per entry in
  `TeamChatData.AdminLog` (newest 500, sorted by an `Order` attribute so
  actions in the same second keep their order); the `Services/Admin` facade wraps
  mute, unmute, ban, unban, kick, warn, (un)blacklist, (un)whitelist,
  whitelist mode, slowmode, purge and setRank to record them and fire
  `onAdminEvent` (it was never fired before; it now returns a disconnect).
- `Services/Admin/ChatRules` (in `TeamChatData.ChatRules`): blocked words
  (whole words, any case; `MessageController` refuses them for anyone below
  moderator, keeping the text) and automatic backups every 1/6/24 hours,
  claimed through `LastAutoBackup` so only one plugin makes each.
- `Services/Chat/Stats`: messages per day and per hour, the most active
  people, DM/bot/file/poll counts and per-person totals; a text transcript
  saved as a ModuleScript in `ServerStorage.TeamChatExports`.
- `Services/Bots`: `test` (a Studio bot's command or button run with its
  answers collected; a web bot called with `"test": true`), `logOf` /
  `statsOf` / `clearLog` (`Log` and `Stats` on the manifest, from Studio and
  web interactions), `editBot` (`CustomName`, `CustomDescription`,
  `CustomAvatar`, `DisabledCommands`, `CommandNotes`, used by `list`,
  `commands`, `tryCommand` and posted messages) and `checkHealth`.
- `PanelKit.tabs`, `barChart`, `bars` and `codeBox`; `PanelKit.tile` is wider
  for long values (a date, a rank name) so they stay on one line.
- AdminPortal spec. BotInteractions opens the dashboard's and portal's
  sections before looking for their controls.

### Changed
- `AdminDialog`: sections Overview, Members (with details), Moderation, Audit
  log and Chat tools. `DeveloperDialog`: Your bots (a page per bot with
  Overview, Test console, Logs & stats and Edit), New bot and Docs.

## [1.24.1] - 2026-11-05

### Changed
- The message box styles markdown as you type, like Discord, instead of a
  preview bar above it. `Util/MarkdownSource` builds a doc whose plain text
  is exactly what's typed (markers dimmed; bold as a `<stroke>` outline,
  italic, underline, strikethrough, spoiler and code `<mark>`s, links and
  mentions coloured, ```lua lines via `SyntaxHighlight.spans`, a quote's `>`
  as a bar), using only styles that keep letters as wide. `UI/ComposerText`
  lays it over the TextBox, hides the TextBox's text (its placeholder still
  shows), and draws the cursor (blinking) and selection itself, measured on
  the styled text with `TextLayout.caret` / `TextLayout.lineRects` (a cached
  session per label).
- The markdown preview bar is gone.

## [1.24.0] - 2026-11-05

### Added
- Pinned messages (`Services/Chat/Pins`): `Pinned`, `PinnedAt`, `PinnedBy`,
  `PinnedByName` on the message folder, kept in history backups; at most 50
  per conversation. Pinning posts a Team Chat notice
  (`MessageStore.sendNotice`, attribute `Notice = "pin"`). The right-click
  menu has Pin / Unpin Message; the header has a pin button that opens
  `UI/ChatWindow/PinsPanel` (author, date, the message with markdown, Jump,
  Unpin).
- Spell check (`Util/SpellCheck`, `UI/SpellingMarks`): an English word list
  in `Config/Dictionary` (152k words from cspell's en_US, front-coded, built
  by `tools/make_dictionary.py`), loaded a module per frame the first time
  you type. Red Path2D zigzags under misspelled words in the message box;
  the word being typed is marked once you move on. Code, links, mentions,
  tags, emoji, /commands and identifiers aren't checked; people's names and
  words added with "Add to dictionary" (`TeamChatDictionary_v1`) count as
  right. Putting the cursor in a marked word lists suggestions (swapped
  letters and neighbouring keys first) in the autocomplete. Setting:
  Settings > Chat > Spell Check (`TeamChatSpellCheck_v1`).
- `THIRD_PARTY_NOTICES.md` for the word list.

### Changed
- Code blocks and quotes are drawn as parts of the message
  (`Markdown.blocks`, `UI/MessageText`): a code block is a bordered, rounded,
  padded box in BuilderMono, with ```lua/```luau coloured by
  `Util/SyntaxHighlight` (light and dark colours, function calls); a quote
  has a bar. `inline code` has a <mark> fill with a thin space each side
  and a rounded outline (`UI/MentionPills`). Indented list items get a
  hollow bullet. Fences follow Discord: a language word after ```, the
  closing ``` can end a line, an unclosed ``` is text.
- The markdown preview above the message box sits above the box (it was
  under it, behind the buttons) and no longer errors while typing.
- Language spec works with English only.

## [1.23.0] - 2026-11-02

### Added
- Web bots (`Kind = "web"` manifests with `Url` and `Token`): the requester's
  plugin POSTs JSON (`ping`, `command`, `button`, `followup`) with an
  `X-TeamChat-Token` header; answers are `pong`, `message`, `update`,
  `deferred` (then `followup` polled every 2 s for 60 s) or `none`.
  `Bots.createWeb`, `updateWeb`, `regenerateToken`, `tokenOf`, `syncWeb`.
  URLs must be https (http only to localhost/127.0.0.1).
- Typed command options (`string`, `integer`, `number`, `boolean`, `user`,
  `choices`), checked on the requester's side by `Bots.parseOptions`; choices
  show in autocomplete (mode `choice`). Old `args` still work.
- Message components: buttons in rows (`Bots.cleanComponents`,
  `UI/Embeds/Components`), saved as the `Components` attribute; clicks go to
  `bot.onButton(ctx, customId)` or a web bot's `button` interaction.
- Ephemeral answers (`VisibleTo`, skipped by other people's chats, unread
  counts and notifications) and deferred answers (`Thinking`, then edited in
  place with a `Revision` bump that re-renders the row). `ctx.defer`,
  `ctx.update`, `ctx.options`, `ctx.customId`, `ctx.message`.
- Settings > Developer (`UI/Dialogs/DeveloperDialog`) and Settings > Admin
  (`UI/Dialogs/AdminDialog`), built from `UI/Dialogs/PanelKit`.
  `AdminNetwork.getRankedUsers`. Bots can be turned off (`Disabled`).
- `tests/Specs/BotInteractions.spec.luau`; the harness records PanelKit
  button clicks and fakes `plugin:OpenScript`.

### Changed
- docs/BOTS.md covers web bots, options, buttons, ephemeral and deferred
  answers, and the token's threat model.

## [1.22.0] - 2026-11-02

### Added
- `Services/Bots`: user-made bots. A bot is a ModuleScript in
  `ServerStorage.TeamChatBots` with an `OwnerId`; it runs only in its owner's
  Studio. The owner's plugin publishes a manifest (name, description, avatar,
  commands; plain data) to `TeamChatData.Bots` with a `LastSeen` heartbeat,
  and answers requests other plugins leave in `TeamChatData.BotRequests`.
  Bot replies are saved messages with `BotId`, `BotOwner`, `BotAvatar` (kept
  through history save/restore), shown under "<name> used /command".
  `ctx`: `user`, `args`, `text`, `command`, `reply`, `send`, `http`,
  `openCloud` (apis.roblox.com with the owner's API key from plugin settings,
  never the place), `json`.
- `/bot create | list | reload | remove | key` (`Commands/Utility/Bot.luau`);
  the registry hands unknown commands to bots and lists bot commands in
  `/help` (a Bots group) and autocomplete. `Author.addBotTag(line, verified)`
  and `Author.markBot`: user-made bots get a plain BOT tag and their avatar.
- `docs/BOTS.md`; PRIVACY.md covers bots; Bots spec (17 checks).

### Fixed
- German `bot.offline` used `{owner}` twice.

## [1.21.1] - 2026-11-02

### Added
- Sidebar DMs: a `TimeLabel` with the last message's time today (clock
  format from Settings) or its date (`DD/MM`, `DD/MM/YY` when older), hidden
  while hovering (the close button takes its place).
- Sidebar search (expanded): filters DMs by display name and username
  (`SearchText` attribute); while searching, "New message" reads
  "Search friends for …" (`sidebar.searchFriends`) and opens the friend
  picker with the search filled in (`NewMessageDialog.open(query)`).
- Sidebar spec: 6 more checks.

Roblox doesn't offer an API for its own chat or friends list (Open Cloud
included), so DMs still reach friends inside the place only.

## [1.21.0] - 2026-11-02

### Added
- `Services/ObjectTags`: #tags point at objects in the place, saved as
  `#[<GetFullName()>]` and shown as `#Name` with a mention pill. `search`
  (selection first, then names in the main services, capped scan),
  `resolve` (names with dots work), `pathOf`, `focus` (selects the object;
  parts, models and attachments get a camera glide, or a jump with
  animations off).
- Composer: typing `#name` opens an Objects list (`Autocomplete.createObjectItem`
  with Studio's class icons); Tab or click inserts the tag. A `# ` header or
  `##` doesn't open it. Clicking a tag in a message calls
  `MessageText.onTag`; a missing object says so (`tag.notFound`).
- ObjectTags spec (17 checks). The 1.20.0 What's New entry is now
  "Formatting & tags".

## [1.20.0] - 2026-11-02

### Added
- `Util/Markdown`: Discord-style markdown parsed into RichText runs (plain
  text + tags + plain byte range): bold, italic, underline, strikethrough,
  inline code, code blocks, spoilers, headers (`#`, `##`, `###`), `-#`
  subtext, quotes, lists, masked links, `\` escapes; links, @mentions and
  `#[object]` tags become runs too. `slice`, `runAt`, `urls`, `strip`,
  `plainDoc`, `append`.
- `UI/TextLayout`: measures (rich) text the way Roblox lays it out, by prefix
  heights (lines can differ in height) and word ends (words wrap whole):
  `rect(label, doc, from, to)` and `hitTest(label, x, y)`.
- `UI/MessageText`: `set(label, content, palette, { edited })` renders a
  message's markdown and registers its doc; `attachClicks` opens links,
  reveals spoilers and calls `MessageText.onTag` for #tags.
- Markdown spec (29 checks).

### Changed
- Message text, file captions, edits and recolors render through
  MessageText; link previews take their URLs from the doc (masked links
  included). Notifications, reply previews and sidebar previews strip
  markdown. `MentionPills` places pills with TextLayout (and pills #tags).
- The "couldn't open the link" message is translated (`links.copied`).

### Removed
- `UI/LinkHelper` (replaced by TextLayout); its test now covers TextLayout
  after bold text.

## [1.19.1] - 2026-11-02

### Fixed
- Mentions: `Mentions.mentions(text, names)` takes a list; `Shared.myNames()`
  is your username and display name, so "@<display name>" mentions you.
  `Shared.mentionsMe(content, container)` also counts a reply to one of
  your messages (`ReplyToSenderId`, set only for real replies, not a bot's
  "used /command" line). The gold look is decided after `Author.attach` and
  re-checked on every recolor (your profile may load later).
- Notifications: display-name mentions and replies to you get through
  "DMs only"; replies say "{name} replied to you" (`notify.repliedToYou`).
- Reply lines colour @mentions (`RichText.colorMentions`).
- Mentions spec: 4 more checks.

## [1.19.0] - 2026-11-02

### Added
- Public bot messages: `MessageStore.sendBotMessage(content, embedJson?,
  command?)` saves a message from "System" with `SaidBy`, `SaidByName`,
  `Command` and `Embed` (a CommandEmbed spec as JSON, colour as hex).
  `ctx.addSystemMessage(text, { public = true })` and
  `ctx.addEmbed(spec, { public = true })` use it; the registry sets
  `ctx.command`. They render through `ui.addBotMessage` under a
  "<name> used /command" line (the reply-line component, no jump), can be
  deleted by whoever ran the command, and survive history save/restore
  (`ChatState` now keeps `SaidBy`, `SaidByName`, `Command`, `Embed`).
- Private bot messages (everything else) get "Only you can see this ·
  Dismiss message" (`Shared.addOnlyYouNote`); Dismiss removes the message.
- Cards: public for ban, kick, mute, tempmute, warn, blacklist, unban,
  unmute, unblacklist, whitelist, unwhitelist, setrank, slowmode, purge,
  togglewhitelist, roll and coinflip; private for who, listblacklist,
  listwhitelist, restore (list), backup and `/help` (grouped by tag; `/help`
  is now tagged Utility). The `reply.*` keys only the old line replies used
  are gone; new `bot.*`, `embed.*` and `commandGroup.*` texts.
- Bot spec (10 checks); Profiles and Smoke specs follow the public /roll, /coinflip and the /help card.

### Changed
- Team Chat shows as a verified bot: a "✓ BOT" tag (`Icons` `botCheck`,
  tooltip `system.verified`) instead of the verified badge and APP tag.

## [1.18.0] - 2026-11-02

### Added
- `UI/Embeds/Providers/CommandEmbed`: a command's reply as a card (title,
  description, avatar thumbnail, inline fields three to a row, footer, a
  coloured edge), built from a spec with `CommandEmbed.fromSpec`. Registered
  as a provider that never matches a link, so `EmbedManager.recolor` themes
  it. `ui.addSystemEmbed(spec)`; commands use `ctx.addEmbed(spec)` (falls
  back to text lines without a UI). Documented in `Commands/_Template`.
- Cards for `/whois` (avatar, name colour edge, User ID, Chat rank,
  Verified, In this place, Badges), `/stats`, `/serverstatus`,
  `/listusers`, `/warnings` and `/help <command>` (usage, each argument,
  aliases, required rank). `embed.*` texts in every language; the
  `reply.*` keys only the old line replies used are gone.

### Changed
- The plugin's messages ("System") show as Team Chat (`Author.nameOf`), in
  the plain text colour, with the verified badge (tooltip "Sent by the Team
  Chat plugin") and an APP tag (`system.tag`, `system.verified`).
- The "Replying to …" bar uses `Author.nameOf` (display names, Team Chat).
- Badges spec: Team Chat, the `/help` card and a `/whois` card (8 checks).

## [1.17.3] - 2026-11-02

### Fixed
- ChatWindow drag and drop: `PluginDragEntered` / `PluginDragDropped` get no
  drag data for drags that aren't plugin drags (Explorer items, files), and
  indexed `dragData.MimeType` on nil. Both now go through
  `isAttachmentDrag(dragData)`.
- Test harness: each faked widget event has its own signal
  (`hooks.events.<Event>`); they shared one, so a simulated focus loss also
  fired the drag handlers with no data (the errors seen during test runs).
  Social spec: a drag check that watches Output for errors.

## [1.17.2] - 2026-11-02

### Changed
- `UI/MentionPills`: the highlight behind an @mention is a rounded frame
  (4px corners) laid over it, placed by measuring the text like LinkHelper
  (`LinkHelper.measure` / `firstCharOfLine` are now shared). Used on
  message text, file captions and the message box, which can't colour its
  own text while typing. Re-measured on text, size and wrapping changes;
  recoloured on theme changes.
- `RichText` no longer uses `<mark>` for mentions, only the mention colour;
  `mentionText` is brighter since the tint now lies over it.
- Mentions spec: pill checks in messages and the message box (5).

## [1.17.1] - 2026-11-02

### Fixed
- Sidebar unread badge: its `UIStroke` ring had the default
  `ApplyStrokeMode` (Contextual), which on a TextLabel outlines the text, so
  the digit got a 2px dark outline that hollowed the badge out. Now
  `Border`, 3px, on an 18px badge with 11px text. Same fix for the
  scroll-to-bottom button's outline.
- Social spec: checks that no UIStroke on a TextLabel or TextButton outlines
  the text (2 checks).

## [1.17.0] - 2026-11-02

### Added
- `Util/Mentions`: `find(text)` (`@name`, 3-20 name characters, or
  `@everyone`, not inside a word), `mentions(text, username)` and
  `typing(text)` (an `@name` being typed at the end).
- Members picker: typing `@` lists people in the session (`Players`) and DM
  contacts, online first, plus `@everyone`
  (`Autocomplete.createMemberItem`); Tab or click inserts `@username `.
- `RichText.styleContent(content, palette?)` highlights mentions with
  `<mark>` (`mentionBack` at `Theme.MENTION_TRANSPARENCY`, `mentionText`);
  colours only, so LinkHelper's hit-testing is unchanged.
- `Shared.applyMention`: a message mentioning you gets the `Mentioned`
  attribute and a `MentionGradient` (2px gold bar, gold tint at
  `Theme.MENTION_ROW_TRANSPARENCY`). Re-applied after edits, theme changes
  and the jump-to-reply flash.
- Mentions notify you even with Notifications on "DMs only"; the toast says
  "{name} mentioned you".
- Translated the autocomplete titles and hint (`autocomplete.*`,
  `mention.everyoneHint`, `notify.mentioned`); `Autocomplete.DEFAULT_HINT`
  is now `Autocomplete.defaultHint()`.
- Mentions spec (24 checks).

### Fixed
- Profiles spec: the DM header checks make the DM the active conversation,
  so the controller's header refresh (`Conversations.onChanged`) can't swap
  it back to the team chat mid-test; it waits for user 156's name lookup.

## [1.16.3] - 2026-11-02

### Fixed
- Reply mini avatar: the plain avatar background (`menuItemHover`) behind a
  headshot instead of the author's name colour (kept behind their initial),
  and 20% transparent (`MINI_AVATAR_TRANSPARENCY`). `Shared.recolorSpine` is
  now `Shared.recolorReply` (line + mini avatar); `setReplyAvatar` takes the
  palette. Messages spec: 2 more checks.

## [1.16.2] - 2026-11-02

### Fixed
- Reply line (`Shared.createSpine`): a `Path2D` (even 2px line, a real
  quarter-circle corner) instead of a clipped rounded-rectangle stroke, which
  rendered thick and blotchy at the corner when scaled. It stops 3px above
  the message's avatar and 4px before the mini avatar. Its colour is blended
  towards the background (plugins can't set `Path2D.Transparency`) and
  follows theme changes (`Shared.recolorSpine` from `Recolor.apply`).
- Messages spec: 4 more reply-line checks.

## [1.16.1] - 2026-11-02

### Removed
- `UI/Components/AvatarRing` and the avatar rings: Studio doesn't expose the
  colour it gives each collaborator, so the plugin can't match it. The
  1.16.0 What's New entry no longer mentions them.

## [1.16.0] - 2026-11-02

### Added
- `UI/Components/AvatarRing`: a ring in the person's chat name colour
  (`UsernameColors`) around message avatars (`Author.attach`) and sidebar
  DM avatars. Studio doesn't expose its own collaborator colours.
- Unread: `Conversations.firstUnread(id)`; `ui.showUnreadDivider(timestamp?)`
  draws a red NEW line before the first unread message when a conversation
  opens (`unread.new` in every language); the sidebar badge pops when its
  count goes up; the widget title becomes "(n) Team Chat <version>".
- Social spec (19 checks; 16 after 1.16.1).

### Fixed
- Typing indicator in DMs: typing entries carry a `Conversation` attribute;
  `setTyping(active, conversation?)`, `getTypingUsers(conversation?)` and
  `simulateTyping(name, seconds, conversation?)` follow it. The controller
  no longer limits typing to the team chat.
- Delete: `ChatState.deleteMessage` refuses others' messages and the context
  menu hides Delete (and its divider) on them (`canDelete`).

## [1.15.2] - 2026-11-02

### Added
- `UI/ChatWindow/TeamCreateNotice`: "Only you can see this chat" under the
  header while the place is unpublished or not in Team Create (checked by
  `game.PlaceId ~= 0 and Players.LocalPlayer ~= nil`; Studio adds editors to
  Players only in Team Create). Re-checks when Players or the PlaceId
  change; the message list and empty state start below it (`topSpace()`).
- `teamCreate.title` / `teamCreate.text` in every language; Window spec
  checks (7).

## [1.15.1] - 2026-11-02

### Added
- Translated the rest of the plugin: the Badges, Checkout, About, New
  message, Create a Poll and What's New windows (`ModalKit.addTextKey`),
  notifications, badge names and descriptions (`badge.<id>.name`), rank
  names (`rank.<n>`), `/help` and the registry's errors, every command's
  description and argument hints (`command.<name>.description` /
  `.arg.<arg>`) and every command reply (`reply.*`; usage lines share
  `commands.usage`).
- `Language.tOr(key, default)`: text with its own English source (command
  descriptions, badge names) falls back to that source.
- `Language.pick(value)`: What's New `text` and `title` can be
  `{ en = ..., nl = ... }`; the 1.12.4-1.15.1 notes are translated, older
  notes stay English.
- Language spec: 5 more checks (replies, descriptions, `pick`).

## [1.15.0] - 2026-11-02

### Added
- `Core/Language`: translations with an English fallback. `t(key, vars)`
  fills `{name}` placeholders; `bind(instance, property, key, vars?,
  transform?)` keeps a property translated; `set(code)` ("auto" follows
  Studio's `RobloxLocaleId`) saves the choice and re-labels; `changed` fires
  for text built by code. Initialized in `App` after `Settings`.
- `Config/Languages`: en, nl, de, es, fr, pt, found automatically.
- Settings > Language (dropdown, Auto + each language in its own name).
- Translated: the Settings page (titles, descriptions, sections, choices,
  search), the Settings tabs and window titles, the right-click and attach
  menus, the message box, reply/edit bar, empty states, typing indicator
  and the sidebar.
- Language spec (24 checks); test copies run in English.

### Changed
- Settings `SECTIONS` no longer hold English titles/descriptions; they come
  from `setting.<key>.title` / `.description`. Dropdown `labels` can be a
  function. Context menu items take a translation key.

## [1.14.0] - 2026-11-02

### Changed
- `Config/Changelog` is grouped Minecraft-style: main versions (`x.0.0`,
  with title and date) hold their `x.y.z` updates in `updates`.
- What's New: main versions are the tabs (labelled `1.0`), updates are
  foldable cards (version, date, title; notes when unfolded). Opening it for
  a version unfolds that update; `hasNotesFor` searches the updates.
- `ChangelogView.find(changelog, version)` replaces `findIndex`; the version
  line in `render` is optional.
- Changelog spec (7 checks); the Badges spec adds its own test badge.

## [1.13.1] - 2026-11-01

### Removed
- The in-Studio purchase window (`Badges.promptPurchase`, the checkout's
  Studio **Buy**). `PromptGamePassPurchase` runs without an error in Edit
  mode but Roblox never shows the window there, and in Studio Play mode
  purchases are test purchases that don't grant the real pass. The checkout
  is back to the Roblox.com flow (Continue to Roblox + `watchPurchase`).

## [1.13.0] - 2026-11-01

### Added
- `Badges.promptPurchase(userId, badgeId, onStatus)`: shows Roblox's
  purchase window in Studio with `MarketplaceService:PromptGamePassPurchase`
  (Team Create gives the Studio user a Player) and reports `owned` /
  `cancelled` from `PromptGamePassPurchaseFinished`; returns false when it
  can't (no game pass or player).
- Checkout: **Buy** (with the price) uses it; **Buy on Roblox.com** is the
  website fallback; new states for the window being open, cancelled or
  unavailable.
- Game pass IDs for Premium, Supporter, Star and Diamond (set by the owner).

### Changed
- Badges spec sets a badge's pass to 0 in its own copy to test "Coming soon".

## [1.12.4] - 2026-11-01

### Fixed
- Sliders: the press lands on the track, so the release goes there too; the
  drag now ends on the track's InputEnded, the press input's End state or
  the drag layer's InputEnded (it needed a second click before).
- `SettingsTabs` no longer retitles every page "Settings"; pages keep their
  own titles and icons.
- Focus leaving the widget closes only menus; modals stay open. The
  focus-loss grace logic in `SettingsDialog` is gone. `ModalKit` click
  catchers ignore clicks inside `modal.insideGuis` (the Settings nav).
- Toggle squish and slider knob grow only run with animations on.
- Message images are sized to their aspect ratio (GIF frame size or the
  asset's size, read once via EditableImage and cached), within 200 x
  `MAX_IMAGE_HEIGHT`, instead of being letterboxed in a fixed box.
- Specs: per-tab titles, focus loss, image sizing (244 checks).

## [1.12.3] - 2026-11-01

### Fixed
- Modals live on their own full-panel layer (`Modals` in the widget), so the
  backdrop dims the sidebar too and windows center in the whole panel; they
  were inside the chat area before.
- The sidebar overlay raised some elements twice (rows moved between holders
  fire DescendantAdded again), putting them above dialogs. Each element's own
  ZIndex is now kept in a `BaseZ` attribute, so raising is idempotent.
- Tests: the backdrop covers the whole plugin; sidebar ZIndexes stay below
  dialogs after re-rendering (241 checks).

## [1.12.2] - 2026-11-01

### Changed
- `Constants.TOOLTIP_DELAY` is 0.3 s.
- Toasts live only in the plugin panel (bottom-centre of the widget); the
  CoreGui ScreenGui for Studio's 3D view is gone.
- `Theme.PALETTES` follow Roblox's dark and light themes (#335FFF blue,
  near-black / white surfaces, Roblox grays).
- Toggle switches: the knob springs across (pop preset), stretches while
  pressed and the track brightens on hover. Fixed: the save after a click
  called `set` without animation and cut the slide short; `set` on all
  controls now ignores unchanged values.
- Tests: the harness and Foundations spec replace any `LOG_LEVEL` value.

## [1.12.1] - 2026-11-01

### Changed
- `ModalKit` sizes every modal's card: width 0.9 of the panel kept between
  300 and 520px (minus `modal.reservedWidth`, e.g. the Settings nav), height
  from its content kept between `minHeight` (default 200) and 540px; below
  the panel's own size it shrinks to fit. `modal.refit()` after changing
  them. The UISizeConstraint is gone.
- The Settings window uses one height (540px, or the panel's) on every tab.
- ModalSize spec (9 checks).

## [1.12.0] - 2026-11-01

### Added
- `UI/Components/Controls`: setting cards (title, control slot, optional
  full-width row, divider, description), toggle switches, sliders (drag via a
  full-panel catcher in the dialog overlay; `dragTo`) and dropdowns (list in
  the overlay so the scrolling page can't clip it; flips up near the bottom).
- Notification duration preference (2-10 s) used by toasts.
- `Constants.TOOLTIP_DELAY` (1 s): badge tooltips (`Tooltip.show`, with an
  `immediate` flag) and sidebar tooltips wait for it; leaving cancels.
- Window API `applySetting` / `getSetting` / `getSettingControls`; the
  harness's `clickSetting` became `setSetting(key, value)`.
- Settings spec (23 checks).

### Changed
- `SettingsDialog` rebuilt from a `SECTIONS` list (Appearance, Chat,
  Notifications) with a search box; `set(key, value)` / `get(key)`.
- Message text size is a number (11-20 px); saved names (Small, Default,
  Large) still load. `Messages.setTextSize` takes a number or a name.

## [1.11.0] - 2026-11-01

### Added
- `UI/Animation`: the animation controller (presets quick / smooth / pop /
  exit, `tween`, `fadeIn` / `fadeOut` over a GUI's transparencies, `popIn` /
  `popOut` with a UIScale, `slideIn`); Settings > Animations turns it off.
  Used by modals (backdrop fade + pop), the sidebar (width, chat position,
  scrim, hovers), the context menu, autocomplete, typing and reply bars,
  live messages, toasts and the Settings nav.
- `UI/Components/Toasts`: notifications at the bottom-centre of the chat
  area, or of Studio's 3D view (a ScreenGui in CoreGui) while the panel is
  closed. `ui.notify(toast)`.
- `Conversations.onMessage(id, message)`; PluginController notifies for new
  messages outside the open conversation (Settings > Notifications: All,
  DMs only, Off). Purchases notify too.
- Polish spec (22 checks). Test boots default to animations off.

### Changed
- `SettingsTabs`: the tabs are a nav column on the left of the window (icons
  only below 460px). `ModalKit` modals animate and take `instantNext`
  (tab switches swap pages without re-opening); `isVisible` is false as soon
  as `close()` is called.

## [1.10.2] - 2026-11-01

### Changed
- One Settings button in the sidebar footer (plus the toggle). Settings,
  Badges, What's New and About are pages of one window: `UI/Dialogs/SettingsTabs`
  adds a tab row under each dialog's title (all titled "Settings") and opening
  a tab closes the others. The dialogs expose `modal`; the window API's
  `openSettings` / `openBadges` / `openChangelog` / `openAbout` /
  `closeSettings` / `toggleSettings` go through the tabs.

## [1.10.1] - 2026-11-01

### Changed
- Narrow panel + expanded sidebar: the sidebar lies over the chat (drawer)
  instead of the chat being scaled down. Its ZIndexes are raised by
  `ConversationList.OVERLAY_Z_OFFSET` (above chat content, below dialogs),
  a scrim dims the chat and closes the sidebar on click, and picking a
  conversation closes it. The UIScale and `Pointer.scaleOf` are gone.
- Harness: `narrow` boot option; exposes the sidebar toggle and scrim.
- Sidebar spec (11 checks).

## [1.10.0] - 2026-11-01

### Added
- `Services/Profiles`: display names and verified flags (batched
  `GetUserInfosByUserIdsAsync`, cached, `changed` signal). `Services/Badges`
  takes the verified flag from it and gains `watchPurchase` (polls game pass
  ownership after Buy, 10 minutes).
- Display names (Settings > Names) in message headers, reply lines, the DM
  header (with `@username`), the sidebar and the New message dialog; the
  verified badge next to verified names in all of them.
- `UI/Components/BadgeIcons` (verified = `verified-backplate` in
  `Badges.VERIFIED_COLOR` + white `verified-check`; `verified-mono` inline),
  `UI/Preferences` (names, badges, badge tooltips, link previews, typing
  indicator), `UI/Dialogs/PurchaseDialog` (checkout).
- Premium badge (`crown`, game pass id to fill in).
- Commands: `/say` (Admin; stores `SaidBy`), `/me`, `/shrug`, `/roll`,
  `/coinflip`, `/whois`, `/select`, `/stats`, `/about`, `/badges`.
  `MessageStore.sendMessageAs`; command context `openAbout` / `openBadges`.
- `Icons.ALL`: all 781 Builder Icons names.
- First install (nothing saved yet, `Settings.firstRun`) opens About instead
  of What's New.
- Profiles spec; harness records the checkout button and stubs `Browser.open`.

### Changed
- Narrow panel + expanded sidebar: the chat keeps its collapsed width and is
  scaled down with a UIScale (`Pointer.scaleOf` fixes context menu, link and
  jump-to-reply positions).
- Version in the widget title; the header shows title, verified badge and
  subtitle.
- System messages are "System" again (code icon, no badges).
- Badge tooltips show just the name, can be turned off, and live in the
  widget (unscaled) so they line up with the badge.
- Reply lines re-render when names or verified flags arrive
  (`Shared.renderReplyLabel`).

## [1.9.1] - 2026-11-01

### Added
- Badge tooltips: hovering a badge next to a name shows its name and
  description above it (`UI/Components/Tooltip`, `Author.tooltip`,
  `Author.tooltipText`). Hidden when the messages scroll.

### Changed
- The verified badge is the `verified` icon from `Config/Icons`
  (`circle-check`, filled) in `Config/Badges.VERIFIED_COLOR`, instead of the
  `U+E000` glyph. `RichText.badgeIcon` picks a badge's icon, fill and color.
- The author header is a row of `AuthorLabel` (name), `Badges` (one icon
  label per badge) and `TimeLabel`; `RichText.buildAuthor` is gone.

## [1.9.0] - 2026-11-01

### Added
- Badges next to names: Roblox Verified (`UserService:GetUserInfosByUserIdsAsync`,
  drawn with the `U+E000` verified glyph), custom badges per user and badges
  sold as game passes (`MarketplaceService:UserOwnsGamePassAsync`).
  `Config/Badges` (definitions, `ORDER`, `USERS`), `Services/Badges` (cached,
  batched lookups, `changed` signal, `getStore`, `purchaseUrl`),
  `RichText.buildBadges`, `Author.getBadges`, window API `setBadgeProvider` /
  `setBadgeHandlers` / `refreshBadges` / `openBadges` / `openAbout`.
- `UI/Dialogs/BadgesDialog` (your badges, store with Buy / Owned / Coming
  soon, Refresh) and `UI/Dialogs/AboutDialog` (info, disclaimer, terms, data);
  sidebar buttons for both. `ModalKit.addText` / `recolorText`.
- Command argument panel: typing `/command ` lists its arguments (name,
  optional pill, description) with the one being typed highlighted
  (`Autocomplete.createArgItem`, `setHint`).
- Command `Args` can be tables `{ name, description, optional }`; every
  command now uses them. `getCommandList` returns `args` and `usage`.
- Badges spec (24 checks).

### Changed
- System messages show as "Roblox" (verified, Roblox logo avatar); the stored
  sender is still "System". Reply lines use the same display name.
- `RichText.buildAuthor` takes options (`displayName`, `nameColor`, `badges`).
- `/help <command>` builds its usage line from the argument names.

## [1.8.0] - 2026-11-01

### Added
- Editing your own text messages: "Edit Message" in the right-click menu
  (only for messages whose `SenderId` is yours), edit in the composer with an
  "Editing message" bar, save with Send/Enter, cancel with the bar's ×.
- `MessageStore.editMessage` (checks ownership and type, sets `Content` and
  `EditedAt`), `RichText.buildBody` (adds "(edited)"), `Messages.setBody`,
  window API `setCurrentUserId` / `getEditingMessage` / `clearEditing` /
  `updateMessage`.
- PluginController watches each message's `Content` and re-renders edits
  live (text, links, link previews).
- Editing spec (15 checks).

### Changed
- `LinkHelper.attach` always listens (links can appear after an edit).
- Test runs no longer print to Output.

## [1.7.1] - 2026-11-01

### Changed
- Reply lines: a thin curved line from the reply's avatar up to the reply, a
  mini avatar of the original author, then the name (half opacity) and the
  preview. Polls and announcements (no avatar) keep the reply arrow.
- Replies store `ReplyToSenderId`; older replies take the id from the original
  message when it's loaded.

## [1.7.0] - 2026-11-01

### Changed
- Text and file messages use a Discord-style layout: a round Roblox headshot
  (`UI/Messages/Author`), a header with the name in its color and the time
  (`RichText.buildAuthor`, `TimeFormat.formatPlain`), and the message below.
  Content is indented so images, embeds and file cards line up under the name.
- System messages show a code-icon badge; senders without a user id show
  their initial. Image-only messages hide the empty text line.
- `ui.addMessage` / `ui.addFileMessage` take an optional `senderId` (last
  argument); the controller passes it from the message folder.
- `Util/Links` lays out only the message text (the author is in the header).

## [1.6.0] - 2026-11-01

Restructure of the whole plugin. Behavior is unchanged except where listed
under Fixed and "Behavior changes".

### Added
- Files on disk with a Rojo project (`default.project.json` builds the plugin,
  `dev.project.json` live-syncs it and the tests into Studio).
- Tooling: `aftman.toml` (Rojo 7.7.1, StyLua 2.0.2, Selene 0.28), `stylua.toml`,
  `selene.toml`, `.gitignore`, `.gitattributes`, git history.
- `docs/AUDIT.md`, `docs/ARCHITECTURE.md`, `README.md`, this file.
- Foundations: `Util/Janitor`, `Util/Signal`, `Core/Logger` (levels, set in
  `Config/Constants.LOG_LEVEL`), `Core/Settings` (safe plugin settings, JSON,
  per-place keys), `Core/Identity` (current user, resolved once),
  `Core/Browser`, `Services/History` (ChangeHistoryService recordings).
- `Util/Duration`, `Util/Links`.
- `tests/`: Studio harness (boots an isolated copy of the plugin), runner and
  specs (Foundations, Services, Messages, Smoke: 51 checks).
- `tools/`: Studio export importer, migration script, static analyzer.

### Changed
- New layout: `Config`, `Util`, `Core`, `Services`, `Commands`, `Controllers`,
  `UI`, with one-directional dependencies (see ARCHITECTURE). The entry script
  only bootstraps `App`.
- `UI/ChatUI` (3,186 lines) split into `UI/ChatWindow/{init, Header,
  ContextMenu, TypingBar, Pointer}` and `UI/Messages/{TextMessage,
  Announcement, PollMessage, FileMessage, Recolor, Shared}`.
- `Core/Lifetime` rebuilt on Janitor; tracks timers and the typing animation.
- All plugin settings go through `Core/Settings`; every setting key lives in
  `Config/Constants`.
- Rank names moved to `Config/Constants.RANK_NAMES` (the UI no longer
  requires services).
- `/whisper`, `/claim`, `/goto` and `/waypoint` use the new services.
- Logging: `[Team Chat]`/`[Team Chat/<scope>]` prefixes; the load message is
  "Loaded v<version>. Plugin made by @...".
- Formatted with StyLua; Selene reports 0 warnings.

### Fixed
- `/goto` never worked: camera sharing was never started and serialized only
  the first CFrame component. It now starts with the plugin and publishes at
  most once a second, only when the camera moves.
- Clicking links inside message text never worked (the hit-test called
  `GetTextBoundsAsync` with invalid arguments).
- Admin data keyed by user id (ranks, mutes, bans, lists, warnings) was lost
  on reload because JSON turns numeric keys into strings.
- `Config/AllowedUsers` was never applied (`ipairs` over a dictionary).
- RichText escaping now handles `&`.
- `/timer` reminders and the typing-dots animation kept running after the
  plugin unloaded.
- `setVisible` read an undefined global (`visibilityCallback`).

### Removed
- 12 unused modules (kept in `legacy/`): `UI/Components/{AttachMenu,
  DropOverlay, EmptyState, FileCard, InputBar, MessageItem, PollCard,
  PollDialog, PreviewBar, SystemMessage}`, `Networking/Chat/MessageEvents`,
  `Config/Types`.
- Dead state in the context menu (eight target fields only ever written).

### Behavior changes
- Your camera position is now shared with collaborators of the place (that is
  what `/goto` needs; it was the original intent of `StudioNetwork`).
- Claims work for instance names with any characters (attribute keys are
  sanitized more strictly; claims made before with names containing only
  letters, digits, `_`, `.` and spaces keep the same key).
- The right-click menu uses a rounded stroke instead of a square border.
- "Studio isn't signed in" is logged as info instead of a warning.
