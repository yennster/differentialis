# Changelog

All notable changes to Differentialis are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

When cutting a release, add a section here and use it as the release notes:
`gh release create vX.Y.Z --notes "$(scripts/changelog.sh X.Y.Z)"`.

## [Unreleased]

### Added
- **File Properties** comparison viewer — a popover (the ⓘ button in a text or image
  comparison) comparing A/B file metadata: size, type, dates, permissions, and for images the
  dimensions, format, and color space, with differing values highlighted.
- **Collapsible panels** in the repository view — hide the commit / files list or the
  changed-files list (matching collapse controls in each panel header) to give the diff more room.
- **Changelog** link in the Help menu.

### Changed
- Bundle identifier migrated to `app.differentialis.*` to match the differentialis.app domain.

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

[Unreleased]: https://github.com/yennster/differentialis/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/yennster/differentialis/releases/tag/v0.1.2
[0.1.1]: https://github.com/yennster/differentialis/releases/tag/v0.1.1
[0.1.0]: https://github.com/yennster/differentialis/releases/tag/v0.1.0
