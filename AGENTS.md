# AGENTS.md

Guidance for AI coding agents working in the **Differentialis** repository.

## What this is

Differentialis is a native **macOS 26 (Tahoe)** app for comparing and merging
text, pasted snippets, images, and folders, with git built in. It is written in
**Swift 6 / SwiftUI**, with AppKit bridges and Apple's Liquid Glass APIs. The diff,
merge, and git engines have no third-party dependencies; **Sparkle is the sole
package dependency**, used for in-app updates. Git runs through `/usr/bin/git`.

There is no backend, database, account system, or runtime service to start. App
content comes from local files, in-memory text, and local git repositories;
preferences and saved comparison definitions live on the user's Mac.

This guide maps ownership and contracts, not every implementation detail. Read the
owning code and tests before editing, and update this guide when those boundaries
change. `project.yml` is authoritative for targets, dependencies, and build settings.

## Requirements

- **macOS 26 (Tahoe)** or later (the app uses Liquid Glass APIs).
- **Xcode 26** / **Swift 6**.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

> The `.xcodeproj` is **generated** and is not committed. Always run
> `xcodegen generate` before building if it is missing or after editing
> `project.yml`.

## Amp orbs

`.agents/setup` installs tools once for the reusable orb snapshot; reruns reuse
installed packages. `.agents/resume` does no installation or authentication.

- **Linux (Debian 12):** setup installs Swift 6.2.4 via Swiftly and its system
  dependencies, plus Python for website checks. New Bash login shells in this
  repository get Swift on `PATH`. No Xcode, AppKit, SwiftUI, or Sparkle is available;
  do not attempt to install Apple's SDKs on Linux. Useful checks are:

  ```bash
  swiftc -swift-version 6 -typecheck Differentialis/Diff/*.swift Differentialis/Models/DiffStats.swift
  python3 scripts/check-site.py
  ```

  These are not substitutes for the macOS test suite. There is no root SwiftPM
  manifest, so `swift test` does not run the app's tests.
- **macOS 26+:** start with full Xcode 26+ selected and Homebrew installed. Setup
  installs missing XcodeGen/Python, generates the project, and resolves the Sparkle
  dependency declared in `project.yml` into the `build/` cache used by CI. It does
  not install Xcode, sign releases, or authenticate with Apple.
- The website is static: no npm install, database, env file, or server is required
  for its checks. `tools/og-card/render.mjs` still requires macOS, Chrome, and `sips`.

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

CI (`.github/workflows/ci.yml`) runs this on a `macos-26` runner for every push to
`main` and every pull request, so keep the suite green.

Tests use **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) with
`@testable import Differentialis`, not XCTest. The `DifferentialisTests` target
includes `Tests/` automatically through XcodeGen.

| Test file | Coverage |
| --- | --- |
| `Tests/DiffTests.swift` | Myers reconstruction/bounded fallback, character and line diffs, whitespace/format diagnostics, git parsing, diff3 conflicts and line styles |
| `Tests/MergeSessionTests.swift` | Merge session state: choices, manual Result edits, unsaved-work tracking, reload, ownership by `Comparison` |
| `Tests/PastedTextTests.swift` | Two-way hunk copying, line correspondence, terminator preservation, UTF-16 ranges, editor decorations |
| `Tests/GitComparisonTests.swift` | Real disposable git repos: index/worktree snapshots, staged reversions, conflicts, unborn HEAD, SHA-256 empty trees |
| `Tests/FolderAndFilterTests.swift` | Package traversal, scan errors, stable identities, composed git filters, file properties |
| `Tests/ThemeImportTests.swift` | `.tmTheme` import, hex colors, observable settings clamping |

**Add or update tests when changing the diff or merge engines.** Extend the relevant
suite for other behavioral changes; prefer observable results over private helper
details. Git integration tests should use the existing temporary-repository fixture,
never the developer's checkout. Native UI/lifecycle, persistence recovery, CLI
installation, and Sparkle still need targeted manual validation; these suites do
not exercise them end to end.

## Project layout

