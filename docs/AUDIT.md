# Audit: Team Chat plugin v1.5.1

Snapshot audited: the v1.5.1 export (in git history before 1.27.1; exported unchanged from
`ReplicatedStorage.TeamChatPlugin`, 112 scripts, 16,642 lines).
Tools: Selene 0.28 (`std = "roblox"`), `tools/analyze.py` (require graph,
cycles, dead modules, API patterns), manual review.

## How the project was built

- Lived only inside a Team Create place (`ReplicatedStorage.TeamChatPlugin`),
  installed with **Save as Local Plugin** (`%LOCALAPPDATA%/Roblox/Plugins/TeamChatPlugin.rbxmx`).
  No files on disk, no version control, no build, no lint/format.
- One `Script` (entry) + 111 `ModuleScript`s. No LocalScripts.
- Requires all use instance paths (`script.Parent...`). **No cycles, no unresolved requires.**
- Version: `Version` attribute on the entry script (read by `Config/PluginConfig`).

## Findings, by severity

### High

| # | Problem | Where |
|---|---------|-------|
| H1 | **God module.** `UI/ChatUI` is 3,186 lines: widget, header, sidebar wiring, context menu, message list, composer, attachments, autocomplete, theming and the whole public API in one closure. It already hit Luau's 200-local limit (worked around with `do` blocks and a shared table). Hard to change safely. | `UI/ChatUI` |
| H2 | **`/goto` has never worked.** `StudioNetwork.init` (camera sharing) is never called, and if it were: `local c = cf:GetComponents()` keeps only the first number, so `string.format` with 12 `%f` would error **every frame**, and it would write a replicated attribute on `RenderStepped` (per-frame Team Create traffic). | `Networking/StudioNetwork` |
| H3 | **Undefined variable.** `setVisible` reads `visibilityCallback` before its `local` is declared (Selene `undefined_variable`), so that call reads a nil global. No visible effect (a `widget.Enabled` listener also fires the callback), but it's a latent bug. | `UI/ChatUI:2983` |
| H4 | **Lifecycle is partial.** Only 22 connections go through `Core/Lifetime`; ~90 UI/service connections and `task.delay` timers (`/timer`) are never cleaned up. On plugin reload the old copy keeps timers and some listeners alive. Instances created in the widget aren't tracked. | many |
| H5 | **Dead code (~2,000 lines).** Never required: `UI/Components/{AttachMenu, DropOverlay, EmptyState, FileCard, InputBar, MessageItem, PollCard, PollDialog, PreviewBar, SystemMessage}` (older duplicates of code now inside ChatUI / AttachmentCards / CreatePollDialog), `Networking/Chat/MessageEvents` (only re-exported, no callers since DMs), `Config/Types` (no consumers). | see list |

### Medium

| # | Problem | Where |
|---|---------|-------|
| M1 | **Config ignored.** `AllowedUsers` is a dictionary `{[userId] = "Owner"}` but is read with `ipairs`, so it never grants anything. | `Networking/AdminNetwork` |
| M2 | **Moderation is local-only and not enforced.** Ranks, mutes, bans, black/whitelists and slowmode live in each user's own plugin settings and `canUserSend`/`getSlowmode` are never called. `kick` stores a permanent ban despite saying "temporary". (Documented; changing it would be a new feature.) | `Networking/Admin/*` |
| M3 | **Duplicated logic.** Current user resolved twice (2 web calls) in `ChatState` and `RankManager`; `parseDuration` copied in `/timer` and `/tempmute`; GetSetting/SetSetting + JSON + `pcall` boilerplate in 5 modules; theme detection in `ChatUI` and `SettingsDialog`; `toHex` in two places. | various |
| M4 | **Settings scattered.** 10 call sites use `plugin:GetSetting/SetSetting` directly; several keys are hard-coded outside `PluginConfig` (`TeamChatLastRead_v1`, `TeamChatReadSince_v1`, `TeamChatClosedDms_v1`, `TeamChatVersion_*`). | `Conversations`, `VersionHistory` |
| M5 | **No logging policy.** 13 bare `warn`/`print` calls, no levels, no way to silence debug output. | various |
| M6 | **Weak typing.** 61 of 112 scripts aren't `--!strict`; tables typed as `table`; no shared types. | most modules |
| M7 | **Hard-coded values.** 18 `Color3.fromRGB` outside the theme; sizes, timings and user-facing strings inline. | UI |
| M8 | **Internal API.** Links open with `StudioService:OpenInBrowser_DONOTUSE` (undocumented, may break); already has a clipboard fallback. | `Utils/LinkHelper` |
| M9 | **RichText escaping** handles `<`/`>` but not `&`, so text containing entities (e.g. `&lt;`) is shown decoded. | `Utils/RichTextHelper` |

### Low

| # | Problem |
|---|---------|
| L1 | Selene: 65 unused variables (mostly command `speaker`/`args`), 29 multiple statements per line, 4 shadowed variables (reply state declared twice in ChatUI). |
| L2 | Mixed comment styles (`--!` blocks used as doc comments), inconsistent indentation in a few functions, no formatter. |
| L3 | `Commands/Template` lives next to real commands and is skipped by name. |
| L4 | `ChangeHistoryService`: only `/waypoint` uses it. Chat data written to `ServerStorage.TeamChatData` is plugin state, not user content; see ARCHITECTURE "Undo policy". No command edits user instances. |

## Plugin-specific checks

| Check | Status |
|---|---|
| `plugin` global | Used only in the entry script, passed down. OK |
| Toolbar / buttons | Created once in `PluginController`; buttons synced to widget state (broken by H3). |
| DockWidgetPluginGui | Created once; old children cleared on reload. OK |
| `plugin.Unloading` | Connected to `Lifetime.stop`, which only covers tracked connections (H4). |
| ChangeHistoryService | See L4. |
| Selection | `/find`, `/claim` read/set selection. OK |
| GetSetting/SetSetting | Works, but scattered and keys not centralized (M4). |
| Studio-only APIs | `StudioService`, `PluginGuiService` used in a plugin context. OK. `OpenInBrowser_DONOTUSE` (M8). |
| Runtime-only APIs | None misused. `Sound`/`VideoFrame` replaced by `AudioPlayer`/`VideoPlayer` earlier (edit mode). |
| Deprecated APIs | No `wait`/`spawn`/`delay`/`Instance.new(x, parent)`, no `_G`/`shared` in plugin code. |
