# Contributing

Thanks for looking. ScrubJay deletes people's files, so the bar for changes is
about care rather than volume: a small patch with a test that would have caught
the bug is worth more than a large one without.

## Building

The engine and CLI build with Swift alone:

```sh
swift build
swift test
swift run scrubjay scan "Some App"
```

The app needs [XcodeGen](https://github.com/yonaskolb/XcodeGen), which generates
`ScrubJay.xcodeproj` from `project.yml` (the project file itself is not in the
repo):

```sh
brew install xcodegen swiftlint
xcodegen generate
xcodebuild -project ScrubJay.xcodeproj -scheme ScrubJay -configuration Debug build
```

Signing is only needed to run the privileged helper: XPC checks the app's
signature, so an ad-hoc build can browse and remove user-level leftovers but
cannot touch `/Library`. Everything else works unsigned.

## Style is enforced, not remembered

`.swiftlint.yml` carries rules that fail the build, and they exist because the
same component once rendered two different greys:

- Colours and sizes come from `App/Theme.swift`. No `.secondary`,
  `.quaternary`, `Color.orange`, or bare numbers for spacing, padding, corner
  radius, or icon size.
- Hierarchical styles are rejected outright: they resolve against whatever
  `foregroundStyle` an ancestor set, so the same view renders differently
  depending on where it is placed.

SwiftLint runs on every Xcode build and in CI. `swiftlint --fix` handles the
mechanical parts.

## What a change should carry

- **Tests for matching logic.** `Matcher` and the scanners are pure functions
  over fixtures; a rule change without a test is a rule that will drift.
- **Fixtures over the real filesystem.** Tests build a temporary home
  directory; none of them read the machine they run on.
- **A reason in the commit message.** What changed and why, enough to
  understand it from `git log` without opening the diff.

## The parts to be careful with

- `Helper/` runs as root. Its four rules are in
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#the-privileged-helper); a change
  there needs an argument for why the rule still holds.
- Confidence levels decide what a UI preselects. Raising a level makes
  ScrubJay delete more by default, which is the one direction that cannot be
  undone by an apology.
- `Trasher` is the only removal path. Nothing else may delete, and nothing may
  delete permanently.

## Reporting a security issue

See [SECURITY.md](SECURITY.md) — please do not open a public issue for
anything touching the privileged helper.
