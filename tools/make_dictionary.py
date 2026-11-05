"""
Builds the spell check word list (src/Config/Dictionary/) from cspell's
English dictionary (@cspell/dict-en_us, MIT licence, see
src/Config/Dictionary/LICENSE.txt).

cspell ships the dictionary as a compressed trie (en_US.trie.gz, format
"TrieXv3"); this reads it, keeps the words that make sense in chat, and
writes them as Luau modules: one string each, a word per line, split so no
module gets too big for Studio's script editor.

The words are sorted and front-coded to halve the size: each line is a
digit (how many letters it shares with the word before it, 0-9) and the
rest of the word. "abandon", "abandoned" -> "0abandon", "7ed". Every
module starts again from 0. Util/SpellCheck decodes them.

Kept: words of letters (and apostrophes), no possessives ("cat's" is
checked as "cat"), and capitalised words only when their lowercase isn't
there too (names like "Amsterdam").

Usage (from the repository root):
    python tools/make_dictionary.py <path to en_US.trie.gz>

The VS Code extension "Code Spell Checker" includes it at
    ~/.vscode/extensions/streetsidesoftware.code-spell-checker-*/node_modules/@cspell/dict-en_us/en_US.trie.gz
or get it from npm: @cspell/dict-en_us.
"""

import gzip
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "Config", "Dictionary")
CHUNK = 150_000  # characters per module
ESCAPES = {"n": "\n", "r": "\r", "\\": "\\"}
BACK_DIGITS = "<23456789"


class Node:
    __slots__ = ("children", "eow")

    def __init__(self):
        self.children = {}
        self.eow = False


def read_trie(text: str) -> Node:
    """
    Reads a cspell TrieXv3 file (cspell-trie-lib importExportV3):
      a character      add it as a child and move into it ("\\" escapes one)
      $                the current node ends a word; go back one step
      < or 2..9        right after $ or <: go back 1, or (digit - 1) more steps
      #<n>;            the current node is node n (base `base`) seen earlier:
                       nodes are numbered in the order they got a first child,
                       after the root (0) and the shared end-of-word leaf (1)
    """
    lines = text.split("\n")
    header = re.search(r"^TrieXv3\nbase=(\d+)$", "\n".join(lines[1:3]), re.M)
    if not header:
        sys.exit("not a TrieXv3 file")
    base = int(header.group(1))
    data = lines[lines.index("__DATA__") + 1 :]

    root = Node()
    eow_leaf = Node()
    eow_leaf.eow = True
    refs = [root, eow_leaf]
    path = [root]  # path[-1] is the cursor; path[i] is reached by edges[i - 1]
    edges = []

    def back(steps: int):
        for _ in range(steps):
            path.pop()
            edges.pop()

    backing = False  # right after $ or <: digits are step counts
    escaping = False
    ref = None  # the digits of a #reference while reading one
    for line in data:
        for char in line:
            if ref is not None:
                if char == ";":
                    target = refs[int(ref, base) + 1]
                    path[-2].children[edges[-1]] = target
                    path[-1] = target
                    ref = None
                else:
                    ref += char
                continue
            if escaping:
                char = ESCAPES.get(char, char)
                escaping = False
            else:
                if backing:
                    if char in BACK_DIGITS:
                        back(1 if char == "<" else int(char) - 1)
                        continue
                    backing = False
                if char == "$":
                    path[-1].eow = True
                    back(1)
                    backing = True
                    continue
                if char == "<":
                    back(1)
                    backing = True
                    continue
                if char == "#":
                    ref = ""
                    continue
                if char == "\\":
                    escaping = True
                    continue
            node = path[-1]
            if not node.children and node is not root:
                refs.append(node)
            child = node.children.get(char)
            if child is None:
                child = Node()
                node.children[char] = child
            path.append(child)
            edges.append(char)
    return root


def words(root: Node):
    stack = [(root, "")]
    while stack:
        node, prefix = stack.pop()
        if node.eow and prefix:
            yield prefix
        for char, child in node.children.items():
            stack.append((child, prefix + char))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    text = gzip.open(sys.argv[1]).read().decode("utf-8")
    found = set(words(read_trie(text)))
    print(f"{len(found)} words in the dictionary")

    # Letters and apostrophes only (cspell has entries with digits, dots and
    # "~" case variants); no possessives; names only when not a plain word too
    usable = {w for w in found if re.fullmatch(r"[A-Za-z][A-Za-z']*", w) and len(w) <= 24 and not w.endswith("'s")}
    lower = {w for w in usable if w.islower()}
    kept = sorted(lower | {w for w in usable if not w.islower() and w.lower() not in lower})
    print(f"{len(kept)} kept")

    os.makedirs(OUT, exist_ok=True)
    for name in os.listdir(OUT):
        if re.fullmatch(r"Words\d+\.luau", name):
            os.remove(os.path.join(OUT, name))
    chunks, current, size = [], [], 0
    for word in kept:
        if size + len(word) + 1 > CHUNK and current:
            chunks.append(current)
            current, size = [], 0
        current.append(word)
        size += len(word) + 1
    if current:
        chunks.append(current)
    for index, chunk in enumerate(chunks, 1):
        lines, previous = [], ""
        for word in chunk:
            shared = 0
            while shared < 9 and shared < len(previous) and shared < len(word) and previous[shared] == word[shared]:
                shared += 1
            lines.append(f"{shared}{word[shared:]}")
            previous = word
        path = os.path.join(OUT, f"Words{index}.luau")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("-- Generated by tools/make_dictionary.py from @cspell/dict-en_us (MIT). Don't edit.\n")
            f.write("return [==[\n" + "\n".join(lines) + "\n]==]\n")
    print(f"wrote {len(chunks)} modules to {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