```
Differentialis/
├── App/          Lifecycle, AppModel routing, focused menu commands, concurrency, CLI installer
├── Diff/         Pure Swift Myers, line/character diff, two-way edits, three-way merge
├── Git/          Process runner, git models/parsers, changeset-to-comparison bridge
├── Models/       Comparison sources, pasted document, merge session, JSON stores, Sparkle bridge
├── Features/     Text (including paste/merge), Image, Folder, Repo, Settings, Welcome
├── DesignSystem/ Theme accessors/manager/import, Liquid Glass components, AppKit popover
└── Resources/    Assets.xcassets, Info.plist, bundled differentialis launcher

Tests/            Swift Testing suites; git tests create real temporary repositories
docs/             ROADMAP.md (claimable feature backlog) + README images
site/             Static marketing site (HTML/CSS/JS), screenshots, llms.txt
scripts/          Changelog extraction, DMG packaging, site/README checks
tools/            Icon generator and social-card renderer
.agents/          Orb setup/resume scripts
.github/workflows/ci.yml        Build + tests on every push to main and every PR
.github/workflows/release.yml   Release DMG, signing/notarization, Sparkle appcast
project.yml       XcodeGen project definition (source of truth for the project)
```

## App lifecycle, navigation, and state

App source paths below are relative to `Differentialis/` unless otherwise noted.

- `App/DifferentialisApp.swift` owns the `@State AppModel`, injects it into the
  window environment, creates the Settings scene, and initializes
  `ThemeManager.shared` before windows appear. `AppDelegate` forwards Finder / CLI
  open Apple Events to `AppModel.shared`; this is app-wide state, not a separate
  model per comparison window.
- `App/AppModel.swift` is `@MainActor @Observable`. It owns the route (`welcome`,
  `repository`, `comparison(UUID)`, `changeset(UUID)`), open comparisons and
  changesets, the active repository/refs, stores, updater, and app-level errors.
  Repository probes resolve the working-tree root before installing repository
  state. Request UUIDs stop older opens from overriding newer navigation.
- `App/RootView.swift` renders a fixed-width sidebar beside a `NavigationStack`.
  This intentionally avoids `NavigationSplitView` squeezing the sidebar out of
  multi-pane layouts. Detail subtrees use `.id(comparison.id)` / `.id(changeset.id)`
  to reset view-local state when selection changes. Its startup task processes
  launch arguments and restores open changesets.
- `Models/Comparison.swift` describes one file/text comparison. Modes are text,
  image, folder, merge, binary, and pasted. `Features/ComparisonDetailView.swift`
  dispatches them to feature views. A repository changeset is a **file list plus
  snapshot endpoints**, not a `Comparison`; selecting a file produces one.
- `App/AppCommands.swift` defines `DiffCommandActions`. Active views publish their
  supported actions via `.focusedSceneValue(\.diffCommands, ...)`, and menus use
  `@FocusedValue` to enable commands for the focused scene. Wire new shortcuts here
  and in `Features/KeyboardShortcutsView.swift`, rather than global key handlers.

Typical flow:

```text
Menus / Welcome / drop / CLI / Finder
  -> AppModel -> RootView route
      -> ComparisonDetailView -> feature view -> ComparisonSource -> bytes
      -> RepositoryView / ChangesetDetailView
          -> GitRepository -> changed files + GitSide endpoints
          -> makeComparison -> ComparisonDetailView
```

### Comparison sources and loading

`Models/ComparisonSource.swift` is the byte-loading boundary: `.file`, `.text`,
`.gitBlob`, `.workingCopy`, or `.empty`. The index is represented by `.gitIndex(...)`
using a private sentinel ref inside `.gitBlob`; use the constructor and
`isIndexReference`, not a duplicate magic value. Conflict stages use `:2` / `:3`.

- `.empty` means an **absent side**, not a zero-byte file. Keep that distinction in
  comparisons, image presentation, and `FilePropertiesView`.
- `Comparison.mode(for:_:)` checks folder, then image, then binary, otherwise text.
  Classification can run in a SwiftUI body: `kind` uses extensions and at most a
  4 KB on-disk prefix. Never load a whole file, decode an image, or run git there.
  Unknown git blob types default to text rather than spawning a classification read.
