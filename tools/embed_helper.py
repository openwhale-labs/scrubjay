#!/usr/bin/env python3
"""Embed the privileged helper into the app bundle (Xcode post-build phase).

Copies the helper executable to Contents/Library/HelperTools and the daemon
plist to Contents/Library/LaunchDaemons, where SMAppService expects them.
Runs before Xcode signs the app, so both land inside the signature.
"""

import os
import shutil
import sys
from pathlib import Path


def main() -> int:
    app = Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["WRAPPER_NAME"]
    products = Path(os.environ["BUILT_PRODUCTS_DIR"])
    srcroot = Path(os.environ["SRCROOT"])

    helper = products / "dev.openwhale.scrubjay.helper"
    plist = srcroot / "Helper" / "dev.openwhale.scrubjay.helper.plist"

    # Wipe both directories first: an incremental build over a renamed
    # bundle identifier would otherwise keep shipping the previous
    # privileged helper alongside the current one.
    helper_dir = app / "Contents" / "Library" / "HelperTools"
    daemon_dir = app / "Contents" / "Library" / "LaunchDaemons"
    for directory in (helper_dir, daemon_dir):
        if directory.exists():
            shutil.rmtree(directory)
        directory.mkdir(parents=True)

    shutil.copy2(helper, helper_dir / helper.name)
    shutil.copy2(plist, daemon_dir / plist.name)
    print(f"embedded helper into {app}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
