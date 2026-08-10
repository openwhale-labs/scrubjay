# ScrubJay

Uninstall Mac apps cleanly.

ScrubJay removes an application together with the files it leaves behind — caches, preferences, containers, saved state, logs, launch agents. Every removal goes to the Trash, so nothing is lost for good.

**Status: early development.** The scanning engine and a CLI exist; the app is not built yet. Not ready for daily use.

## Try the CLI

```
swift run scrubjay apps
swift run scrubjay scan "Google Chrome"
```

`scan` reports what would be removed and how confident ScrubJay is about each file. It does not delete anything.

## Design

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the engine design, the confidence model, and the roadmap.

## Requirements

- macOS 14 or later
- Swift 6.0 toolchain to build from source
