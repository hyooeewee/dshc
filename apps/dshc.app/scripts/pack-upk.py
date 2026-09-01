#!/usr/bin/env python3
"""Stamp the release version into the dshc.app bundle and pack it with `ug`.

Updates the image tag in rootfs_common/docker-compose.yaml and the version in
project.yaml to the given release tag (image tags are published without a "v"
prefix); the project version keeps only the semver core (0.1.2-alpha.3 ->
0.1.2) while the compose image ref stays verbatim. Then runs `ug check` and
`ug pack --arch all --build <id>` through apps/dshc.app/bin/ug.

Modes (at most one):
  default      stamp versions, `ug check`, `ug pack`  (needs --build, --tag)
  --prepack    stamp versions + `ug check`, no pack  (prepares for pack;
               needs --tag)
  --check-only `ug check` only, no stamping, no pack (needs nothing)
  --pack-only  `ug pack` only, no stamping, no check (chains after prepack;
               needs --build)
  --dry-run    preview edits and commands without writing or executing
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent  # scripts/.. = apps/dshc.app
UG = Path(os.environ.get("DSHC_UG", str(APP_DIR / "bin" / "ug")))

COMPOSE_PATH = APP_DIR / "rootfs_common" / "docker-compose.yaml"
PROJECT_PATH = APP_DIR / "project.yaml"

IMAGE_RE = re.compile(r"^(\s*image:\s*godotttt/dshc):\S+\s*$")
VERSION_RE = re.compile(r"^version:\s*\S+\s*$")

_SEMVER_CORE_RE = re.compile(r"^([0-9]+\.[0-9]+\.[0-9]+)")
_TAG_RE = re.compile(r"^[A-Za-z0-9._-]+$")  # Docker tag charset


def semver_core(tag: str) -> str:
    """Major.minor.patch of a tag, dropping any -prerelease/+build suffix.

    Falls back to the full tag when it has no three-part stem, so non-semver
    values like `latest` do not truncate.
    """
    match = _SEMVER_CORE_RE.match(tag)
    return match.group(1) if match else tag


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stamp the release tag into the dshc.app bundle and pack it with ug.",
    )
    parser.add_argument("--build", help="ug pack build id, e.g. 103")
    parser.add_argument(
        "--tag",
        help="release tag, e.g. 0.1.2-alpha.3: compose image ref written "
        "verbatim, project version written as its semver core (0.1.2)",
    )
    parser.add_argument(
        "--prepack",
        action="store_true",
        help="stamp versions + run `ug check`, no pack (needs --tag)",
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="run `ug check` only; no stamping, no pack",
    )
    parser.add_argument(
        "--pack-only",
        action="store_true",
        help="run `ug pack` only; no stamping, no check (chains after prepack; needs --build)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="preview version edits and commands without writing or executing",
    )
    return parser.parse_args(argv)


def stamp_file(
    path: Path, pattern: re.Pattern[str], value: str, dry_run: bool = False
) -> str | None:
    """Replace the first line matching `pattern` with `value`.

    Returns the old line, or None when nothing matched. The leading whitespace
    of the matched line is preserved (changing the value must not disturb the
    file's indentation). With dry_run the file is left untouched.
    """
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    for i, line in enumerate(lines):
        if pattern.match(line):
            old = line.rstrip("\n")
            if not dry_run:
                indent = re.match(r"[ \t]*", line).group(0)
                lines[i] = f"{indent}{value}\n"
                path.write_text("".join(lines), encoding="utf-8")
            return old
    return None


def update_versions(tag: str, dry_run: bool = False) -> list[tuple[str, str, str]]:
    """Stamp both files; returns list of (file, old line, new line) changes."""
    changes: list[tuple[str, str, str]] = []

    old = stamp_file(
        COMPOSE_PATH, IMAGE_RE, f"image: godotttt/dshc:{tag}", dry_run=dry_run
    )
    if old is None:
        raise SystemExit(f"error: no godotttt/dshc image line found in {COMPOSE_PATH}")
    changes.append((str(COMPOSE_PATH), old, f"image: godotttt/dshc:{tag}"))

    version = semver_core(tag)
    old = stamp_file(PROJECT_PATH, VERSION_RE, f"version: {version}", dry_run=dry_run)
    if old is None:
        raise SystemExit(f"error: no version line found in {PROJECT_PATH}")
    changes.append((str(PROJECT_PATH), old, f"version: {version}"))

    return changes


def run_ug(build: str | None, dry_run: bool, mode: str) -> int:
    """Run the ug steps for `mode` (full | prepack | check-only | pack-only)."""
    commands: list[list[str]] = []
    if mode != "pack-only":
        commands.append([str(UG), "check"])
    if mode in ("full", "pack-only"):
        commands.append([str(UG), "pack", "--arch", "all", "--build", build or ""])

    if dry_run:
        print("would run: " + " && ".join(" ".join(c) for c in commands))
        return 0
    for cmd in commands:
        print("$ " + " ".join(cmd))
        # ug resolves project.yaml relative to its working directory, so run
        # it inside the app dir regardless of where this script was invoked.
        result = subprocess.run(cmd, cwd=APP_DIR)
        if result.returncode != 0:
            return result.returncode
    return 0


def mode_of(args: argparse.Namespace) -> str:
    modes = [
        m
        for m, flag in (
            ("prepack", args.prepack),
            ("check-only", args.check_only),
            ("pack-only", args.pack_only),
        )
        if flag
    ]
    if len(modes) > 1:
        raise SystemExit(
            "error: --prepack, --check-only and --pack-only are mutually exclusive"
        )
    return modes[0] if modes else "full"


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    mode = mode_of(args)

    if not Path(UG).exists():
        print(f"error: {UG} not found", file=sys.stderr)
        return 2

    if mode in ("full", "pack-only") and not re.fullmatch(r"[0-9]+", args.build or ""):
        print(f"error: build id must be numeric, got '{args.build}'", file=sys.stderr)
        return 2
    if mode in ("full", "prepack") and not (args.tag and _TAG_RE.match(args.tag)):
        print(f"error: invalid or missing tag '{args.tag}'", file=sys.stderr)
        return 2

    if mode in ("full", "prepack"):
        changes = update_versions(args.tag or "", dry_run=args.dry_run)
        for path, old, new in changes:
            print(f"{path}:")
            print(f"  {old}  ->  {new}")

    return run_ug(args.build, dry_run=args.dry_run, mode=mode)


if __name__ == "__main__":
    sys.exit(main())
