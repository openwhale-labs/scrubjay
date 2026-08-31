#!/usr/bin/env python3
"""Upload the release DMG and Sparkle appcast to R2.

The bucket is served at dl.openwhale.dev, which is what the download button
and the app's update feed both point at. Run after tools/release.py.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DIST = REPO / "dist"
BUCKET = "openwhale-releases"
PREFIX = "scrubjay"
BASE_URL = f"https://dl.openwhale.dev/{PREFIX}"
ZONE_ID = "998705dbdda4791a2fe1a323b3e9e8d2"
# Cloudflare answers 403 to the default Python-urllib agent.
USER_AGENT = "scrubjay-publish/1.0"


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


def purge(urls: list[str]) -> None:
    """Drop the CDN's copies so visitors stop getting the previous release.

    R2 sits behind Cloudflare's cache with a multi-hour TTL: without this,
    an upload is invisible at the edge for hours, and a cask whose checksum
    already points at the new build fails for everyone who tries it.
    """
    print("==> Purging CDN cache")
    email = os.environ.get("CLOUDFLARE_EMAIL") or os.environ.get("CF_EMAIL")
    key = os.environ.get("CLOUDFLARE_API_KEY") or os.environ.get("CF_API_KEY")
    if not (email and key):
        raise SystemExit("CLOUDFLARE_EMAIL / CLOUDFLARE_API_KEY not set")
    request = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/purge_cache",
        data=json.dumps({"files": urls}).encode(),
        headers={
            "X-Auth-Email": email, "X-Auth-Key": key,
            "Content-Type": "application/json", "User-Agent": USER_AGENT,
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = json.load(response)
    if not body.get("success"):
        raise SystemExit(f"cache purge failed: {body.get('errors')}")


def verify_live(path: Path) -> None:
    """Download what visitors get and compare it byte for byte.

    Uploading is not publishing: the object store, the cache, and the file
    on disk have to agree before a release counts as out.
    """
    expected = hashlib.sha256(path.read_bytes()).hexdigest()
    url = f"{BASE_URL}/{path.name}"
    for attempt in range(6):
        request = urllib.request.Request(
            f"{url}?v={int(time.time())}{attempt}", headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=120) as r:
            actual = hashlib.sha256(r.read()).hexdigest()
        if actual == expected:
            print(f"    {path.name} matches ({expected[:16]}…)")
            return
        time.sleep(5)
    raise SystemExit(
        f"{url} still serves {actual[:16]}… but the local file is {expected[:16]}…"
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
    # Sparkle delta updates: the appcast advertises them, so they must be
    # downloadable before it goes up.
    dmgs += sorted(DIST.glob("ScrubJay*.delta"))

    appcast = DIST / "appcast.xml"
    if not appcast.exists():
        raise SystemExit("no appcast.xml in dist/ — run tools/release.py first")

    for dmg in dmgs:
        put(dmg, "application/x-apple-diskimage")
    # The appcast goes last: it must never advertise a build that is not
    # downloadable yet.
    put(appcast, "application/xml")

    purge([f"{BASE_URL}/{p.name}" for p in dmgs + [appcast]])
    print("==> Verifying what the CDN serves")
    for path in dmgs + [appcast]:
        verify_live(path)

    print(f"\nLive: {BASE_URL}/{appcast.name}")
    for dmg in dmgs:
        print(f"      {BASE_URL}/{dmg.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
