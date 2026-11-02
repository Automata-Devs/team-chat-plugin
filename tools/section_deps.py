"""Lists what a line range of a Luau file needs from the rest of the file.

Usage: python tools/section_deps.py <file> <first line> <last line>

  imports: names used in the range but declared (as locals) outside it
  exports: locals declared in the range that are used outside it
Rough regex analysis (good enough to plan an extraction, not a parser).
"""
import re
import sys

path, first, last = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
lines = open(path, encoding="utf-8").read().split("\n")


def strip(line):
    line = re.sub(r"--.*$", "", line)  # comments (rough: ignores -- inside strings)
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    line = re.sub(r"'(?:\\.|[^'\\])*'", "''", line)
    return line


DECL = re.compile(r"\blocal\s+function\s+([A-Za-z_]\w*)|\blocal\s+([A-Za-z_][\w\s,:<>?{}()\[\]\|\.\-]*?)(?:=|$)|^\s*function\s+([A-Za-z_]\w*)\s*\(")
IDENT = re.compile(r"(?<![\.:\w])([A-Za-z_]\w*)")


def declared(chunk):
    names = set()
    for line in chunk:
        line = strip(line)
        for match in DECL.finditer(line):
            if match.group(1):
                names.add(match.group(1))
            elif match.group(3):
                names.add(match.group(3))
            elif match.group(2):
                for part in match.group(2).split(","):
                    name = part.split(":")[0].strip()
                    if re.fullmatch(r"[A-Za-z_]\w*", name):
                        names.add(name)
    return names


def used(chunk):
    names = set()
    for line in chunk:
        names.update(IDENT.findall(strip(line)))
    return names


inside = lines[first - 1:last]
outside = lines[:first - 1] + lines[last:]
inside_decl, outside_decl = declared(inside), declared(outside)
print("imports:", " ".join(sorted((used(inside) - inside_decl) & outside_decl)))
print("exports:", " ".join(sorted(inside_decl & used(outside))))
