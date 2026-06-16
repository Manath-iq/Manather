# Contributing to Manather

Thanks for taking the time to help out — Manather is early-stage and ideas are
genuinely welcome.

## Ways to contribute

- **💡 Suggest a feature** — [open a feature request](https://github.com/Manath-iq/Manather/issues/new?template=feature_request.yml).
- **🐛 Report a bug** — [open a bug report](https://github.com/Manath-iq/Manather/issues/new?template=bug_report.yml).
- **🔧 Send a pull request** — fix a bug or build a feature (see below).

If you're planning a larger change, please open an issue first so we can agree on
the direction before you spend time on it.

## Project at a glance

- **Platform:** macOS 14 (Sonoma)+, Apple Silicon.
- **Stack:** SwiftUI + SwiftData, pure Apple frameworks — no external dependencies.
- **Project file:** `manather.xcodeproj` lives at the repo root; sources are in `manather/`.

New `.swift` files added under `manather/` are picked up automatically by the
project's synchronized file groups.

## Building

```bash
git clone https://github.com/Manath-iq/Manather.git
cd Manather
open manather.xcodeproj   # then press ⌘R in Xcode
```

Or from the command line:

```bash
xcodebuild -project manather.xcodeproj -scheme manather \
  -destination 'platform=macOS' build
```

**No Mac handy?** Every push runs the [Build workflow](../../actions/workflows/build.yml)
on a macOS runner. A green check means it compiles — that's the main way to verify
a change without a Mac.

## Pull request checklist

1. **Branch** off `main` with a descriptive name (e.g. `fix/board-export-clipping`).
2. **Keep it focused** — one logical change per PR is much easier to review.
3. **Build passes** — make sure CI is green before requesting review.
4. **Update the docs** when behavior changes: `README.md`, `CLAUDE.md`, and add a
   line under `## [Unreleased]` in [`CHANGELOG.md`](../CHANGELOG.md).
5. **Describe the change** clearly in the PR — what, why, and a screenshot/GIF for
   anything visual.

## Style

- UI strings and code comments are in **English**.
- Match the surrounding code: naming, spacing, and comment density.
- Design language: light theme uses a paper-white background; dark theme uses a
  neutral graphite (not blue/teal). Card corners 12, panel corners 16.

By contributing, you agree that your contributions are licensed under the
project's [MIT License](../LICENSE).
