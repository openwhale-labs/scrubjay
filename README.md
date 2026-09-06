# ScrubJay

Uninstall Mac apps cleanly. ([中文说明](README.zh-CN.md))

ScrubJay removes an application together with the files it leaves behind — caches, preferences, containers, saved state, logs, launch agents. Every removal goes to the Trash, so nothing is lost for good.

**ScrubJay is available.** Download the notarized DMG at [scrubjay.openwhale.dev](https://scrubjay.openwhale.dev), or install with Homebrew:

```
brew install --cask openwhale-labs/tap/scrubjay
```

Early release; expect rough edges.

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

```
$ scrubjay scan "Google Chrome"
Google Chrome (com.google.Chrome) — /Applications/Google Chrome.app

[certain]
  ~/Library/Preferences/com.google.Chrome.plist  (4 KB)

[medium]
  ~/Library/Application Support/Google/Chrome  (7.56 GB)
  ~/Library/Caches/Google/Chrome  (1.78 GB)

3 items, 9.33 GB
```

`scan` reports what would be removed and how confident ScrubJay is about each file; it never deletes anything. `remove` shows the same report, asks for confirmation, and moves the items to the Trash — loosely matched files are excluded unless you lower `--min-confidence` yourself. `dev` lists developer caches (npm, pnpm, DerivedData, Homebrew downloads, …) that are safe to clear because everything in them is re-fetched or rebuilt on demand; `dev clean` moves them to the Trash after confirmation. `orphans` finds bundle-identifier-keyed files that no installed app claims — traces of apps uninstalled without cleanup.

## Design

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the engine design, the confidence model, and the roadmap.

## Requirements

- macOS 14 or later
- Swift 6.0 toolchain to build from source

## Contributing

Bug reports and patches are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for
how to build the app and what a change should carry. Security issues go through
[SECURITY.md](SECURITY.md) rather than a public issue.

## License

Source-available, not open source in the OSI sense: Apache 2.0 with the
[Commons Clause](https://commonsclause.com/). Read it, change it, run it,
redistribute it — selling ScrubJay, or a product whose value derives
substantially from it, is not permitted. See [LICENSE](LICENSE).
