# Changelog

Developer-facing history of the codebase. User-facing notes ("What's New")
are in `src/Config/Changelog.luau`. Format: [Keep a Changelog](https://keepachangelog.com).

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
