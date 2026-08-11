#!/usr/bin/env python3
"""Upload the release DMG and Sparkle appcast to R2.

The bucket is served at dl.openwhale.dev, which is what the download button
and the app's update feed both point at. Run after tools/release.py.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DIST = REPO / "dist"
BUCKET = "openwhale-releases"
PREFIX = "scrubjay"


def run(*cmd: str) -> None:
    env = dict(os.environ)
    result = subprocess.run(cmd, env=env)
    if result.returncode != 0:
        raise SystemExit(f"command failed: {' '.join(cmd)}")


def put(path: Path, content_type: str) -> None:
    print(f"==> {path.name}")
    run(
        "npx", "-y", "wrangler@latest", "r2", "object", "put",
        f"{BUCKET}/{PREFIX}/{path.name}",
        "--file", str(path), "--content-type", content_type, "--remote",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", help="release version, e.g. 0.1.0")
    args = parser.parse_args()

    dmgs = sorted(DIST.glob("ScrubJay-*.dmg"))
    dmgs = [d for d in dmgs if "unnotarized" not in d.name]
    if args.version:
        dmgs = [d for d in dmgs if args.version in d.name]
    if not dmgs:
        raise SystemExit("no notarized DMG in dist/")

    appcast = DIST / "appcast.xml"
    if not appcast.exists():
        raise SystemExit("no appcast.xml in dist/ — run tools/release.py first")

    for dmg in dmgs:
        put(dmg, "application/x-apple-diskimage")
    # The appcast goes last: it must never advertise a build that is not
    # downloadable yet.
    put(appcast, "application/xml")
    print(f"\nLive: https://dl.openwhale.dev/{PREFIX}/{appcast.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
