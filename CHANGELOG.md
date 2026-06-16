# Changelog

All notable changes to Manather are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet — your next change goes here._

## [0.1.6] — 2026-06-16

### Added
- **Export a collection tailored for an AI agent.** When you export a collection
  you now pick a target and Manather lays the files out the way that agent reads
  them automatically:
  - **Claude Code** — `CLAUDE.md`, each skill as `.claude/skills/<name>/SKILL.md`
    (with the name/description header Claude expects), and a real `.mcp.json`.
  - **AGENTS.md (universal)** — a single `AGENTS.md`, the open standard read by
    Cursor, Codex, Copilot, Gemini and others, plus `mcp.json`.
  - **Generic context pack** — the original `CONTEXT.md` + `manifest.json`,
    unchanged.

  All options still copy images/video into `assets/` and code snippets into
  `snippets/`, and gather your MCP servers into one config file.

## [0.1.5] — 2026-06-16

### Added
- **Switchable libraries**: the “Library ▾” menu now holds several libraries you
  can switch between, each with its own saves and collections.
- **Share a library as a ZIP**: export a whole library from Settings and send it
  to a friend, who imports it back as a new library from the Library menu —
  collections, names, prompts, notes and tags all come across.

### Changed
- Settings is now a styled panel matching the app’s other menus (was a plain
  system popover).
- The New Board dialog adapts to light/dark mode like the New Collection one.
- Small search-field polish.

### Fixed
- Rotating a board object now pivots around its own center, so a rotated item no
  longer drifts away and drags in the right direction; its toolbar tracks it.

## [0.1.4] — 2026-06-16

### Added
- **Visit Site** button on web-link assets, right inside the inspector.
- Collection picker in the inspector is now a clean popover instead of an inline text field.
- Board cards show a collage preview of their images instead of a blank rectangle.

### Changed
- Web-link cards redesigned: full-bleed page screenshot with a gradient and title overlay.

### Fixed
- Three board polish issues: font label, toolbar overlap, and clipping on export.
- Dragging a URL in from Finder is now handled correctly.
- Removed a stray phantom arrow from the Library sort menu.

## [0.1.3] — 2026-06-15

### Added
- **⌘V smart-paste**: paste an image, link, or text straight into the library.
- Global screenshot hotkey to capture and save without leaving your current app.

### Changed
- Card and right-click-menu visual polish.

## [0.1.2] — 2026-06-15

### Added
- **Rotate any board object** with a dedicated rotation handle.
- Board arrows and lines can be drawn in any direction.

### Fixed
- Notes on a board scroll their overflowing text instead of resizing.
- Smoother board item drag/resize (gestures measured in global space).

## [0.1.1] — 2026-06-15

### Fixed
- Release workflow: manual dispatch can now create the tag, and notes are passed
  via a file so apostrophes no longer break the build.

## [0.1.0] — 2026-06-15

First public release. 🎉

### Added
- **Library** — a Pinterest-style masonry grid for every building block:
  images, GIFs, video, web links, code snippets, MCP servers, and skills.
- **Color filter** (7 auto-extracted hues), search across titles/prompts/notes/tags/code,
  and sorting by recency or name.
- **Collections** as real, first-class objects with a folder “fan” card.
- **Detail view** — full-screen viewer with zoom, keyboard navigation, a glassmorphic
  inspector, prompts, notes, tags, and a copyable color palette.
- **Boards** — an infinite moodboard canvas with images, notes, text, shapes, frames,
  and arrows; move/resize/rotate, undo/redo, and PNG export.
- **Context Pack export** — turn a collection into an agent-ready folder
  (`CONTEXT.md`, `manifest.json`, copied assets).
- Continuous integration and one-click `.dmg` releases.

[Unreleased]: https://github.com/Manath-iq/Manather/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/Manath-iq/Manather/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/Manath-iq/Manather/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Manath-iq/Manather/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Manath-iq/Manather/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Manath-iq/Manather/releases/tag/v0.1.0
