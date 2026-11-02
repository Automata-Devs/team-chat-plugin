"""One-off migration: copies legacy/TeamChatPlugin into the new src/ layout and
rewrites every `require(script...)` path so it points at the module's new home.

Usage: python tools/migrate.py            (writes src/, refuses if src/ exists)
       python tools/migrate.py --map      (prints the migration map only)

The mapping below is the source for the migration table in docs/ARCHITECTURE.md.
"""
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(__file__))
from analyze import load_tree, long_path, REQUIRE  # noqa: E402

ROOT = "TeamChatPlugin"
LEGACY = os.path.join("legacy", ROOT)
OUT = "src"

# Old instance path (after TeamChatPlugin/src/) -> new path (after TeamChatPlugin/).
# Exact entries win over prefix entries (marked with a trailing "/").
MAPPING = {
    "Commands/CommandHandler": "Commands/Registry",
    "Commands/Template": "Commands/_Template",
    "Commands/": "Commands/",
    "Config/PluginConfig": "Config/Constants",
    "Config/Theme": "Config/Theme",
    "Config/Icons": "Config/Icons",
    "Config/Changelog": "Config/Changelog",
    "Config/AllowedUsers": "Config/AllowedUsers",
    "Core/Lifetime": "Core/Lifetime",
    "Core/PluginController": "Controllers/PluginController",
    "Core/MessageController": "Controllers/MessageController",
    "Networking/PlaceStorage": "Core/PlaceStorage",
    "Networking/ChatNetwork": "Services/Chat",
    "Networking/Chat/ChatState": "Services/Chat/ChatState",
    "Networking/Chat/MessageStore": "Services/Chat/MessageStore",
    "Networking/Chat/PollManager": "Services/Chat/Polls",
    "Networking/Chat/TypingIndicator": "Services/Chat/Typing",
    "Networking/Chat/Conversations": "Services/Chat/Conversations",
    "Networking/Chat/VersionHistory": "Services/Chat/VersionHistory",
    "Networking/AdminNetwork": "Services/Admin",
    "Networking/Admin/AdminState": "Services/Admin/AdminState",
    "Networking/Admin/RankManager": "Services/Admin/Ranks",
    "Networking/Admin/ModerationManager": "Services/Admin/Moderation",
    "Networking/Admin/UserResolver": "Services/Admin/UserResolver",
    "Networking/StudioNetwork": "Services/StudioCollab",
    "Utils/UsageTracker": "Services/Usage",
    "Utils/LinkHelper": "UI/LinkHelper",
    "Utils/RichTextHelper": "Util/RichText",
    "Utils/TimeFormatter": "Util/TimeFormat",
    "Utils/EmojiData": "Util/EmojiData",
    "Utils/GifDecoder": "Util/GifDecoder",
    "Utils/UsernameColors": "Util/UsernameColors",
    "UI/ChatUI": "UI/ChatWindow",
    "UI/ModalKit": "UI/Dialogs/ModalKit",
    "UI/SettingsDialog": "UI/Dialogs/SettingsDialog",
    "UI/CreatePollDialog": "UI/Dialogs/CreatePollDialog",
    "UI/ChangelogDialog": "UI/Dialogs/ChangelogDialog",
    "UI/ChangelogView": "UI/Dialogs/ChangelogView",
    "UI/NewMessageDialog": "UI/Dialogs/NewMessageDialog",
    "UI/Components/AttachmentCards": "UI/Components/AttachmentCards",
    "UI/Components/AudioPlayback": "UI/Components/AudioPlayback",
    "UI/Components/Autocomplete": "UI/Components/Autocomplete",
    "UI/Components/ConversationList": "UI/Components/ConversationList",
    "UI/Components/GifPlayer": "UI/Components/GifPlayer",
    "UI/Components/MediaFocus": "UI/Components/MediaFocus",
    "UI/Embeds/": "UI/Embeds/",
    "Packages/": "Packages/",
}

# Not migrated (kept in legacy/ only); see docs/AUDIT.md H5.
REMOVED = {
    "Networking/Chat/MessageEvents",
    "Config/Types",  # replaced by src/Types.luau
    "UI/Components/AttachMenu",
    "UI/Components/DropOverlay",
    "UI/Components/EmptyState",
    "UI/Components/FileCard",
    "UI/Components/InputBar",
    "UI/Components/MessageItem",
    "UI/Components/PollCard",
    "UI/Components/PollDialog",
    "UI/Components/PreviewBar",
    "UI/Components/SystemMessage",
}


