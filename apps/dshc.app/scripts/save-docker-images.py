#!/usr/bin/env python3
"""Save the dshc Docker image into the dshc.app per-architecture rootfs.

Pulls godotttt/dshc:<tag> (when missing locally or with --pull) and exports a
per-platform tarball with `docker save --platform`, mirroring the layout that
docker-save.sh produced: rootfs_<arch>/images/dshc-<tag>.tar.

The image tags published by the dshc pipeline have no "v" prefix (semver
normalization strips it), so the tag is used verbatim; latest is the default.
"""

from __future__ import annotations

import argparse
import json
import shutil
import re
import subprocess
import sys
import tarfile
from pathlib import Path

PLATFORM_ALIASES = {
    "all": ["linux/amd64", "linux/arm64"],
    "amd64": ["linux/amd64"],
    "arm64": ["linux/arm64"],
}

DEFAULT_PLATFORMS = ["linux/amd64", "linux/arm64"]
DEFAULT_REPO = "godotttt/dshc"
APP_ROOT = Path(__file__).resolve().parent.parent  # scripts/.. = apps/dshc.app


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export the dshc image as per-platform tarballs for the dshc.app rootfs.",
    )
    parser.add_argument(
        "-t",
        "--tag",
        default="latest",
        help="image tag to save (used verbatim, no v prefix is added; default: latest)",
    )
    parser.add_argument(
        "-p",
        "--platform",
        default=",".join(DEFAULT_PLATFORMS),
        help="comma-separated platforms, or 'all' (= linux/amd64,linux/arm64); "
        "default: linux/amd64,linux/arm64",
    )
    parser.add_argument(
        "-r",
        "--repo",
        default=DEFAULT_REPO,
        help=f"registry repository to pull from (default: {DEFAULT_REPO})",
    )
    parser.add_argument(
        "-o",
        "--out",
        type=Path,
        default=APP_ROOT,
        help="output root; per-platform tarballs go to <out>/rootfs_<arch>/images "
        f"(default: {APP_ROOT})",
    )
    parser.add_argument(
        "--pull",
        action="store_true",
        help="force `docker pull` even when the image is already present locally",
    )
    return parser.parse_args(argv)


def resolve_platforms(raw: str) -> list[str]:
    """Normalize the --platform value into a list of platform strings."""
    expanded = PLATFORM_ALIASES.get(raw.strip().lower(), [raw])
    out: list[str] = []
    for chunk in expanded:
        for item in chunk.split(","):
            platform = item.strip()
            if platform:
                out.append(platform)
    return out


def platform_dir(out_root: Path, platform: str) -> Path:
    """Map a platform string to its rootfs images directory under out_root.

    Matches the app layout: linux/amd64 -> rootfs_amd64, linux/arm64 ->
    rootfs_arm64 (the os prefix is dropped). Non-linux/os platforms fall back
    to the full sanitized string (rootfs_linux_arm64-style).
    """
    if platform.startswith("linux/"):
        arch = platform.split("/", 1)[1]
    else:
        arch = platform.replace("/", "_")
    return out_root / f"rootfs_{arch}" / "images"


def clear_dir(out_dir: Path) -> None:
    """Remove files already in out_dir so a rootfs keeps one image per arch.

    Old tarballs from previous releases would otherwise accumulate in the
    shipped bundle.
    """
    for entry in out_dir.iterdir():
        if entry.is_file():
            entry.unlink()
            print(f"  removed old {entry.name}")


