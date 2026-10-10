# Differentialis roadmap

Where the product is going, and a backlog of small features that agents (or people) can pick up
one at a time. Read [AGENTS.md](../AGENTS.md#autonomous-roadmap-work) before claiming anything; its architecture sections say which code owns what.

_Last reviewed: 2026-10-10, at v0.3.1._

## Where we are (v0.3.1)

Shipped: Myers text diff with character-level highlights (split/unified), Paste Text comparisons
with per-change copy, image diff (Two-Up / One-Up / Split / Difference), recursive folder diff,
three-way merge, git history and changed-files views, Custom Comparison (ref/commit/working copy,
saved), themes and fonts, a bundled `differentialis` CLI launcher, and Sparkle self-update.
See the [changelog](../CHANGELOG.md). There are no open GitHub issues; this file is the backlog.

## Product direction

1. **Be the best "what changed?" viewer on the Mac.** Fast, correct, and good-looking diffs for
   text, images, and folders, including large and awkward inputs.
2. **Be a first-class git companion.** Drop-in difftool/mergetool, plus read-only views that git
   users reach for daily (blame, file history). Staging and committing are *out of scope* for now.
3. **Stay small and dependency-free.** Engines are pure Swift; Sparkle is the only dependency.
4. **Be scriptable.** CLI and URL scheme so other tools can open Differentialis.

## Themes (in rough priority order)

| Theme | Why |
| --- | --- |
| Git tool integration | Biggest adoption lever: `git difftool`/`mergetool` should just work. |
| Diff quality & scale | Moves, large files, encodings: trust in the result. |
| Navigation & review | Faster reading of big diffs and folder comparisons. |
| Git depth | Blame/file history/stash: read-only views of data we already can fetch. |
| Export & sharing | Get a diff out of the app (patch, HTML, PDF). |
| Platform polish | Accessibility, localization, Shortcuts. |

## Backlog

Each item is meant to fit **one small PR** (roughly under 400 changed lines, one feature area).
Larger items are listed as *epics* and must be split into new `S` items before being started.

Size: **S** ≈ a few hours, **M** ≈ a day (only take M if no S is available). Item IDs are stable;
never renumber. When an item ships, change its status to `Shipped (vX.Y.Z)` in the same PR.

Status values: `Open`, `Shipped (vX.Y.Z)`, `Blocked: <reason>`, `Epic`. **Whether an item is
claimed is not recorded here** — it is determined by branches and PRs (see AGENTS.md).

### Diff quality & scale

| ID | Size | Status | Feature | Where / Tests |
| --- | --- | --- | --- | --- |
| R-001 | S | Open | **Ignore case** option for text diff (alongside whitespace-insensitive matching). | `Diff/LineDiff.swift`, `TextComparisonView`; unit tests in `Tests/DiffTests.swift` (Swift Testing). |
| R-002 | S | Open | **Ignore blank lines** option for text diff. | `Diff/LineDiff.swift`; engine tests. |
| R-003 | M | Open | **Moved-line detection**: mark deleted/added lines that moved rather than changed. | `Diff/` (new pure-Swift pass over `LineDiff` output); engine tests. |
| R-004 | S | Open | **Large-file guard**: above a size/line threshold, show a notice and diff off-main with a cancel button instead of freezing. | `TextComparisonView`, `Diff/`; test the threshold helper. |
| R-005 | S | Open | **Show detected text encoding** (UTF-8/BOM, UTF-16, Latin-1 fallback already decoded by `loadText`) in File Properties, and warn when a merge save will convert to UTF-8. | `Models/ComparisonSource.swift`, `FilePropertiesView`; tests in `Tests/FolderAndFilterTests.swift`. |
| R-006 | S | Open | **Word-level diff granularity** option for intra-line highlights (word vs character). | `Diff/CharDiff.swift`; engine tests. |

### Navigation & review

| ID | Size | Status | Feature | Where / Tests |
| --- | --- | --- | --- | --- |
| R-010 | S | Open | **Change minimap / overview ruler** beside the diff showing where changes are. | `Features/Text/`; unit-test the pure position math. |
| R-011 | S | Open | **Go to line** (`⌘L`) in text and diff views. | `App/AppCommands.swift`, `Features/Text/`; add to `KeyboardShortcutsView` and README table. |
| R-012 | S | Open | **Find in diff** (`⌘F`) with next/previous match. | `Features/Text/`; test the matching helper. |
| R-013 | S | Open | **Folder diff: sort** by name/status/size/modified date. | `Features/Folder/`; test sort comparator. |
| R-014 | S | Open | **Folder diff: ignore patterns** (e.g. `.git`, `.DS_Store`, `node_modules`) editable in Settings. | `Features/Folder/FolderScanner.swift`; `Tests/FolderAndFilterTests.swift`. |
| R-015 | S | Open | **Folder diff: compare by content hash vs. size+mtime** toggle. | `FolderScanner.swift`; scanner tests. |
| R-016 | S | Open | **Mark file as reviewed** in folder and git changeset lists (session-only checkmark and progress count). | `Features/Folder/`, `Features/Repo/`. |

### Git tool integration & depth

| ID | Size | Status | Feature | Where / Tests |
| --- | --- | --- | --- | --- |
| R-020 | S | Open | **`differentialis --help` / `--version`** for the bundled CLI launcher. | `Differentialis/Resources/differentialis` launcher script, `CommandLineToolInstaller.swift`. |
| R-021 | M | Open | **Git difftool/mergetool setup**: a Settings button (and documented snippet) that writes `difftool.differentialis` / `mergetool.differentialis` into global git config; show current status. | `Git/`, `Features/Settings/`; test config-argument builder with a temp `GIT_CONFIG_GLOBAL`. |
| R-022 | M | Open | **`differentialis://` URL scheme** to open a path or comparison. Update README and site copy. | `App/`, `project.yml` (then `xcodegen generate`); test URL parsing. |
| R-023 | S | Open | **Compare with previous version of a file** (file history list for one path via `git log --follow`). | `Git/GitRepository.swift`, `Features/Repo/`; temp-repo tests in `Tests/GitComparisonTests.swift`. |
| R-024 | M | Open | **Read-only blame** view for a file at a ref (`git blame --porcelain` parser). | `Git/`, `Features/Repo/`; parser unit tests with fixture output. |
| R-025 | S | Open | **Stash browser**: list stashes and open one as a changeset. | `Git/`; temp-repo tests. |
| R-026 | S | Open | **Commit search** in history by message/author. | `Features/Repo/RepositoryView.swift`, `Git/`; test the filter/args. |

### Export & sharing

| ID | Size | Status | Feature | Where / Tests |
| --- | --- | --- | --- | --- |
| R-030 | S | Open | **Copy / save as unified patch** for a text comparison. | `Diff/` (patch formatter, pure Swift), toolbar item; formatter tests. |
| R-031 | S | Open | **Export diff as standalone HTML**. | New pure formatter plus save panel; formatter tests. |
| R-032 | M | Open | **PDF export** of a comparison (README's long-standing roadmap item). Depends on R-031's renderer being reusable, otherwise split. | `Features/`; render helper tests where practical. |

### Platform polish

| ID | Size | Status | Feature | Where / Tests |
| --- | --- | --- | --- | --- |
| R-040 | S | Open | **VoiceOver labels** for diff rows, change bars, and image mode switcher. | `Features/Text/DiffRowView.swift`, `Features/Image/`. |
| R-041 | S | Open | **Reduce Motion / Increase Contrast** support (stop One-Up auto-blink, stronger change tints). | `Features/Image/`, `DesignSystem/Theme*.swift`. |
| R-042 | S | Open | **Recent comparisons** list on the welcome screen (files/folders, not just repos). | `Models/` (new store modelled on `RecentProjectsStore`), `Features/Welcome/`; store tests. |

### Epics (split before starting)

| ID | Status | Epic |
| --- | --- | --- |
| R-100 | Epic | Syntax highlighting inside diffs (needs a no-dependency tokenizer design first). |
| R-101 | Epic | Directory/package (`.app`, `.xcassets`) aware folder diff. |
| R-102 | Epic | Editable text diff (edit either side with live re-diff, save). |
| R-103 | Epic | Shortcuts/App Intents actions ("Compare two files"). |
| R-104 | Epic | Localization. |
| R-105 | Epic | Audio/video and PDF-content comparison. |

## Adding to the roadmap

Open a PR that appends a row with the next free `R-` ID in the right section. Keep entries to one
sentence, name the files/tests, and prefer `S`. Remove nothing; mark dropped items
`Blocked: <reason>` or `Dropped: <reason>`.
