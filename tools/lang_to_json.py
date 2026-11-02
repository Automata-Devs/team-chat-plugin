"""
Converts src/Config/Languages/<code>.luau to lang/<code>.json
({ code, name, englishName, strings }), keeping the key order.

Run from the repository root:  python tools/lang_to_json.py
"""
import glob, json, os, re

# A Lua string literal in double or single quotes
STRING = r'"((?:[^"\\\n]|\\.)*)"|\'((?:[^\'\\\n]|\\.)*)\''


def unescape(body: str) -> str:
    out, i = [], 0
    simple = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = body[i + 1]
        if nxt == "u" and body[i + 2] == "{":
            end = body.index("}", i)
            out.append(chr(int(body[i + 3:end], 16)))
            i = end + 1
        elif nxt == "x":
            out.append(chr(int(body[i + 2:i + 4], 16)))
            i += 4
        elif nxt.isdigit() and nxt != "0" or (nxt == "0" and i + 2 < len(body) and body[i + 2].isdigit()):
            m = re.match(r"\d{1,3}", body[i + 1:])
            out.append(chr(int(m.group(0))))
            i += 1 + len(m.group(0))
        elif nxt in simple:
            out.append(simple[nxt])
            i += 2
        else:
            raise ValueError("unknown escape \\" + nxt)
    return "".join(out)


def literal(m, first: int) -> str:
    body = m.group(first) if m.group(first) is not None else m.group(first + 1)
    return unescape(body)


def strip_comments(source: str) -> str:
    # Drop "--" comments outside strings (line by line, quote-aware)
    lines = []
    for line in source.split("\n"):
        out, quote, i = [], None, 0
        while i < len(line):
            c = line[i]
            if quote:
                out.append(c)
                if c == "\\":
                    out.append(line[i + 1])
                    i += 2
                    continue
                if c == quote:
                    quote = None
            elif c in "\"'":
                quote = c
                out.append(c)
            elif line.startswith("--", i):
                break
            else:
                out.append(c)
            i += 1
        lines.append("".join(out))
    return "\n".join(lines)


os.makedirs("lang", exist_ok=True)
for path in sorted(glob.glob("src/Config/Languages/*.luau")):
    source = strip_comments(open(path, encoding="utf-8").read())
    info = {}
    for field in ("code", "name", "englishName"):
        m = re.search(r"^\t" + field + r"\s*=\s*(?:" + STRING + ")", source, re.M)
        info[field] = literal(m, 1)
    body = source[source.index("strings = {"):]
    strings = {}
    for m in re.finditer(r"\[\s*(?:" + STRING + r")\s*\]\s*=\s*(?:" + STRING + ")", body):
        key = literal(m, 1)
        assert key not in strings, (path, key)
        strings[key] = literal(m, 3)
    expected = len(re.findall(r"^\t\t\[", body, re.M))
    assert len(strings) == expected, (path, len(strings), expected)
    info["strings"] = strings
    target = os.path.join("lang", info["code"] + ".json")
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        json.dump(info, f, ensure_ascii=False, indent="\t")
        f.write("\n")
    print(target, len(strings), "strings")
