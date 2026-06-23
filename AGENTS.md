# AGENTS.md

Guidance for AI coding agents working in the **Differentialis** repository.

## What this is

Differentialis is a native **macOS 26 (Tahoe)** app for comparing and merging
text, images, and folders, with git built in. It is written in **SwiftUI**
using Apple's Liquid Glass APIs and has **zero third-party dependencies** — the
diff/merge engines are pure Swift and git is driven through the system `git`
binary.

## Requirements

- **macOS 26 (Tahoe)** or later (the app uses Liquid Glass APIs).
- **Xcode 26** / **Swift 6**.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

> The `.xcodeproj` is **generated** and is not committed. Always run
> `xcodegen generate` before building if it is missing or after editing
> `project.yml`.

## Build & run

```bash
# 1. Generate the Xcode project from project.yml
xcodegen generate

# 2a. Open in Xcode and hit Run
open Differentialis.xcodeproj

# 2b. …or build & launch from the command line
xcodebuild -project Differentialis.xcodeproj -scheme Differentialis \
    -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Differentialis.app
```

## Tests

```bash
xcodebuild -project Differentialis.xcodeproj -scheme Differentialis test
```

Tests live in `Tests/` (`DiffTests.swift`) and cover the Myers algorithm, line
diff (including intra-line highlights), and three-way merge (clean merges,
conflict detection, and identical-edit deduplication). **Add or update tests in
this target when you change the diff or merge engines** — they are pure Swift
and easy to unit-test, so there is no excuse to leave logic uncovered.

## Project layout

```
Differentialis/
├── App/          App entry point, window/menu/command wiring
├── Diff/         Myers diff (generic), line diff, char highlights, diff3 merge — pure Swift
├── Git/          system-`git` wrapper (Process): log, diff, blobs, refs, changesets
├── Models/       Comparison + ComparisonSource (file / git blob / working copy), saved-comparison store
├── Features/     Text · Image · Folder · Merge · Repo · Welcome views
├── DesignSystem/ Liquid Glass components, theme, the app mark
└── Resources/    Assets.xcassets, etc.

Tests/            Unit tests (DiffTests.swift)
scripts/          changelog.sh, make-dmg.sh
tools/            make_icon.swift
.github/workflows/release.yml   Signed + notarized .dmg on each release
project.yml       XcodeGen project definition (source of truth for the project)
```

## Conventions

- **Swift 6**, SwiftUI-first. Match the existing style of the file you are
  editing (naming, comment density, idioms).
- **No third-party dependencies.** Do not add SPM/CocoaPods/Carthage packages.
  The diff and merge engines (`MyersDiff`, diff3) and the git layer are
  intentionally dependency-free — keep them that way.
- **Git is the system binary.** Drive git through `Process` (see `Git/`); do not
  vendor libgit2 or similar.
- **Keep git and heavy work off the main thread.** Git, diffing, and image work
  must not block the UI — recent fixes moved this work off the main thread, so
  preserve that when touching view bodies or the git layer.
- **Project changes go in `project.yml`**, not the generated `.xcodeproj`.
  After editing `project.yml`, run `xcodegen generate`.
- **Liquid Glass throughout** — reuse the components in `DesignSystem/` for
  toolbars, mode switchers, popovers, and panels rather than rolling new chrome.

## Releases

Releases are cut via `scripts/changelog.sh` and the
`.github/workflows/release.yml` workflow, which builds a Developer ID–signed,
Apple-notarized `.dmg` on a `macos-26` runner with Xcode 26. Bump
`MARKETING_VERSION` in `project.yml` and update `CHANGELOG.md` when cutting a
release.

## Before you finish

- Run the test suite and make sure it passes.
- If you changed `project.yml`, confirm `xcodegen generate` succeeds.
- Keep `CHANGELOG.md` updated for user-facing changes.
</content>
</invoke>
