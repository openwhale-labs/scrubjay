# ScrubJay

Uninstall Mac apps cleanly.

ScrubJay removes an application together with the files it leaves behind — caches, preferences, containers, saved state, logs, launch agents. Every removal goes to the Trash, so nothing is lost for good.

**ScrubJay 0.1.0 is available** — download the notarized DMG at [scrubjay.openwhale.dev](https://scrubjay.openwhale.dev). Early release; expect rough edges.

## Build the app

```
brew install xcodegen
xcodegen
xcodebuild -project ScrubJay.xcodeproj -scheme ScrubJay build
```

Pick an app in the sidebar to see everything it would leave behind, grouped by how confident ScrubJay is. Items are preselected by confidence — loosely matched files never are. Removal moves files to the Trash and is blocked while the app is running.

## Try the CLI

```
swift run scrubjay apps
swift run scrubjay scan "Google Chrome"
swift run scrubjay remove "Some App"
swift run scrubjay dev
swift run scrubjay orphans
```

`scan` reports what would be removed and how confident ScrubJay is about each file; it never deletes anything. `remove` shows the same report, asks for confirmation, and moves the items to the Trash — loosely matched files are excluded unless you lower `--min-confidence` yourself. `dev` lists developer caches (npm, pnpm, DerivedData, Homebrew downloads, …) that are safe to clear because everything in them is re-fetched or rebuilt on demand; `dev clean` moves them to the Trash after confirmation. `orphans` finds bundle-identifier-keyed files that no installed app claims — traces of apps uninstalled without cleanup.

## Design

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the engine design, the confidence model, and the roadmap.

## Requirements

- macOS 14 or later
- Swift 6.0 toolchain to build from source

## License

Apache 2.0 with the Commons Clause: use, modify, and redistribute freely; selling ScrubJay, or a product whose value derives substantially from it, is not permitted. See [LICENSE](LICENSE).
