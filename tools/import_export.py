"""Rebuilds a Studio export (chunked JSON returned by execute_luau) into a Rojo-style tree.

Usage: python tools/import_export.py <out_dir> <chunk files in order...>

Each chunk file contains "<<CHUNK n>>...<<END>>". The joined JSON is a list of
{ path, class, children, source?, attributes? } entries, one per instance.
"""
import json
import os
import re
import sys

LONG_PREFIX = "\\\\?\\"  # Windows: paths over 260 characters need \\?\


def long_path(path):
    full = os.path.abspath(path)
    if os.name == "nt" and not full.startswith("\\\\"):
        return LONG_PREFIX + full
    return full


def main():
    out_dir, files = sys.argv[1], sys.argv[2:]
    parts = {}
    for path in files:
        with open(long_path(path), encoding="utf-8") as f:
            text = f.read()
        match = re.search(r"<<CHUNK (\d+)>>(.*)<<END>>", text, re.S)
        if not match:
            sys.exit(f"no chunk marker in {path}")
        parts[int(match.group(1))] = match.group(2)
    data = "".join(parts[i] for i in sorted(parts))
    print("assembled bytes:", len(data.encode("utf-8")), "chunks:", sorted(parts))
    items = json.loads(data)

    suffix = {"Script": ".server.luau", "LocalScript": ".client.luau", "ModuleScript": ".luau"}
    for item in items:
        target = os.path.join(out_dir, *item["path"].split("/"))
        cls = item["class"]
        if cls in suffix:
            if item["children"] > 0:
                os.makedirs(long_path(target), exist_ok=True)
                file_path = os.path.join(target, "init" + suffix[cls])
                meta_path = os.path.join(target, "init.meta.json")
            else:
                os.makedirs(long_path(os.path.dirname(target)), exist_ok=True)
                file_path = target + suffix[cls]
                meta_path = target + ".meta.json"
            with open(long_path(file_path), "w", encoding="utf-8", newline="\n") as f:
                f.write(item["source"])
            if item.get("attributes"):
                with open(long_path(meta_path), "w", encoding="utf-8", newline="\n") as f:
                    json.dump({"attributes": item["attributes"]}, f, indent=2)
        elif cls == "Folder":
            os.makedirs(long_path(target), exist_ok=True)
        else:
            print("unhandled class", cls, item["path"])
    print("items:", len(items))


if __name__ == "__main__":
    main()
