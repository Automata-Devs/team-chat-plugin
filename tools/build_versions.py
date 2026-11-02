"""
Builds every released version of the plugin into src/build/, one file per
version: src/build/TeamChatPlugin<version>.rbxm.

A version is released when a commit changes `Version` in src/init.meta.json;
each one is built from that commit's sources. The working tree's version is
built too (so a version you haven't committed yet is saved). Files that
already exist are kept, except the working tree's, which is rebuilt.

Usage (from the repository root):
    python tools/build_versions.py           # build what's missing
    python tools/build_versions.py --all     # rebuild every version

Needs git and rojo (aftman: ~/.aftman/bin) on PATH.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "build")
META = "src/init.meta.json"


def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, capture_output=True, **kwargs).stdout


def rojo() -> str:
    found = shutil.which("rojo")
    if found:
        return found
    aftman = os.path.join(os.path.expanduser("~"), ".aftman", "bin", "rojo")
    for candidate in (aftman, aftman + ".exe"):
        if os.path.exists(candidate):
            return candidate
    sys.exit("rojo not found: install it with aftman")


def version_of(meta_json: bytes) -> str:
    return json.loads(meta_json)["attributes"]["Version"]


def released() -> dict:
    """{ version: commit } for every commit that changed the version, oldest first."""
    commits = run("git", "log", "--reverse", "--format=%H", "--", META).decode().split()
    versions = {}
    for commit in commits:
        version = version_of(run("git", "show", f"{commit}:{META}"))
        versions.setdefault(version, commit)  # the commit that released it
    return versions


def build(source_dir: str, version: str):
    target = os.path.join(OUT, f"TeamChatPlugin{version}.rbxm")
    project = {"name": "TeamChatPlugin", "tree": {"$path": "src"}}
    project_path = os.path.join(source_dir, "build_version.project.json")
    with open(project_path, "w", encoding="utf-8") as f:
        json.dump(project, f)
    # Older versions never had src/build; the working tree's must not include it
    shutil.rmtree(os.path.join(source_dir, "src", "build"), ignore_errors=True)
    subprocess.run([rojo(), "build", project_path, "-o", target], check=True, capture_output=True)
    print(f"built {os.path.relpath(target, ROOT)}")


def main():
    rebuild = "--all" in sys.argv
    os.makedirs(OUT, exist_ok=True)

    for version, commit in released().items():
        target = os.path.join(OUT, f"TeamChatPlugin{version}.rbxm")
        if os.path.exists(target) and not rebuild:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            archive = run("git", "archive", "--format=tar", commit, "src")
            with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
                tar.extractall(tmp, filter="data")
            build(tmp, version)

    # The working tree (may be a version that isn't committed yet)
    with open(os.path.join(ROOT, META), encoding="utf-8") as f:
        current = version_of(f.read().encode())
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copytree(
            os.path.join(ROOT, "src"),
            os.path.join(tmp, "src"),
            ignore=shutil.ignore_patterns("build"),
        )
        build(tmp, current)


if __name__ == "__main__":
    main()