- `loadData` resolves the actual source. `loadText` handles UTF-8 BOM, UTF-16 and
  then Latin-1 fallback. Detection is best-effort, not a guarantee of original
  encoding round-tripping; merged output is saved as UTF-8.
- Adding a source or mode requires checking exhaustive presentation switches,
  properties/path labels, mode dispatch, opening flows, and tests.

### Concurrency rules

`App/Concurrency.swift` provides `await offMain { ... }`, backed by
`Task.detached(priority: .userInitiated)`. Capture inputs, do blocking work there,
then assign view/model state back on the caller's actor. Merely wrapping synchronous
git or diff work in `Task { ... }` does **not** move it off the main actor.

- Git, large file reads, folder scans, diff computation, and pixel-difference
  rendering must not block UI updates. `Process.waitUntilExit` also pumps the run
  loop: invoking it during SwiftUI layout has caused re-entrant layout crashes.
- Preserve cancellation checks **and** input keys/request tokens after awaits.
  Detached work can finish after its caller is cancelled; discard stale results.
- `Unchecked<Value>` is an explicit `@unchecked Sendable` bridge for values such
  as `NSImage`; only use it when concurrent mutation cannot occur.
- AppKit UI stays on the main actor. The privileged CLI installer intentionally
  runs `NSAppleScript` there; it is not a template for background git execution.

## Diff, editing, and merge contracts

`Diff/` contains the dependency-free computation layer. Keep SwiftUI/AppKit out.

- `MyersDiff.swift`: generic `myersDiff` emits indexed equal/delete/insert edits.
  Common prefix/suffix trimming and a bounded edit-distance search prevent runaway
  memory on unrelated inputs. Over-budget inputs yield a valid, non-minimal block
  replacement; do not remove this safety fallback for prettier diffs.
- `CharDiff.swift` computes similarity and intra-line highlights together, with a
  long-line guard. `LineDiff.swift` builds aligned `DiffRow`s, stats, and collapsible
  `DiffDocument` sections. Similar delete/insert pairs become modified rows;
  unrelated pairs remain deletions/insertions. Whitespace policy changes comparison
  keys, not the displayed source text.
- `LineDiff.split` recognizes LF/CRLF/CR, drops the phantom segment after a final
  newline, and represents empty input as one empty line. Content equality therefore
  does not imply byte equality: `textFormatDifferences` in `TextComparisonView.swift`
  separately reports terminator/final-newline differences.
- Coordinate systems matter: row line numbers are **1-based**; `TextHunk` ranges
  are **0-based, half-open line ranges**; character highlights use Swift `Character`
  offsets; `NSTextView`/`NSRange` use **UTF-16**. Convert through
  `TwoWayMerge.utf16Ranges`; test emoji and combining characters.
- `TwoWayMerge.swift` groups changed rows, maps lines for synchronized scrolling,
  and copies a hunk in either direction. Untouched terminators remain exact;
  inserted lines use the target's dominant ending (source fallback if none), and
  the target's final-newline state is preserved subject to an empty last line.
- `ThreeWayMerge.swift` merges base/left/right, deduplicates identical edits, and
  allows compatible adjacent edits without falsely conflicting. Content hunks and
  `MergeLineStyleDecision` are separate: two conflicting format edits also require
  resolution. `mergedText` emits git-style markers for unresolved content; never
  silently save just the chosen/left side of an unresolved conflict.

### Feature owners

