# Architecture

## Goals

- Uninstall an app and the files it leaves behind, with nothing deleted permanently — everything goes to the Trash.
- One job done well. No system "optimization", no telemetry, no background daemons beyond what a feature strictly needs.
- The engine is a library (`ScrubJayKit`) with no UI dependencies, consumed by a CLI today and a SwiftUI app next.

## Layers

```
ScrubJayKit   engine: inventory, scanning, matching, removal
ScrubJayCLI   thin front end for development and power users
ScrubJay.app  SwiftUI front end (planned)
```

`ScrubJayKit` is deliberately synchronous and value-typed; front ends own their threading.

## Confidence model

Matching a file to an app is the entire product. Every result carries a confidence level, and confidence — not category — decides what a UI may preselect.

| Level | Meaning | Example | UI default |
|---|---|---|---|
| `certain` | Bundle ID exact, or bundle ID + well-known suffix | `com.google.Chrome.plist` | selected |
| `high` | Bundle ID prefix, unknown suffix | `com.google.Chrome.helper` | selected |
| `medium` | Exact normalized app-name match | `Google Chrome/` | selected, flagged |
| `low` | Weak signal (very short names, etc.) | `Arc/` | never preselected |

Matching rules live in `Matcher` and are pure functions with no filesystem access, so every rule is unit-tested.

## Safety invariants

1. **Trash only.** `Trasher` is the single removal path; it calls `FileManager.trashItem` and nothing else. There is no permanent-delete code in the codebase.
2. **Protected paths.** `Trasher` refuses to touch filesystem roots, the home directory, `~/Library` itself, and other top-level folders — even if matching logic goes wrong.
3. **Top-level matching.** Search roots are scanned one level deep. Descending further trades precision for noise.
4. **`low` is advisory.** Low-confidence results exist to inform the user, never to be acted on automatically.

## Attribution defenses

Two hazards observed on real machines are handled in the scanner, both biased toward missing a file over deleting a wrong one:

- **Channel variants.** `com.google.Chrome.beta.plist` is bundle-ID-prefixed by Chrome but belongs to Chrome Beta. Defense in two layers: any entry that a longer installed bundle ID claims is attributed to that app and excluded from the target's results; and when the sibling app is *not* installed, a channel token (`beta`, `canary`, `dev`, …) right after the bundle ID caps the entry at `low`, so it is reported but never preselected.
- **Vendor-nested directories.** Chrome's main data lives in `Application Support/Google/Chrome`, one level below a vendor folder. The scanner descends exactly one level, only into a directory named after the app's own vendor (the second component of its bundle ID), and matches children by composing vendor + child against the app name ("Google" + "Chrome" → "Google Chrome"). The vendor directory itself is never a result, and children composing another installed app's name are excluded.

## Known hazards (open work)

- **Shared containers.** Group containers can be shared by several apps from one vendor; removing them with the last app only.

## Roadmap

1. Engine hardening: running-app detection.
2. `remove` in the CLI: explicit confirmation, trash-only, prints what went where.
3. SwiftUI app (XcodeGen project), drag-and-drop and list UI.
4. Login items and launch agents (`SMAppService` + LaunchAgents plists).
5. Homebrew awareness: detect cask-managed apps, delegate to `brew uninstall --cask`.
6. Developer leftovers: caches for npm/pip/cargo, Xcode DerivedData, simulators.
7. System-level roots (`/Library/...`) behind a privileged helper.
8. Distribution: Developer ID signing, notarization, Sparkle updates.
