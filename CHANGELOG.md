# Changelog

All notable changes to Differentialis are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

When cutting a release, add a section here and use it as the release notes:
`gh release create vX.Y.Z --notes "$(scripts/changelog.sh X.Y.Z)"`.


## [Unreleased]

## [0.4.0] — 2026-10-28

### Added
- **`git difftool` and `git mergetool` support.** The `differentialis` command-line tool takes
  `--wait`, which blocks until you finish in the app, and `--output <file>` for merges: **Save**
  writes the merged result straight to git's file and returns to git, which marks it resolved only
  when no conflict markers remain. The README has the `~/.gitconfig` snippet
  ([#22](https://github.com/yennster/differentialis/issues/22)). Reinstall the command-line tool
  from the app menu to get the new options.

### Fixed
- Text files with no recognised extension (`Makefile`, `.env`, `notes`, …) no longer open as
  **binary** when they contain non-ASCII text
  ([#14](https://github.com/yennster/differentialis/issues/14)). A multi-byte character that
  straddles the 4 KB sniff no longer breaks detection, UTF-16 files with a BOM are recognised
  as text, and other NUL-free 8-bit text (such as Latin-1) diffs as text instead of showing the
  size/SHA card.
- Choosing **Base** for a merge hunk (**Use Base** on a conflict, or **Base** from a resolved hunk's
  ↻ menu) no longer turns the hunk into plain unchanged context. It now shows **Took Base** and keeps
  its source menu, so you can switch back to Left, Right, or Both without refreshing
  ([#13](https://github.com/yennster/differentialis/issues/13)).
- Picking **Both** from the ↻ menu of a hunk where both sides made the same edit no longer
  duplicates its lines, and the hunk label now reads **Took Both** instead of "Both (same)".
- A **3-way merge** now keeps your conflict choices, line-ending choice, Result edits, and
  Review/Result tab when you switch to another sidebar item and back
  ([#11](https://github.com/yennster/differentialis/issues/11)). **Refresh** (`⌘R`) and **Close**
  now ask to save first when the merge has unsaved work, and quitting with an unsaved merge asks
  for confirmation.
- The merge **Result** editor no longer changes what you type: straight quotes stay straight,
  `--` stays two hyphens, and autocorrect and text replacement are off, whatever the system text
  settings say. **Save Merged…** now writes every line with the merge's line ending, so a line
  typed or pasted into a CRLF merge is saved as CRLF instead of a bare LF
  ([#12](https://github.com/yennster/differentialis/issues/12)).
- A commit hash pasted into **Custom Comparison** can no longer be read by git as an option: a
  value starting with `-` (such as `--output=<file>`) is rejected in the popover, dropped from
  saved and restored comparisons, and always passed to git after `--end-of-options`. A side must
  now name a commit: an unknown hash (or a tree-only object) reports "Unknown commit or reference"
  instead of a raw git error, and a branch that shares its name with a tracked file compares
  instead of failing as "ambiguous"
  ([#17](https://github.com/yennster/differentialis/issues/17)).

## [0.3.1] — 2026-10-10

### Fixed
- The **Check for Updates…** menu item's enabled state is now updated on the main actor, removing
  a Swift concurrency warning that would become an error under stricter checking.

## [0.3.0] — 2026-10-10

### Added
- **Paste Text comparisons** — compare snippets without saving them to files first
  ([#5](https://github.com/yennster/differentialis/issues/5)). **File ▸ New Pasted Text Comparison**
  (`⌘T`) or the new **Paste Text** card on the welcome screen opens two side-by-side editors; paste
  or type into each and the diff updates live as you edit — changed lines are tinted with change
  bars, changed characters are highlighted, line numbers run down each side, and the two panes
  scroll together so matching lines stay level.
- **Copy a change across** in a pasted-text comparison: click into a change (or step to it with
  `⌘]` / `⌘[`), then **Copy to B** (`⌥⌘→`) or **Copy to A** (`⌥⌘←`) to make that side match. The next
  change is selected after each copy, and every edit — including copies, Paste, Clear, and **Swap A
  / B** (`⇧⌘S`) — is undoable.
- A pasted-text comparison can flip to the familiar **Diff** view (split or unified, collapsed
  unchanged regions) from the Edit / Diff switch in its toolbar.

## [0.2.2] — 2026-09-02

### Added
- Custom themes can be **converted between Light and Dark** — visible Edit / Convert / Remove
  buttons appear beside the row when a custom theme is selected (also in the card's context
  menu). Converting re-derives the canvas for the target appearance and rescales accents for
  contrast, rather than just moving the theme.
- **Picking a theme for the other appearance switches to that appearance**, so the choice is
  immediately visible.
- File status badges (M, A, D, ?) show a **tooltip naming the status** — "?" is git's
  untracked marker.

### Fixed
- The file lists in repository, changeset, and folder views now **take on the theme's canvas
  color** instead of keeping the system list background (invisible with the default dark theme,
  obvious with custom ones).

## [0.2.1] — 2026-09-02

### Changed
- An **added or deleted image now uses the full canvas**: the existing side fills the view with
  a status chip ("Added — this file doesn't exist on side A"), instead of half the view going to
  a placeholder pane.
- The **Two-Up image divider is draggable** (in both orientations) to resize the panes;
  double-click it to recenter.
- The **split text diff's column divider is draggable** too — the A/B headings follow the
  split, the width is remembered across comparisons, and double-click recenters.

### Fixed
- Selecting a file in a custom comparison, saved comparison, or folder comparison no longer
  resets the file-list pane width (the same stable-pane fix 0.2.0 applied to the repository
  view now covers every split view).

## [0.2.0] — 2026-09-02

### Added
- **Settings window** (⌘,) in the application menu, covering appearance, color themes, and the
  code font size.
- **Light and Dark appearance with an Auto mode** that follows the system setting (the default).
  The whole UI — canvas, hairlines, keycaps, welcome screen — now adapts to either appearance.
- **Color themes**, chosen per appearance: Differentialis, Mariana, Monokai, One Dark, and
  Solarized for dark; Differentialis, Solarized, and GitHub for light.
- **Adjustable code font size** for text comparisons and merges — ⌘+ / ⌘− / ⌘0 in the View menu,
  or from Settings.
- The sidebar now lists **saved comparisons and open changesets under their project**; entries
  whose repository is no longer in Projects keep their own section.
- **Open changesets persist across launches** — custom comparisons you had open are re-resolved
  against their repository on the next start (skipped quietly if the repo is unavailable).
- **Choose the code font family** in Settings — any installed fixed-pitch font, alongside the
  size controls.
- **Theme import and export.** Themes are simple JSON files (export the current theme from
  Settings to get an editable template); imported themes live in Application Support and can be
  removed from their card's context menu.
- **`.tmTheme` import** — bring in any TextMate-format color scheme (e.g. from
  colorsublime.github.io). The importer uses the theme's own `markup.inserted/deleted/changed`
  diff colors when defined and otherwise hue-matches its accent colors onto
  added/removed/modified/conflict slots.
- **A custom theme editor** in Settings — build a theme with color pickers over a live diff
  preview, then save to apply; right-click any theme card to start a new theme from it or edit
  a custom one.
- **Pinch-to-zoom on text comparisons and merges** resizes the code font with the trackpad,
  matching the existing image zoom gesture.
- **Adjustable background gradient** in Settings — separate Light and Dark sliders (with live
  swatches) control how much the canvas shades from top to bottom, from flat up to double the
  theme's own shading.

### Fixed
- The A and B column headings above a split comparison now align with the two columns: A owns the
  left half and B starts at the midpoint, with the view controls tucked into B's half (dropping to
  a second row in narrow windows).
- The repository toolbar separates the repo utilities (refresh, Finder, Terminal) from the Custom
  Comparison action instead of merging all four into one glass group.
- Light appearance readability: recessed backgrounds (diff scroller, segmented controls, commit
  fields, image checkerboard) no longer gray out the whole surface on a light canvas.
- The History and Files pane headers in the repository view share one fixed height, so
  "300 commits" and "Files" sit on the same line across panes.
- Selecting a file or commit no longer resets the repository view's pane widths — the detail
  pane keeps a stable identity, so the split dividers stay where you dragged them.

## [0.1.9] — 2026-07-22

### Fixed
- Opening a Custom Comparison no longer risks leaving the app unresponsive when the popover and
  repository view are dismissed in the same update.

## [0.1.8] — 2026-07-22

### Added
- **Whitespace-aware text comparison.** Choose exact matching, ignore leading/trailing whitespace,
  or ignore all whitespace; the preference carries across comparisons. Files that differ only by
  line endings or their final newline now show that distinction instead of appearing identical.
- **Fast file filtering** for folder comparisons, repository working changes, and commit
  changesets, including name, extension, and status filters with live result counts.
- **Editable merge results.** The Result view is now the exact text that will be saved, supports
  direct edits, clearly marks manual changes, and can be reset from the hunk selections.
- Image comparison now includes explicit **zoom in, zoom out, and Fit** controls, shared pan/zoom
  in Split mode, and a keyboard- and VoiceOver-adjustable split divider.

### Fixed
- The Custom Comparison popover stays open when switching to another app, while still dismissing
  after an in-app outside click. Pasted commit hashes are remembered per repository across popover
  openings and app launches.
- **Git staged and unstaged comparisons now use the correct snapshots.** Staged changes compare a
  reference with the index, unstaged changes compare the index with the working tree, and All
  Changes keeps a coherent layer-aware row even when staged and working edits cancel each other.
  Conflict stages, repositories without a first commit, and SHA-256 repositories are handled too.
- Three-way merge no longer reports conflicts for adjacent independent edits, and text diff no
  longer pairs unrelated neighboring lines as an in-place modification. Single-newline files,
  one-sided formatting edits, and mixed line endings round-trip correctly; incompatible line-ending
  choices are now resolved explicitly.
- Image Split mode now reveals A and B with one shared viewport, while Swap consistently swaps the
  actual sides in every mode. Difference images are rendered only when that mode is selected.
- Folder scans include package contents, report unreadable files and enumeration failures instead
  of calling them identical, and retain stable selection while filtering.
- Opening too many or mismatched inputs now reports a precise error, and a slow repository open can
  no longer replace a newer request. Repository history and diff failures remain visible instead of
  turning into misleading empty states.
- Binary checksums stream from disk and file metadata no longer loads an entire large file merely
  to inspect it.

### Improved
- Comparison controls, status badges, segmented selections, and the image divider have stronger
  contrast and more complete accessibility labels and selected-state traits.
- Comparison headers give both source paths room to breathe and move controls to a second row when
  needed, instead of truncating paths beside unused space or crowding narrow windows.

## [0.1.7] — 2026-07-10

### Fixed
- **No more hangs or crashes on large or unusual files.** The Myers diff engine now trims common
  prefixes/suffixes and caps its search (degrading to a block replacement past the cap) instead of
  allocating unbounded memory on large, dissimilar files — comparing big generated files (lockfiles,
  logs) no longer spins forever and OOM-kills the app. The same guard, plus a long-line cutoff,
  applies to intra-line character highlighting.
- **Fixed a crash when opening comparisons of extensionless or unknown-type files.** Content-type
  detection no longer runs a synchronous `git` subprocess (or reads whole files) from inside a
  SwiftUI view body — it decides from the extension and, only for on-disk files, a small bounded
  byte sniff.
- **Three-way merge no longer loses your work.** Saving a merge with unresolved conflicts used to
  silently write the left side and drop the right; it now warns and writes standard
  `<<<<<<< / ======= / >>>>>>>` conflict markers. Merge output preserves the original file's line
  endings (CRLF/CR) and trailing newline, and **save failures now surface an error** instead of
  being swallowed.
- **Git integration is far more robust.** Filenames with non-ASCII characters, spaces, or renames
  are parsed correctly (all `git` output is now read as NUL-delimited `-z` records); selecting a
  **merge commit** shows its changes (diffed against the first parent) instead of an empty list;
  invalid UTF-8 in git output no longer blanks the whole history; large diffs can't deadlock the
  git subprocess; and the Custom Comparison "Unstaged"/"All Changes" scopes now mean what they say
  (All Changes includes untracked files).
- **UTF-16 and BOM-prefixed text files** are detected and decoded instead of rendering as mojibake.
- **Binary files** are recognized and shown with a size/checksum comparison instead of being
  line-diffed into garbage.
- **Fast file switching no longer shows stale results.** Text, image, folder, and merge views
  discard a slow load once you've moved on, reset cleanly between comparisons, and no longer flash
  the previous file's content.
- **Saved comparisons and recent projects survive corruption and offline drives.** One malformed
  entry no longer wipes the whole list, a corrupt store is quarantined rather than overwritten, and
  repositories on unmounted volumes are kept instead of being silently forgotten at launch.
- **Pinch-to-zoom on images no longer accelerates uncontrollably**, and the drag-and-drop handler on
  the welcome screen no longer races on concurrent file loads or scramble A/B by path.
- Folder comparison now includes **dotfiles and symlinks**, compares files by streaming (constant
  memory, early exit) instead of loading each whole file, and prunes `.git`.

### Added
- **Refresh (⌘R)** re-runs the current diff, folder scan, or merge, and reloads a repository's
  history, working changes, and refs — so on-disk changes show without reopening.
- **Copy Left / Right / Both** from a diff row's right-click menu.
- Next/Previous change now jumps **hunk-to-hunk** rather than line-by-line.
- **In-app updates** — Differentialis now downloads, verifies, installs, and relaunches updates
  itself instead of opening the DMG download page in a browser. The update banner's button
  ("Update") and **Check for Updates…** both install in place; updates are verified with an
  EdDSA-signed appcast attached to the latest GitHub release.
- **`differentialis` command-line launcher.** A thin shell script is bundled inside the app at
  `Contents/Resources/differentialis`; install it from **Differentialis ▸ Install Command Line
  Tool…** (one password prompt, then it's on your `$PATH`). Run `differentialis <repo>`,
  `differentialis <a> <b>`, or `differentialis <base> <mine> <theirs>` to open a diff from any
  directory. It talks to Differentialis by bundle id and works whether the app is already running
  or not — the app now handles the `open` Apple Event (not just launch arguments) and registers as
  a Viewer for folders and files so LaunchServices routes the paths instead of bouncing them. A
  single non-repository path now shows an in-app error instead of doing nothing.

### Changed
- Added **Sparkle** as the app's only third-party dependency, used solely for the self-updater.
  The diff, merge, and git engines remain dependency-free. Releases now carry a monotonic
  `CFBundleVersion` and an `appcast.xml` so installed apps can find and verify new versions.
- **Text layout (Split / Unified) and image comparison mode now persist across files and
  launches.** Switching to Unified for one file diff used to reset to Split when you opened
  another file. The layout choice is now a global default stored in UserDefaults — your last
  choice carries over to the next comparison and survives app relaunch. The same applies to
  image diff modes (⌘1–⌘4).

### Improved
- **Collapsible sidebar panels now show their title when collapsed.** The commit-history,
  changed-files, and changeset-file-list panels display a vertical title (e.g. "HISTORY", "FILES")
  in the collapsed rail so you can tell at a glance what each rail expands to. The expanded
  headers now show the same title horizontally.

## [0.1.6] — 2026-06-24

### Added
- **Right-click a changed file to copy its name or path.** The context menu in the repository /
  changeset file list and the folder-comparison list offers **Copy Name**, **Copy Path**
  (repo-relative), and **Copy Full Path**.

### Fixed
- **Image comparisons no longer get stuck loading for added or deleted files.** When one side of an
  image comparison doesn't exist (a newly added or a deleted file), the view spun on a loading
  indicator forever because it waited for both sides to decode. It now renders whichever side is
  present and shows a clear placeholder explaining the other side is absent.

## [0.1.5] — 2026-06-23

### Fixed
- **Fixed a crash when viewing a diff or running a custom comparison** (e.g. a commit hash against
  a branch). Building a file comparison resolved the repository root by shelling out to git from
  inside a SwiftUI view body; on the main thread that re-entered the render loop and aborted. The
  repository root is now resolved once, off the main thread, so diffs render without crashing.
- **The Commits ⇄ Files toggle is fully clickable again.** Only the small icon was hit-testable, so
  switching modes often did nothing; the whole control (and the panel collapse buttons) now respond.

## [0.1.4] — 2026-06-23

### Fixed
- **Repository view no longer crashes or freezes.** Git commands — and large text diffs and image
  decoding — now run off the main thread instead of blocking it. Previously, opening a repository or
  loading a big diff could hang the UI or crash with a segmentation fault.
- **Sidebar no longer clips its contents.** The project sidebar is now a fixed-width column that the
  repository view's panes can't squeeze, so the logo and labels never get cut off the window's left edge.
- **Repository layout fixes** — the changed-files panel collapses again to give the diff more room, and
  the working-copy / "no working changes" states fill their panes instead of floating to the center.

## [0.1.3] — 2026-06-23

### Added
- **File Properties** comparison viewer — a popover (the ⓘ button in a text or image
  comparison) comparing A/B file metadata: size, type, dates, permissions, and for images the
  dimensions, format, and color space, with differing values highlighted.
- **Collapsible panels** in the repository view — hide the commit / files list or the
  changed-files list (matching collapse controls in each panel header) to give the diff more room.
- **Changelog** link in the Help menu.
- One-Up image mode: a clear **A | B** selector plus keyboard control — Space toggles, ← / →
  pick a side, ⇧⌘S swaps.

### Changed
- Bundle identifier migrated to `app.differentialis.*` to match the differentialis.app domain.

### Fixed
- The update banner summarizes the first real line of the release notes instead of showing a
  raw `## What's new` heading.

## [0.1.2] — 2026-06-23

### Added
- **Projects sidebar** — opened repositories persist in the sidebar, one click away.
- **Commits ⇄ Files** — flip the repository view between commit history and a grouped,
  filterable list of working-copy changes (HEAD vs working tree).
- **Paste a commit hash** in the Custom Comparison popover, or pick from history.
- **Keyboard shortcuts + Help menu** — full menu-bar commands and a Keyboard Shortcuts cheat
  sheet (`⌘/`); bare `[` / `]` also navigate changes.
- **Automatic updates** — checks GitHub Releases on launch and offers the notarized download,
  plus a **Check for Updates…** app-menu command.

### Fixed
- Window could be resized below its content minimum, squishing the layout.
- Sidebar collapsing into a translucent overlay in split-based detail views.

## [0.1.1] — 2026-06-22

### Changed
- Builds are now signed with **Developer ID** and **notarized by Apple**, so they install
  without Gatekeeper warnings.

## [0.1.0] — 2026-06-22

### Added
- Initial release: **text, image, and folder comparison**, **3-way merge**, a **git
  repository browser**, and the **Custom Comparison** popover with saved comparisons.
- Native SwiftUI + Liquid Glass, **zero third-party dependencies**.
- GitHub Actions release workflow that builds and attaches a drag-to-Applications `.dmg`.

[Unreleased]: https://github.com/yennster/differentialis/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/yennster/differentialis/releases/tag/v0.3.1
[0.3.0]: https://github.com/yennster/differentialis/releases/tag/v0.3.0
[0.2.2]: https://github.com/yennster/differentialis/releases/tag/v0.2.2
[0.2.1]: https://github.com/yennster/differentialis/releases/tag/v0.2.1
[0.2.0]: https://github.com/yennster/differentialis/releases/tag/v0.2.0
[0.1.9]: https://github.com/yennster/differentialis/releases/tag/v0.1.9
[0.1.8]: https://github.com/yennster/differentialis/releases/tag/v0.1.8
[0.1.7]: https://github.com/yennster/differentialis/releases/tag/v0.1.7
[0.1.6]: https://github.com/yennster/differentialis/releases/tag/v0.1.6
[0.1.5]: https://github.com/yennster/differentialis/releases/tag/v0.1.5
[0.1.4]: https://github.com/yennster/differentialis/releases/tag/v0.1.4
[0.1.3]: https://github.com/yennster/differentialis/releases/tag/v0.1.3
[0.1.2]: https://github.com/yennster/differentialis/releases/tag/v0.1.2
[0.1.1]: https://github.com/yennster/differentialis/releases/tag/v0.1.1
[0.1.0]: https://github.com/yennster/differentialis/releases/tag/v0.1.0