| Feature | Owning code and responsibilities |
| --- | --- |
| Text diff | `Features/Text/TextComparisonView.swift`: async load, whitespace options, split/unified layout, gaps, navigation, format diagnostics; `DiffRowView.swift` renders highlighted rows |
| Pasted text | `PastedTextComparisonView.swift`: live analysis with typing debounce, editor/diff presentations, hunk actions; `PastedTextAnalysis.swift` shapes rows into UTF-16 decorations and scroll mappings |
| Native editors | `DiffTextEditor.swift`: TextKit 1 `NSTextView`, line-number ruler, SwiftUI representable, `PastedTextEditorController` for edits/scroll synchronization/shared undo |
| Three-way merge | `MergeView.swift`: Review and editable Result (`PlainCodeEditor.swift`), hunk choices, format resolution, save warnings and atomic UTF-8 save |
| Images | `Features/Image/ImageComparisonView.swift`: Two-Up, One-Up/blink, Split, Difference; `ImageSupport.swift`: shared zoom/pan gestures, checkerboard, Core Image difference renderer |
| Folders | `Features/Folder/FolderScanner.swift`: inventory and byte comparison; `FolderComparisonView.swift`: filtering, issues, selection, embedded file comparison |
| Git | `Features/Repo/RepositoryView.swift`: history/working changes; `GitChangesetView.swift` and `ChangesetDetailView.swift`: file lists/detail; `CustomComparisonPopover.swift`: endpoint selection; `GitFileFilterBar.swift`: shared path/type/status filtering |
| Metadata/binary | `Features/FilePropertiesView.swift`: async metadata comparison for sources; `BinaryComparisonView.swift`: non-text fallback |

Important feature invariants:

- `PastedTextDocument` is a reference type retained by `Comparison`, so its text
  survives detail-view teardown when navigating away. It is not persisted across
  launches. Programmatic edits should go through `PastedTextEditorController` while
  editors are mounted to preserve undo, caret, and scroll; its shared undo manager
  must not outlive its text views.
- `MergeSession` is a reference type retained by `Comparison` for `.merge`, holding
  the hunk and line-style choices, Result text, and Review/Result tab, so a merge
  survives detail-view teardown; `MergeView` loads only when `needsLoad`. It is not
  persisted across launches. `hasUnsavedChanges` is set by any choice, Result edit,
  or Reset from Review, and cleared by a load or successful save. Refresh and Close
  ask before discarding it (`confirmDiscardingChanges`); Quit asks in
  `AppDelegate.applicationShouldTerminate`.
- In `MergeSession`, manually edited `resultText` is authoritative (`resultDirty`).
  Hunk/format changes do not regenerate dirty output; “Reset from Review” explicitly
  does. Refresh reloads the sources and resets edits. Saving warns about remaining
  conflict marker fragments; an unresolved line-style choice blocks saving, edited
  or not, until reviewed. Save rewrites every terminator to the chosen line ending
  (`ThreeWayMerge.normalizingLineEndings`), so typed or pasted lines can't mix styles.
