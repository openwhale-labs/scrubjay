# Architecture

## Goals

- Uninstall an app and the files it leaves behind, with nothing deleted permanently — everything goes to the Trash.
- One job done well. No system "optimization", no telemetry, no background daemons beyond what a feature strictly needs.
- The engine is a library (`ScrubJayKit`) with no UI dependencies, consumed by a CLI today and a SwiftUI app next.

## Layers

```
ScrubJayKit   engine: inventory, scanning, matching, removal
ScrubJayCLI   thin front end for development and power users
ScrubJay.app  SwiftUI front end (App/, XcodeGen project)
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
- **Unknown bundle-ID suffixes.** `com.foo.App.Something` could be App's helper or an uninstalled sibling product. Only recognized helper tokens (`helper`, `renderer`, `updater`, `app`, …) earn `high`; anything unrecognized stays at `low` and is never preselected.
- **Ambiguous names.** A name-keyed entry that also name-matches another installed app is attributed to neither.
- **Group containers.** Entries are team-ID-prefixed (`5A4RE8SF68.com.tencent.xinWeChat`); matching strips the team ID and always reports at `low`, because a group container may be shared by the vendor's other apps.
- **Launch agents.** Unloading (`launchctl bootout`) is a behavior change beyond the Trash model, so it requires the plist's own `Label` to carry the target's bundle ID — a matched file name is not enough.

## Known hazards (open work)

- **Removing a shared group container** while sibling apps remain installed. Reported at `low` today; a real ownership model is future work.

## Decision record — council review, 2026-08-10

Status: frozen 2026-08-10 (both reviewers verified all findings closed, no new P0).

Two independent reviews (baseline `0cf12ea`) drove these changes, all landed:

- Scan generation token: a stale scan can no longer be shown for, or removed as, the newer selection; removal re-asserts the plan belongs to the currently selected app.
- Apple applications are refused on every removal path, including drag-and-drop (previously CLI-only).
- Chat-data protection extends to the CLI (`--include-chat-data` to override).
- Unknown-suffix downgrade, ambiguous-name skip, group-container matching, and the launch-agent Label guard (see attribution defenses above).
- `Trasher` resolves symlinks before the protected-path check.

Deliberately not changed, pending owner decision: Select all includes `low` items (explicit user action); the chat-app list is curated best-effort rather than fail-closed for every app's Containers; app-layer state-machine tests await an injectable engine boundary.

## Roadmap

1. System-level roots (`/Library/...`) behind a privileged helper.
2. Distribution: Developer ID signing, notarization, Sparkle updates.
