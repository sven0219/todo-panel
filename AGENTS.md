# TodoPanel — Agent Guide

macOS menu-bar todo client (SwiftUI + AppKit) that reads/writes markdown week logs in a user "todo repo" and auto-commits/pushes to that repo's current git branch. Single SwiftPM executable, **no dependencies, no test target**.

## Commands

```bash
swift build                 # debug
swift build -c release      # release binary at .build/release/TodoPanel
./build-app.sh              # package dist/TodoPanel.app (also rebuilds release)
swift run TodoPanel --selftest --sample=example/weeks/2026/2026-W24-0608-0614.md
swift run TodoPanel --selftest          # works without --sample too
```

- **There is no `swift test`.** Verification is `--selftest` (round-trip + rules checks). It needs a week file for the sample check (`--sample=`); `example/weeks/2026/2026-W24-0608-0614.md` works.
- Regenerate README screenshots: `swift run TodoPanel --screenshot docs/images --repo example` (renders off-screen; commit the PNGs).
- `--e2e --repo <path>` runs clock-in→add→clock-out against a real repo **and commits/pushes to its current branch** — only ever run against `example/` or a scratch branch.

## Layout

- `Sources/main.swift` — entry; parses `--selftest`, `--e2e`, `--screenshot`, `--repo`, `--config`; builds the main menu (Edit menu enables ⌘C/V/A).
- `Sources/App/` — `AppDelegate` (menu bar + NSPanel), `TodoService` (@MainActor orchestration + serial `syncQueue` for git/file work), `AppConfig` (global config), `I18n`, `RepoLocator`, `LoginItem`, `PanelLayout`, `Palette`, `Logger`.
- `Sources/Repo/` — `MarkdownCodec` (parse/serialize week files), `WeekStore` (file + git), `GitManager`.
- `Sources/Rules/` — `TodoRules` (clock in/out, follow-up transfer, scheduled tasks), `WeeklySummary`.
- `Sources/Views/` — SwiftUI: `ContentView`, `TodoSectionView`, `WeekView`, `SetupView`.
- `example/` — self-contained demo todo repo (AGENTS.md + todo.config.json + a week file). Used by selftest, screenshots, and docs. `docs/` — user docs. `.github/workflows/release.yml` — builds + releases on `v*` tags.

## Conventions & quirks

- **Swift 5 language mode** is forced in `Package.swift` (`swiftLanguageMode(.v5)`), yet `@MainActor`-isolated property access from nonisolated code (e.g. AppDelegate) is still a hard error. Wrap UI/service work in `Task { @MainActor in … }`; do not read `TodoService` properties directly from nonisolated functions.
- `@Published var` with `didSet` is unreliable here — persist settings via explicit setter methods (e.g. `setAlwaysOnTop`, `setConfigPathOverride`) that write `UserDefaults` and reload `AppConfig` when needed.
- App config lives in the **user todo repo's** `todo.config.json` (locations, `scheduledTasks` weekday=1..7/monthDay, `commitMessagePrefix`, `appName`, `defaultLanguage`), loaded into the `AppConfig.shared` global. Missing fields fall back to built-in defaults.
- Markdown section names and time-record labels parse **both** Chinese and English; files are serialized in the current UI language (`I18n`). Keep the bilingual `Category` mapping in `MarkdownCodec` in sync.
- App-generated commit messages are English (`AppConfig.commitMessage`).
- `GitManager` shells out to `/usr/bin/git` with `GIT_SSH_COMMAND="ssh -o BatchMode=yes"` (no interactive prompts) and a 60s per-command timeout; order is commit → `pull --rebase` → push.
- Data model is plain markdown; there is no database/migration.

## Releasing

Tag `v*` and push — GitHub Actions builds, runs selftest, packages, and creates the GitHub Release with `TodoPanel-macOS.zip`:

```bash
git tag v0.1.0 && git push origin v0.1.0
```