def map_path(old):
    """'Networking/ChatNetwork' -> 'Services/Chat' (None when removed)."""
    if old in REMOVED:
        return None
    if old in MAPPING:
        return MAPPING[old]
    for prefix, target in MAPPING.items():
        if prefix.endswith("/") and old.startswith(prefix):
            return target + old[len(prefix):]
    raise SystemExit(f"no mapping for {old}")


def new_inst(old_inst):
    """Instance tuple in the legacy tree -> instance tuple in the new tree."""
    if old_inst == (ROOT,):
        return (ROOT,)
    if old_inst[:2] != (ROOT, "src") or len(old_inst) < 3:
        raise SystemExit(f"unexpected instance {old_inst}")
    mapped = map_path("/".join(old_inst[2:]))
    return None if mapped is None else (ROOT,) + tuple(mapped.split("/"))


def require_expr(from_inst, to_inst):
    """Shortest script.Parent... expression from module `from_inst` to `to_inst`."""
    common = 0
    while common < min(len(from_inst), len(to_inst)) and from_inst[common] == to_inst[common]:
        common += 1
    ups = len(from_inst) - common
    return "script" + ".Parent" * ups + "".join("." + name for name in to_inst[common:])


def old_target(from_inst, expr):
    path = list(from_inst)
    for token in re.finditer(r"\.Parent|\.([A-Za-z_][A-Za-z0-9_]*)|:WaitForChild\(\"([^\"]+)\"\)", expr[len("script"):]):
        if token.group(0) == ".Parent":
            path.pop()
        else:
            path.append(token.group(1) or token.group(2))
    return tuple(path)


def out_file(inst, is_entry, has_children):
    parts = list(inst[1:])
    if is_entry:
        return os.path.join(OUT, "init.server.luau")
    if has_children:
        return os.path.join(OUT, *parts, "init.luau")
    return os.path.join(OUT, *parts) + ".luau"


def main():
    modules = load_tree("legacy")
    new_insts = {old: new_inst(old) for old in modules}
    kept = {old: new for old, new in new_insts.items() if new is not None}
    # A module becomes a folder (init.luau) when anything kept maps below it.
    parents = {new[:i] for new in kept.values() for i in range(1, len(new))}

    if "--map" in sys.argv:
        for old, new in sorted(new_insts.items()):
            print("/".join(old[1:]) or "(entry)", "->", "removed" if new is None else "/".join(new[1:]) or "(entry)")
        return

    if os.path.exists(OUT):
        raise SystemExit("src/ already exists; delete it first to re-run the migration")

    manual = []
    for old, file_path in sorted(modules.items()):
        new = kept.get(old)
        if new is None:
            continue
        source = open(file_path, encoding="utf-8").read()

        def rewrite(match):
            target_old = old_target(old, match.group(1))
            target_new = kept.get(target_old)
            if target_new is None:
                manual.append(("/".join(new[1:]), "require of removed/unknown " + "/".join(target_old)))
                return match.group(0)
            return "require(" + require_expr(new, target_new) + ")"

        source = REQUIRE.sub(rewrite, source)
        for line_no, line in enumerate(source.splitlines(), 1):
            if "script.Parent" in line and "require(" not in line:
                manual.append(("/".join(new[1:]) or "(entry)", f"line {line_no}: {line.strip()}"))
        target = out_file(new, old == (ROOT,), new in parents)
        os.makedirs(long_path(os.path.dirname(target)), exist_ok=True)
        with open(long_path(target), "w", encoding="utf-8", newline="\n") as f:
            f.write(source)

    meta = os.path.join(LEGACY, "init.meta.json")
    shutil.copyfile(long_path(meta), long_path(os.path.join(OUT, "init.meta.json")))

    print(f"migrated {len(kept)} scripts, removed {len(modules) - len(kept)}")
    print("== review by hand ==")
    for where, what in manual:
        print(f"  {where}: {what}")


if __name__ == "__main__":
    os.chdir(os.path.join(os.path.dirname(__file__), ".."))
    main()
