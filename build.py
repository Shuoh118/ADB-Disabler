#!/usr/bin/env python3
"""Pack the ADB Disabler Magisk/KernelSU/APatch module.

    python3 build.py

Produces ../dist/ADB-Disabler-<version>.zip, ready to flash. The build
directory sits outside the source tree so a checkout stays clean and the
output never ends up in git by accident.

Only the Python standard library is used. Nothing outside this directory
is read; nothing outside the output directory is written.

Executable bits are the one thing that actually breaks modules: a
service.sh packed as 0644 is silently skipped by every manager, and the
module installs "successfully" while doing nothing. Every file that
starts with a shebang, plus META-INF/com/google/android/update-binary,
gets 0755. Everything else gets 0644. The archive is reopened and each
mode is read back before the script reports success.
"""

from __future__ import annotations

import argparse
import os
import stat
import sys
import zipfile

SRC = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(os.path.dirname(SRC), "dist")

SKIP_DIRS = {".git", ".github", "__pycache__", "out", "dist", ".idea", ".vscode"}
SKIP_FILES = {".DS_Store", "Thumbs.db", "desktop.ini", ".gitignore"}

ALWAYS_EXEC = {"META-INF/com/google/android/update-binary"}

EXEC_BITS = 0o755
FILE_BITS = 0o644

# Reproducible archives: same input bytes always produce the same zip.
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
    """Walk SRC and yield (relative_path, absolute_path, mode)."""
    for root, dirs, files in os.walk(SRC):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            if name in SKIP_FILES or name.endswith((".pyc", ".swp", "~")):
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
            corrupt = "archive is not a valid zip"
        if corrupt:
            bad.append(f"corrupt entry: {corrupt}")
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description="Build the ADB Disabler module zip.")
    ap.add_argument("-o", "--out", default=DEFAULT_OUT, help="output directory")
    ap.add_argument("--no-verify", action="store_true", help="skip the post-build check")
    args = ap.parse_args()

    if not os.path.isdir(SRC):
        die(f"source directory missing: {SRC}")

    mod_id = read_prop("id")
    version = read_prop("version")
    if not mod_id:
        die("module.prop has no id=")
    if not version:
        die("module.prop has no version=")

    entries = list(collect())
    if not entries:
        die("nothing to pack")

    required = {"module.prop", "customize.sh", "service.sh"}
    present = {rel for rel, _, _ in entries}
    missing = sorted(required - present)
    if missing:
        die("required files missing: " + ", ".join(missing))

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    zip_name = f"ADB-Disabler-{version}.zip"
    zip_path = os.path.join(out_dir, zip_name)

    count = pack(zip_path, entries)
    size_kib = os.path.getsize(zip_path) / 1024

    print(f"{zip_name}  {count} files  {size_kib:.1f} KiB")
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
