# Architecture

## Goals

- Uninstall an app and the files it leaves behind, with nothing deleted permanently — everything goes to the Trash.
- One job done well. No system "optimization", no telemetry, no background daemons beyond what a feature strictly needs.
- The engine is a library (`ScrubJayKit`) with no UI dependencies, consumed by both the CLI and the app.

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
| `high` | Bundle ID prefix + recognized helper token | `com.google.Chrome.helper` | selected |
| `medium` | Exact normalized app-name match | `Google Chrome/` | selected, flagged |
| `low` | Weak signal: unknown suffix, channel token, shared group container, very short name | `com.google.Chrome.beta` | never preselected |

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

## The privileged helper

System-domain leftovers (`/Library/...`, root-owned app bundles) need root to remove, so the app registers a launchd daemon through `SMAppService` and talks to it over XPC. A root daemon that moves files is the highest-risk code in the project, and it holds to four rules:

1. **The daemon is the boundary, not the app.** The destination Trash and the resulting ownership come from the connection's audit token — they are not parameters. A compromised client cannot redirect a privileged move.
2. **Descriptors, never paths.** The Trash is opened once with `O_NOFOLLOW`; moves are `renameat` between descriptors, ownership is `fchownat(..., AT_SYMLINK_NOFOLLOW)`, and directory recursion is `openat` + `fdopendir`. A path that is checked and later re-resolved can be swapped in between; a descriptor cannot.
3. **An allow-list, not a prefix.** Sources must be direct children of the scanner's own system roots (or a whole `.app` under `/Applications`), compared by parent equality. `/Library/Keychains` and friends are unreachable by construction, and `HelperPolicyTests` fails the build if the allow-list and the scanner's roots ever diverge.
4. **Still only the Trash.** The helper moves; it never deletes. Ownership is handed to the calling user so the items stay restorable.

These rules are load-bearing rather than stylistic. A destination taken from the request turns the daemon into a general-purpose file mover; `chown` following a symlink hands ownership of arbitrary files to the caller; a prefix match instead of an allow-list leaves `/Library/Keychains` reachable; a path checked and then re-resolved can be swapped in between.

## Known hazards (open work)

- **Removing a shared group container** while sibling apps remain installed. Reported at `low` today; a real ownership model is future work.

## Roadmap

1. An ownership model for shared group containers.
2. Removing stale background-item records, if macOS ever exposes an API for it.