- Editable code views (`DiffTextEditor`, the merge Result's `PlainCodeEditor`) use
  `NSTextView.configureForPlainCode()`; never use SwiftUI `TextEditor` for code,
  since it follows the system's smart-quote, dash, and autocorrect settings.
- Images load bytes off-main, then construct lazy-decoding `NSImage`s. Expensive
  Difference rendering runs off-main only when that mode needs it and is guarded
  by image revision. Preserve shared zoom/pan and one-sided image handling.
- Folder scans include hidden files and package contents, prune `.git` directories,
  compare symlink destinations rather than targets, and stream regular-file
  equality in 1 MB chunks. Surface read/enumeration issues instead of claiming
  unreadable content is identical. Entry identity is the relative path.

## Git snapshot semantics

`Git/GitRepository.swift` owns synchronous git execution and parsing;
`Git/GitModels.swift` defines data; `Git/GitChangeset.swift` maps changed files to
sources and resolves custom comparisons. UI-created repositories must be rooted
at the working-tree root: `makeComparison` is called from view bodies and uses
`repo.url` directly, never `git rev-parse` during rendering.

- `GitSide` distinguishes reference, stage-0 index, conflict index stage, and
  working copy. **Staged** compares selected reference → index; **Unstaged** compares
  index → worktree (the selected reference is irrelevant).
- **All Changes is not just reference → worktree.** It combines staged, unstaged,
  and untracked paths into one row per path. A staged-only row uses ref → index;
  an unstaged-only row uses index → worktree. If both layers changed, index →
  worktree preserves staged bytes even when the worktree has reverted to HEAD.
  Per-file `GitFileComparison` overrides changeset-wide endpoints.
- Unmerged porcelain state is authoritative. Coalesce duplicate conflict entries,
  compare stage 2 (Ours) with stage 3 (Theirs), and represent missing stages as
  absent sources. Do not try to read stage 0 for an unresolved conflict.
- `CustomSide` is the persisted UI definition; `ResolvedChangeset` has concrete
  `GitSide`s and files. The custom comparison's A side is reference/commit, while B
  may be working copy. Commit changesets compare the first parent (including merge
  commits); root commits use `diff-tree --root`.
- Unborn HEAD is valid: empty history, usable staged/worktree comparisons. Derive
  the empty tree through git, not a hard-coded SHA-1 hash (SHA-256 repos are tested).
- Keep `-z` NUL-delimited filename parsing. Rename order is **old/new** in
  `diff --name-status -z` but **new/old** in `status --porcelain -z`.
  `GitChangedFile.id` derives from status and paths so refresh preserves selection.
- `runData` uses `Process` argument arrays, null stdin, disabled terminal prompts
  and optional locks, and stable locale. Drain stdout/stderr concurrently before
  waiting to avoid pipe deadlocks. Use `runData` for bytes; `run` is lossy UTF-8 for
  metadata, so invalid bytes do not blank an entire result.

## Persistence and appearance

Stores are observable JSON-backed objects under
`~/Library/Application Support/Differentialis/`:

| File | Owner / saved data |
| --- | --- |
| `saved-comparisons.json` | `ComparisonStore`: named custom endpoint definitions (`SavedComparison`) |
| `recent-projects.json` | `RecentProjectsStore`: up to 16 repositories, deduplicated by standardized root path, most recent first |
| `open-changesets.json` | `OpenChangesetStore`: titles, repository paths, and endpoint definitions for restoration |
| `Themes/*.json` | `ThemeManager` / `ThemeFile`: imported and edited custom color themes |

The three comparison/project stores write atomically, use `LenientDecodable` to
skip malformed entries, and move wholly corrupt files to `.corrupt`. Preserve
compatibility when changing Codable models. Do not purge projects merely because
a volume is offline. Restoring changesets re-runs git against current repository
state; it is not a saved byte snapshot. Failed restores are skipped without an
alert or immediate rewrite. Ordinary file-comparison tabs and pasted texts are
session-only.

- `DesignSystem/Theme.swift` exposes semantic colors, fonts, fills, and canvas
  through `ThemeManager.shared`; views observe these reads. Reuse it instead of
  hard-coding dark-only colors or code font sizes.
- `ThemeManager` persists appearance, separate light/dark theme IDs, font, and
  gradient settings in `UserDefaults`. It sets `NSApp.appearance` so AppKit menus
  and popovers match SwiftUI and tracks system appearance for Auto.
- `ThemeFile.swift` defines/validates the JSON schema and custom identity;
  `TmThemeImport.swift` converts plist color schemes. Both import paths store the
  app's JSON format. Settings/editor UI lives in `Features/Settings/`.
- Corrective assignments inside `@Observable` `didSet` must be conditional:
  assigning the same property unconditionally re-enters the generated accessor
  and can overflow the stack. Preserve the clamp-and-return pattern.
- Reuse `GlassModifiers`, `GlassSegmentedControl`, and `PathBar` for chrome.
  `SemitransientPopoverPresenter` keeps work-in-progress popovers open across app
  switches. Its synchronous programmatic close and callback invalidation during
  teardown prevent callbacks into dismantled SwiftUI bindings.

## CLI, Finder, and updates

- `Resources/differentialis` resolves paths and invokes
  `open -b app.differentialis.Differentialis`, not app-name lookup (which can pick
  a stale Debug install). `AppModel.open(urls:)` handles one repository, two files
  or two folders, or three files ordered **base, left, right**; invalid combinations
  produce an in-app error. Launch arguments and Apple Events share that routing.
- `Resources/Info.plist` declares folder/item document types as Viewer/Alternate
  so Finder and already-running-app opens reach `AppDelegate` without making the
  app the default handler. Preserve this when changing launching behavior.
- `CommandLineToolInstaller` installs a **copy** of the bundled script at
  `/usr/local/bin/differentialis` through an administrator prompt. The app menu
  toggles installation/removal; this is privileged user-driven work.
- `Models/SparkleUpdater.swift` isolates Sparkle from views via `AvailableUpdate`.
  Scheduled checks use `Features/UpdateBanner.swift`; manual checks and actual
  installation use Sparkle's UI. Skip persists a build number, Later only dismisses
  the offer. Delegate/KVO callbacks re-enter MainActor under Sparkle's main-thread
  callback contract.
- `Info.plist` contains the automatic-check setting, latest-release appcast URL,
  and public EdDSA key. Keep these aligned with release signing; private signing
  keys belong in CI secrets, never source or logs.

## Conventions

- **Swift 6**, SwiftUI-first. Match the existing style of the file you are
  editing (naming, comment density, idioms).
- **No additional third-party dependencies.** Sparkle is the existing exception
  for updates. Keep diff/merge/git dependency-free; do not add packages for these
  engines or vendor libgit2.
- **Git is the system binary.** Drive git through `Process` (see `Git/`); do not
  vendor libgit2 or similar.
- **Keep git and heavy work off the main thread.** Git, diffing, and image work
  must not block the UI — recent fixes moved this work off the main thread, so
  preserve that when touching view bodies or the git layer.
- **Project changes go in `project.yml`**, not the generated `.xcodeproj`.
  After editing `project.yml`, run `xcodegen generate`.
- **Liquid Glass throughout** — reuse the components in `DesignSystem/` for
  toolbars, mode switchers, popovers, and panels rather than rolling new chrome.

## Autonomous roadmap work

The backlog lives in [`docs/ROADMAP.md`](docs/ROADMAP.md). Use this procedure when asked to pick up
roadmap work without a specific item. **You open a PR; you never merge it.**

1. **Sync and survey claims.** `git fetch origin`, then find claimed items:
   ```bash
   git branch -r --list 'origin/roadmap/*'
   gh pr list --state open --search 'R-0 in:title,body,head' --json number,title,headRefName
   gh pr list --state open --label roadmap --json number,title,headRefName
   ```
   An item is **claimed** if a remote branch `roadmap/R-XXX-*` or an open PR mentions its ID.
   Also check `gh issue list` for open issues (a maintainer-filed bug outranks the backlog, but
   only take it if it is small).
2. **Pick one item.** Choose the lowest-numbered `Open`, unclaimed, size **S** item. Don't take
   `M` unless no `S` remains, never take `Epic`/`Blocked` items, and never more than one item
   per PR. If nothing qualifies, stop and report that instead of inventing work.
3. **Claim it first.** Create branch `roadmap/R-XXX-short-slug` from latest `main`, push it
   immediately (an empty commit is fine), and open a **draft** PR titled `R-XXX: <feature>`.
   Re-check step 1 afterwards; if someone else claimed the same ID earlier, delete your branch,
   close your PR, and pick another item.
4. **Implement within scope.** Touch only what the item needs. Follow the Conventions below
   (no new dependencies, git/heavy work off the main thread, project changes in `project.yml`).
   Don't refactor unrelated code or edit other roadmap items.
5. **Test.** Put logic in pure Swift where possible and add Swift Testing tests in `Tests/` (required for
   `Diff/` and `Git/` changes). Run the checks for your platform (see *Amp orbs*): on Linux the
   typecheck command and, if you touched docs/site, `python3 scripts/check-site.py`; on macOS the
   full `xcodebuild test`. UI code can't be compiled or run on Linux — say so in the PR, keep UI
   changes minimal and mirror existing view patterns, and let CI (`macos-26`) be the judge.
6. **Update docs.** Set the item's status to `Shipped (next version)` in `docs/ROADMAP.md`, add a
   `CHANGELOG.md` entry under `[Unreleased]` for user-facing changes, and update README
   features/shortcuts, `KeyboardShortcutsView`, and `site/` copy (FAQ twice, `llms.txt`,
   sitemap `lastmod`) when behavior they describe changes.
7. **Open for review.** Fill in the PR template (item ID, what was and wasn't tested), mark the PR
   ready for review, add the `roadmap` label if it exists, and wait for CI. Fix CI failures you
   caused. Then **stop**: do not merge, enable auto-merge, approve your own PR, push to `main`,
   tag, release, or bump `MARKETING_VERSION`.

Safety rules:
- Never force-push over someone else's branch, close others' PRs, or delete branches you didn't
  create.
- Don't change CI, release workflows, signing, Sparkle keys/appcast, or `.agents/` scripts as part
  of a feature PR.
- If a task is ambiguous, larger than expected (> ~400 changed lines), or needs a product decision,
  stop, keep the draft PR, and write what you learned in its description rather than guessing.
- Don't add roadmap items you're not going to build in the same PR; add them in a separate
  docs-only PR.

## Website

`site/` is the static marketing site at differentialis.app (deployed by Vercel with
`site/` as its root). When features change, keep its copy, the FAQ, and the plain-text
summaries in step:

- The FAQ appears twice in `site/index.html`: the visible `#faq` section and the
  `FAQPage` JSON-LD in `<head>`. Edit both; `scripts/check-site.py` fails if the
  questions drift apart.
- `site/llms.txt` is a plain-text product summary for AI assistants; update it with
  feature or requirement changes.
- Bump `<lastmod>` in `site/sitemap.xml` and the `WebPage` node's `dateModified` together when
  the page content changes; the check fails if they differ.
- When `MARKETING_VERSION` changes, update the site's version too: both `data-version` spans,
  `softwareVersion` in the JSON-LD, and the "Current version" line in `llms.txt`. The check
  compares all three with `project.yml`, so a release bump fails CI until the site follows.
- The FAQ check compares answer text as well as questions. Each visible answer is a single `<p>`
  right after its `<summary>`; in the JSON-LD write `⌘N` as `Command-N` and drop HTML tags.
- `site/404.html` is served for unknown paths, so its references are root-relative.
  `site/vercel.json` redirects `/index.html` to `/`. Favicons (`favicon.ico`,
  `apple-touch-icon.png`, `assets/icon-192.png`) are cropped from `assets/icon.png`.
- Screenshots live in `site/assets/screens/` (WebP); the README gallery reuses them.
- The social card (`site/assets/og.jpg`) is generated from `tools/og-card/`: edit
  `card.html` and run `node tools/og-card/render.mjs` (needs Google Chrome).

## Releases

`scripts/changelog.sh <version>` extracts release notes from `CHANGELOG.md`; it
does not publish a release. Bump `MARKETING_VERSION` in `project.yml` and update
the changelog when cutting one, and in the same commit bump the site's version
(both `data-version` spans and `softwareVersion` in `site/index.html`, and the
"Current version" line in `site/llms.txt`); `scripts/check-site.py` fails CI
until they match. Publish the GitHub release promptly after that commit lands,
since Vercel deploys `main` and the site then advertises the new version.

`.github/workflows/release.yml` runs on a published GitHub Release or a manual
tag input. It checks out that tag, builds on macOS 26/Xcode 26, overrides the
marketing version from the tag, and derives Sparkle's `CURRENT_PROJECT_VERSION`
from the full-history commit count. Preserve monotonic build numbers.

`scripts/make-dmg.sh` packages the app. With configured CI secrets, the workflow
signs Sparkle's nested helpers/framework and the app deepest-first with Developer
ID/hardened runtime, then notarizes/staples the DMG. Without signing configuration
it falls back to ad-hoc signing; do not describe that build as notarized. The
Sparkle appcast is generated over the final DMG and uploaded only when its private
key is configured. Check both `project.yml` and the workflow's Sparkle CLI version
when updating Sparkle. Publishing a release triggers this external delivery flow.

## Before you finish

- Run the relevant checks above. App changes require the macOS suite; Linux
  type-checks cannot establish app build/test success. Report unavailable checks.
- For native UI changes, render and inspect the affected states on macOS, including
  light/dark appearance and relevant empty/error/one-sided states. Linux browser
  previews cannot verify SwiftUI/AppKit rendering.
- If you touched the README or `site/`, run `python3 scripts/check-site.py`.
- If you changed `project.yml`, confirm `xcodegen generate` succeeds.
- Keep `CHANGELOG.md` updated for user-facing changes.
- For roadmap work, follow [Autonomous roadmap work](#autonomous-roadmap-work) and never merge.
