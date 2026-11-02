"""Static checks for a Rojo-style Luau tree.

Usage: python tools/analyze.py <root folder containing the plugin script folder>

Reports:
  - every `require(script...)` that doesn't resolve to a module
  - require cycles
  - modules nothing requires (excluding folders loaded dynamically)
  - counts of deprecated / risky API patterns per file
"""
import os
import re
import sys

LONG_PREFIX = "\\\\?\\"


def long_path(path):
    full = os.path.abspath(path)
    if os.name == "nt" and not full.startswith("\\\\"):
        return LONG_PREFIX + full
    return full


def load_tree(root):
    """Maps instance path tuples -> file path for every script."""
    modules = {}
    for dirpath, _, files in os.walk(long_path(root)):
        rel_dir = os.path.relpath(dirpath, long_path(root))
        parts = [] if rel_dir == "." else rel_dir.split(os.sep)
        for name in files:
            if not name.endswith(".luau") and not name.endswith(".lua"):
                continue
            base = re.sub(r"(\.server|\.client)?\.luau?$", "", name)
            inst = tuple(parts) if base == "init" else tuple(parts + [base])
            modules[inst] = os.path.join(dirpath, name)
    return modules


REQUIRE = re.compile(r"require\(\s*(script(?:\.Parent|\.[A-Za-z_][A-Za-z0-9_]*|:WaitForChild\(\"[^\"]+\"\))*)\s*\)")


def resolve(inst, expr, modules):
    """Resolves script.Parent.X:WaitForChild("Y") style paths from module `inst`."""
    path = list(inst)
    tokens = re.findall(r"\.Parent|\.([A-Za-z_][A-Za-z0-9_]*)|:WaitForChild\(\"([^\"]+)\"\)", expr[len("script"):])
    for token in re.finditer(r"\.Parent|\.([A-Za-z_][A-Za-z0-9_]*)|:WaitForChild\(\"([^\"]+)\"\)", expr[len("script"):]):
        if token.group(0) == ".Parent":
            if not path:
                return None
            path.pop()
        else:
            path.append(token.group(1) or token.group(2))
    return tuple(path)


def main():
    root = sys.argv[1]
    modules = load_tree(root)
    graph = {inst: set() for inst in modules}
    unresolved = []
    for inst, file_path in modules.items():
        source = open(file_path, encoding="utf-8").read()
        for match in REQUIRE.finditer(source):
            target = resolve(inst, match.group(1), modules)
            if target in modules:
                graph[inst].add(target)
            else:
                unresolved.append(("/".join(inst), match.group(1)))

    print("== unresolved requires ==")
    for item in unresolved:
        print("  ", *item)

    print("== cycles ==")
    state = {}
    stack = []

    def visit(node):
        state[node] = 1
        stack.append(node)
        for dep in graph[node]:
            if state.get(dep) == 1:
                cycle = stack[stack.index(dep):] + [dep]
                print("   " + " -> ".join("/".join(n[-2:]) for n in cycle))
            elif dep not in state:
                visit(dep)
        stack.pop()
        state[node] = 2

    for node in graph:
        if node not in state:
            visit(node)

    print("== never required (excluding Commands, loaded by folder scan) ==")
    required = set().union(*graph.values())
    for inst in sorted(modules):
        if inst not in required and "Commands" not in inst and len(inst) > 1:
            print("   " + "/".join(inst))

    patterns = {
        "wait(": r"(?<![\.\w])wait\(",
        "spawn(": r"(?<![\.\w])spawn\(",
        "delay(": r"(?<![\.\w])delay\(",
        "Instance.new(x, parent)": r"Instance\.new\(\s*\"[^\"]+\"\s*,",
        "_G": r"\b_G\b",
        "shared": r"(?<![\.\w])shared\.",
        "--!strict": r"^--!strict",
        "pcall": r"\bpcall\(",
        ".Changed/Connect": r":Connect\(",
        "Lifetime.connect": r"Lifetime\.connect\(",
        "ChangeHistoryService": r"ChangeHistoryService",
        "warn(": r"(?<![\.\w])warn\(",
        "print(": r"(?<![\.\w])print\(",
        "Font = Enum.Font": r"\.Font = ",
    }
    print("== pattern counts (total) ==")
    totals = {name: 0 for name in patterns}
    per_file = {}
    for inst, file_path in modules.items():
        source = open(file_path, encoding="utf-8").read()
        for name, pattern in patterns.items():
            count = len(re.findall(pattern, source, re.M))
            totals[name] += count
            if count and name in ("wait(", "spawn(", "delay(", "Instance.new(x, parent)", "_G", "shared", "ChangeHistoryService"):
                per_file.setdefault(name, []).append(("/".join(inst[-2:]), count))
    for name, count in totals.items():
        print(f"   {name:28} {count}")
    for name, files in per_file.items():
        print(f"   {name}: " + ", ".join(f"{f}({c})" for f, c in files))
    strict = sum(1 for inst, fp in modules.items() if re.search(r"^--!strict", open(fp, encoding="utf-8").read(), re.M))
    print(f"== {strict}/{len(modules)} files are --!strict ==")


if __name__ == "__main__":
    main()
