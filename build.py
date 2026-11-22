#!/usr/bin/env python3
"""Pack the ADB Disabler module.

    python3 build.py

Writes ../dist/ADB-Disabler-<version>.zip, ready to flash.

The archive mirrors the module exactly: install.sh, service.sh, module.prop,
module.yaml and META-INF. Repository files (README, LICENSE, build.py itself)
stay out of the zip so its size matches the original module.

Executable bits matter more than anything else here. A service.sh packed as
0644 gets skipped by every manager, and the module reports a successful
install while doing nothing at all. Anything with a shebang, plus
update-binary, is stored 0755. The zip is reopened afterwards and every mode
is read back before this script claims success.
"""

from __future__ import annotations

import argparse
import os
import stat
import sys
import zipfile

SRC = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(os.path.dirname(SRC), "dist")

# Files that belong to the repository but not to the module image.
SKIP_FILES = {
    "build.py", "build.sh", ".gitignore", ".gitattributes",
    "LICENSE", "NOTICE",
    "README.md", "README_zh.md", "README_EN.md",
    ".DS_Store", "Thumbs.db", "desktop.ini",
}
SKIP_DIRS = {".git", ".github", "__pycache__", "out", "dist", ".idea", ".vscode"}

# install.sh has no shebang (it is sourced by the manager, not executed),
# so it needs to be listed explicitly. Original module shipped it 0755.
ALWAYS_EXEC = {
    "META-INF/com/google/android/update-binary",
    "install.sh",
}

EXEC_BITS = 0o755
FILE_BITS = 0o644

# Reproducible output: identical inputs produce byte-identical archives.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)


def die(msg: str) -> "NoReturn":
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def read_prop(name: str) -> str:
    path = os.path.join(SRC, "module.prop")
    if not os.path.isfile(path):
        die("module.prop not found next to build.py")
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith(name + "="):
                return line.split("=", 1)[1].strip()
    return ""


def has_shebang(path: str) -> bool:
    try:
        with open(path, "rb") as fh:
            return fh.read(2) == b"#!"
    except OSError:
        return False


def collect():
    """Yield (relative_path, absolute_path, mode) for everything going in."""
    for root, dirs, files in os.walk(SRC):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            if name in SKIP_FILES or name.endswith((".pyc", ".swp", ".bak", "~")):
                continue
            full = os.path.join(root, name)
            rel = os.path.relpath(full, SRC).replace(os.sep, "/")
            execable = rel in ALWAYS_EXEC or has_shebang(full)
            yield rel, full, EXEC_BITS if execable else FILE_BITS


def pack(zip_path: str, entries) -> int:
    count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for rel, full, mode in entries:
            info = zipfile.ZipInfo(rel, ZIP_EPOCH)
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(full, "rb") as fh:
                zf.writestr(info, fh.read())
            count += 1
    return count


def verify(zip_path: str, expected) -> list:
    bad = []
    with zipfile.ZipFile(zip_path) as zf:
        got = {i.filename for i in zf.infolist()}
        want = {rel for rel, _, _ in expected}

        for rel, _, mode in expected:
            if rel not in got:
                bad.append(f"{rel}: missing from archive")
                continue
            actual = (zf.getinfo(rel).external_attr >> 16) & 0o777
            if actual != mode:
                bad.append(f"{rel}: mode {oct(actual)}, expected {oct(mode)}")

        for extra in sorted(got - want):
            bad.append(f"{extra}: unexpected file in archive")

        try:
            corrupt = zf.testzip()
        except zipfile.BadZipFile:
            corrupt = "not a valid zip"
        if corrupt:
            bad.append(f"corrupt entry: {corrupt}")
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description="Build the ADB Disabler module zip.")
    ap.add_argument("-o", "--out", default=DEFAULT_OUT, help="output directory")
    ap.add_argument("--no-verify", action="store_true", help="skip the post-build check")
    args = ap.parse_args()

    mod_id = read_prop("id")
    version = read_prop("version")
    if not mod_id:
        die("module.prop has no id=")
    if not version:
        die("module.prop has no version=")

    entries = list(collect())
    if not entries:
        die("nothing to pack")

    required = {"module.prop", "install.sh", "service.sh"}
    present = {rel for rel, _, _ in entries}
    missing = sorted(required - present)
    if missing:
        die("required files missing: " + ", ".join(missing))

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    zip_path = os.path.join(out_dir, f"ADB-Disabler-{version}.zip")
    count = pack(zip_path, entries)

    print(f"ADB-Disabler-{version}.zip  {count} files  "
          f"{os.path.getsize(zip_path) / 1024:.1f} KiB")
    print(f"  {zip_path}")

    if args.no_verify:
        return 0

    bad = verify(zip_path, entries)
    if bad:
        print("verification failed:", file=sys.stderr)
        for line in bad:
            print(f"  {line}", file=sys.stderr)
        return 1

    print("  permissions, contents and CRC ok")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        sys.exit(130)