def docker(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["docker", *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def image_arch(image: str) -> str | None:
    """Local platform of <image> as 'os/arch', or None when absent.

    With the classic (default) image store a multi-arch pull only materializes
    the host architecture, so this is compared against the requested platform
    to decide whether a per-platform pull is needed.
    """
    inspected = docker(
        "image", "inspect", "--format", "{{.Os}}/{{.Architecture}}", image
    )
    if inspected.returncode != 0:
        return None
    return inspected.stdout.strip().lower()


def storage_driver() -> str:
    """Docker storage driver; 'overlayfs' means the containerd image store.

    With the containerd store a tag holds every platform, `docker save`
    without --platform exports the host one, and --platform selects the
    variant; with the classic store pull --platform swaps the tag's content
    and `docker save` (no --platform) exports what is stored.
    """
    r = docker("info", "--format", "{{.Driver}}")
    return r.stdout.strip().lower() if r.returncode == 0 else ""


def tar_arch(path: Path) -> str | None:
    """Architecture of the image inside a `docker save` tarball.

    The manifest lists layers and a Config descriptor; the architecture lives
    in the referenced config json, not in the manifest itself.
    """
    try:
        with tarfile.open(path, "r") as tar:
            manifest = json.loads(tar.extractfile("manifest.json").read() or b"{}")
            config = json.loads(tar.extractfile(manifest[0]["Config"]).read() or b"{}")
        return config.get("architecture", "").lower() or None
    except (
        OSError,
        KeyError,
        IndexError,
        json.JSONDecodeError,
        tarfile.TarError,
    ) as exc:
        print(f"  warning: cannot read architecture from {path.name}: {exc}")
        return None


def ensure_platform_image(image: str, platform: str, force_pull: bool) -> bool:
    """Pull <image> for <platform> unless the local image already is that arch.

    The tag is then overwritten with the requested platform's image, so a
    following `docker save` (without --platform) exports that architecture.
    """
    if not force_pull and image_arch(image) == platform:
        return True
    pulled = docker("pull", "--platform", platform, image)
    if pulled.returncode != 0:
        print(f"  pull failed: {pulled.stderr.strip()}", file=sys.stderr)
        return False
    return True


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if not shutil.which("docker"):
        print("error: docker command not found", file=sys.stderr)
        return 2

    if not (args.tag and re.match(r"^[A-Za-z0-9._-]+$", args.tag)):
        print(
            f"warning: tag '{args.tag}' contains unusual characters, continuing anyway"
        )

    platforms = resolve_platforms(args.platform)
    if not platforms:
        print("error: no platforms given", file=sys.stderr)
        return 2

    image = f"{args.repo}:{args.tag}"
    driver = storage_driver()
    print(f"(storage driver: {driver or 'unknown'})")
    success = 0
    failed: list[str] = []

    for platform in platforms:
        out_dir = platform_dir(args.out, platform)
        out_dir.mkdir(parents=True, exist_ok=True)
        clear_dir(out_dir)
        out_file = out_dir / f"dshc-{args.tag}.tar"
        print(f"exporting {platform} -> {out_file}")
        if not ensure_platform_image(image, platform, args.pull):
            failed.append(platform)
            continue
        save_cmd = ["save", image, "--output", str(out_file)]
        if driver == "overlayfs":  # containerd store: select the platform explicitly
            save_cmd = [
                "save",
                "--platform",
                platform,
                image,
                "--output",
                str(out_file),
            ]
        saved = docker(*save_cmd)
        if saved.returncode != 0:
            failed.append(platform)
            print(f"  failed: {platform} ({saved.stderr.strip()})", file=sys.stderr)
            continue
        expected = platform.rsplit("/", 1)[-1].lower()
        actual = tar_arch(out_file)
        if actual is None or actual != expected:
            out_file.unlink(missing_ok=True)  # never ship an unverified/wrong tar
            failed.append(platform)
            reason = (
                f"(cannot verify tarball architecture)"
                if actual is None
                else f"(tarball architecture {actual}, expected {expected})"
            )
            print(f"  failed: {platform} {reason}", file=sys.stderr)
            continue
        success += 1
        print(f"  ok: {platform}")

    print("=" * 40)
    print(
        f"export summary: {success} succeeded, {len(failed)} failed, {len(platforms)} total"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
