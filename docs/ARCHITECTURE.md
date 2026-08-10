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

## Known hazards (open work)

- **Channel variants.** `com.google.Chrome.beta.plist` is bundle-ID-prefixed by Chrome but belongs to Chrome Beta. Fix: when a matched name is itself a prefix-extension of another *installed* app's bundle ID, exclude it.
- **Vendor-nested directories.** Chrome's main data lives in `Application Support/Google/Chrome`, one level below a vendor folder. Fix: a second-level pass for known vendor-directory patterns, without opening the door to generic recursive matching.
- **Shared containers.** Group containers can be shared by several apps from one vendor; removing them with the last app only.

## Roadmap

1. Engine hardening: channel-variant exclusion, vendor-directory pass, running-app detection.
2. `remove` in the CLI: explicit confirmation, trash-only, prints what went where.
3. SwiftUI app (XcodeGen project), drag-and-drop and list UI.
4. Login items and launch agents (`SMAppService` + LaunchAgents plists).
5. Homebrew awareness: detect cask-managed apps, delegate to `brew uninstall --cask`.
6. Developer leftovers: caches for npm/pip/cargo, Xcode DerivedData, simulators.
7. System-level roots (`/Library/...`) behind a privileged helper.
8. Distribution: Developer ID signing, notarization, Sparkle updates.
