# Contributing to Team Chat

Thanks for helping! Translations, bug fixes and features are all welcome.

Team Chat is **source-available**: you can fork this repository to prepare a
contribution, but not to publish your own version. Please read
[LICENSE.md](LICENSE.md) before you start; **by opening a pull request you
agree to its contribution terms** (section 3): you wrote the work yourself,
and D3veloperHac may use it in Team Chat.

## Ways to help

| You want to… | Do this |
|---|---|
| Report a bug | Open an issue with the **Bug report** template |
| Suggest a feature | Open an issue with the **Feature request** template first, so we can agree on it before you build it |
| Add or fix a translation | Open a pull request (see below), or an issue with the **Translation** template if you'd rather send text |
| Report a security problem | Don't open an issue: see [SECURITY.md](SECURITY.md) |

## Translations

Languages live in `src/Config/Languages/`, one Luau module per language
(`en.luau`, `nl.luau`, …). **`en.luau` is the reference: it has every key.**

- **Fixing a translation:** edit the text in that language's file.
- **Adding a language:** copy `en.luau` to `<code>.luau` (an ISO language code
  like `it` or `pl`), set `code`, `name` (in the language itself, e.g.
  `Italiano`) and `englishName`, and translate every string. The plugin finds
  new languages automatically.
- **Keep every `{placeholder}` exactly as it is** (`{name}`, `{count}`, …), and
  keep `\n` line breaks.
- Keep command names (`/ban`), usernames and "Team Chat" untranslated.
- Text in `<b>…</b>` stays bold: translate the words inside, keep the tags.
- Keep it short where it's shown in buttons, tabs and badges.

The `Language` test spec checks that every language has every English key
with the same placeholders. `lang/*.json` are JSON copies for translation
tools; after changing a language file, run `python tools/lang_to_json.py` to
update them (or say in your pull request that you didn't, and it'll be done
for you).

## Code changes

### Setup

```bash
aftman install                  # Rojo, StyLua and Selene at the pinned versions
rojo serve dev.project.json     # then press Connect in Studio's Rojo plugin
```

Use a place you own for testing. Edit the files on disk, not the synced copies
in Studio.

### Before you open a pull request

```bash
stylua src tests                # format
selene src                      # lint: 0 errors, 0 warnings
```

Then run the tests in Studio's command bar:

```lua
print(require(game.ServerStorage.TeamChatTests.Runner).run())
```

Everything must pass. Add or update specs in `tests/Specs/` for what you
changed.

### Guidelines

- Follow the structure in `docs/ARCHITECTURE.md` (Config < Util < Core <
  Services < Commands, UI < Controllers).
- Match the surrounding code: naming, comment style, `--!strict` where the
  file uses it.
- Every text users see goes through `Language.t` with a key in **all**
  language files (English text is fine in the other files if you can't
  translate it; say so in the pull request).
- New slash commands: start from `src/Commands/_Template.luau`. Replies only
  the user needs use `ctx.addSystemMessage` / `ctx.addEmbed`; replies everyone
  should see pass `{ public = true }`.
- Don't add web requests to services other than Roblox, analytics or
  tracking. The [Privacy Policy](PRIVACY.md) promises there are none.
- Don't bump the version or edit `CHANGELOG.md` / `src/Config/Changelog.luau`;
  that's done when your change is released.
- One topic per pull request. Small pull requests get reviewed faster.

## Pull request review

Pull requests are reviewed by D3veloperHac. A pull request may be changed,
merged, credited or closed. Merged contributions ship in a future version of
the official plugin. Please be patient: this is a side project.

## Conduct

Be kind and constructive. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
