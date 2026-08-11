#!/usr/bin/env python3
"""Build, sign, package, and notarize a ScrubJay release DMG.

One command: `python3 tools/release.py` from the repo root. Produces
dist/ScrubJay-<version>.dmg, notarized and stapled.

Requires: xcodegen, an installed "Developer ID Application" identity, and a
notarytool keychain profile (default AC_PASSWORD — account-level, shared
across apps).
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DERIVED = REPO / ".build" / "ReleaseDerived"
APP = DERIVED / "Build" / "Products" / "Release" / "ScrubJay.app"
DIST = REPO / "dist"
IDENTITY = "Developer ID Application: ARRWAY LTD (67ULUSQ947)"


def run(*cmd: str, check: bool = True) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        sys.stderr.write(result.stdout + result.stderr)
        raise SystemExit(f"command failed: {' '.join(cmd)}")
    return result.stdout + result.stderr


def version() -> str:
    match = re.search(r"MARKETING_VERSION: ([\d.]+)", (REPO / "project.yml").read_text())
    if not match:
        raise SystemExit("MARKETING_VERSION not found in project.yml")
    return match.group(1)


def build() -> None:
    print("==> Generating project and building Release")
    run("xcodegen", "generate")
    # `generic/platform=macOS` builds for every architecture in ARCHS rather
    # than just this Mac's; without it xcodebuild quietly produces a thin
    # binary and Intel users get nothing.
    run(
        "xcodebuild", "-project", str(REPO / "ScrubJay.xcodeproj"), "-scheme", "ScrubJay",
        "-configuration", "Release", "-derivedDataPath", str(DERIVED),
        "-destination", "generic/platform=macOS",
        "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "build",
    )


def resign_sparkle() -> None:
    """Re-sign Sparkle's nested executables with the release identity.

    Xcode signs the framework but not the helper apps, XPC services, and
    tools inside it, so notarization rejects them. They are signed
    inside-out, then the app is re-signed so its seal covers the new
    signatures.
    """
    framework = APP / "Contents" / "Frameworks" / "Sparkle.framework"
    if not framework.exists():
        return
    print("==> Re-signing Sparkle components")
    version = framework / "Versions" / "B"
    nested = [
        version / "XPCServices" / "Downloader.xpc",
        version / "XPCServices" / "Installer.xpc",
        version / "Updater.app",
        version / "Autoupdate",
        framework,
    ]
    for path in nested:
        if not path.exists():
            continue
        run(
            "codesign", "--force", "--sign", IDENTITY, "--timestamp",
            "--options", "runtime", str(path),
        )
    # The app's own seal must be re-established over the changed framework.
    run(
        "codesign", "--force", "--sign", IDENTITY, "--timestamp",
        "--options", "runtime", str(APP),
    )


def verify_app() -> None:
    print("==> Verifying signatures")
    run("codesign", "--verify", "--deep", "--strict", str(APP))
    helper_dir = APP / "Contents" / "Library" / "HelperTools"
    daemon_dir = APP / "Contents" / "Library" / "LaunchDaemons"
    helper = helper_dir / "dev.openwhale.scrubjay.helper"
    plist = daemon_dir / "dev.openwhale.scrubjay.helper.plist"
    for path in (helper, plist):
        if not path.exists():
            raise SystemExit(f"missing embedded helper piece: {path}")
    # Exactly one privileged helper ships — a stale one from a previous
    # bundle identifier would be extra root code in the release.
    for directory, expected in ((helper_dir, helper), (daemon_dir, plist)):
        found = sorted(p.name for p in directory.iterdir())
        if found != [expected.name]:
            raise SystemExit(f"unexpected contents in {directory}: {found}")
    # Both architectures must ship: the site promises Apple Silicon and
    # Intel, and a thin binary would quietly break half of that.
    for binary in (
        APP / "Contents" / "MacOS" / "ScrubJay",
        helper,
    ):
        archs = run("lipo", "-archs", str(binary)).split()
        if sorted(archs) != ["arm64", "x86_64"]:
            raise SystemExit(f"not a universal binary ({' '.join(archs)}): {binary}")
    print("    universal: arm64 + x86_64")

    for target in (str(APP), str(helper)):
        info = run("codesign", "-dv", target)
        if "67ULUSQ947" not in info:
            sys.stderr.write(info)
            raise SystemExit(f"not signed by the release identity: {target}")
        if "flags=0x10000(runtime)" not in info:
            sys.stderr.write(info)
            raise SystemExit(f"hardened runtime missing: {target}")
    print("    app and helper signed, hardened runtime on")


def make_dmg(ver: str, notarized: bool) -> Path:
    print("==> Building DMG")
    DIST.mkdir(exist_ok=True)
    # The release file name is reserved for artifacts that completed
    # notarization and Gatekeeper; anything else is clearly marked.
    suffix = "" if notarized else "-unnotarized"
    dmg = DIST / f"ScrubJay-{ver}{suffix}.dmg"
    dmg.unlink(missing_ok=True)
    staging = DIST / "dmg-staging"
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    shutil.copytree(APP, staging / "ScrubJay.app", symlinks=True)
    (staging / "Applications").symlink_to("/Applications")
    run(
        "hdiutil", "create", "-volname", "ScrubJay", "-srcfolder", str(staging),
        "-ov", "-format", "UDZO", str(dmg),
    )
    shutil.rmtree(staging)
    run("codesign", "--sign", IDENTITY, str(dmg))
    return dmg


def notarize(dmg: Path, profile: str) -> None:
    print("==> Submitting for notarization (a few minutes)")
    output = run(
        "xcrun", "notarytool", "submit", str(dmg),
        "--keychain-profile", profile, "--wait", "--timeout", "30m", check=False,
    )
    print(output)
    if "status: Accepted" not in output:
        match = re.search(r"^\s*id: (\S+)", output, re.MULTILINE)
        if match:
            sys.stderr.write(
                run("xcrun", "notarytool", "log", match.group(1),
                    "--keychain-profile", profile, check=False))
        raise SystemExit("notarization rejected")
    print("==> Stapling")
    run("xcrun", "stapler", "staple", str(dmg))
    if "worked" not in run("xcrun", "stapler", "staple", str(APP), check=False):
        print("    note: .app not stapled; it stays notarized online")


def gatekeeper(dmg: Path) -> None:
    print("==> Gatekeeper assessment")
    out = run("spctl", "-a", "-t", "open", "--context", "context:primary-signature",
              "-v", str(dmg), check=False)
    if "accepted" not in out:
        sys.stderr.write(out)
        raise SystemExit("Gatekeeper rejected the DMG")
    print("    accepted")


def make_appcast(dmg: Path) -> Path:
    """Sign the DMG and refresh the Sparkle appcast next to it.

    generate_appcast reads every DMG in the directory and emits the feed the
    app polls, so the release notes URL and version come from the bundle
    itself — nothing to keep in sync by hand.
    """
    print("==> Generating appcast")
    tool = (
        DERIVED / "SourcePackages" / "artifacts" / "sparkle" / "Sparkle" / "bin"
        / "generate_appcast"
    )
    if not tool.exists():
        raise SystemExit(f"generate_appcast not found at {tool}")
    run(
        str(tool), str(dmg.parent),
        "--download-url-prefix", "https://dl.openwhale.dev/scrubjay/",
        "--link", "https://scrubjay.openwhale.dev",
    )
    appcast = dmg.parent / "appcast.xml"
    if not appcast.exists():
        raise SystemExit("generate_appcast produced no appcast.xml")
    return appcast


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default="AC_PASSWORD")
    parser.add_argument("--skip-notarize", action="store_true")
    args = parser.parse_args()

    ver = version()
    build()
    resign_sparkle()
    verify_app()
    dmg = make_dmg(ver, notarized=not args.skip_notarize)
    if args.skip_notarize:
        print(f"==> Skipped notarization; test build at {dmg}")
        return 0
    notarize(dmg, args.profile)
    gatekeeper(dmg)
    appcast = make_appcast(dmg)
    print(f"\nDone: {dmg}")
    print(f"Appcast: {appcast}")
    print("Upload both to R2: tools/publish.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
