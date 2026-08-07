# TodoPanel

A macOS menu-bar floating-panel todo client that reads and writes your markdown weekly-log repository and auto-commits to git.

Turn daily work logging into one click: clock in/out, maintain todo & done lists, auto weekly summary. Your data is plain markdown — fully under your control.

## Features

- **Clock in / Clock out**: record time and work location, auto-compute duration; clock-out automatically moves today's "follow-ups" to the next workday (Fri → next Mon, creating next week's file if needed)
- **Scheduled tasks**: checked on the first clock-in of the day (day-of-week or day-of-month), deferred to the next workday when a fixed date falls on a weekend
- **Todo management**: Todo / Done lists with add, edit, delete, reorder, move; subtasks can be toggled individually
- **Day & Week views**: browse by day or by week; clock-in/out only available for today
- **Weekly summary**: on Monday, auto-generates last week's summary into the repo's root `README.md`
- **Sync strategy**: changes commit locally, pushed in batch every 10 minutes (manual sync button, optional push-per-action, forced push on clock-out, auto retry)
- **UI**: light/dark override, Chinese/English switching, project name autocomplete, resizable window, collapse-aware height, menu-bar status

## Quick Start

### 1. Prepare a todo repository

Your todo data lives in your own git repository (with an `AGENTS.md` spec — see [example/](example/AGENTS.md)):

```
my-todo-repo/
├── AGENTS.md          # logging spec (see example/)
├── README.md          # weekly summaries are written here
├── todo.config.json   # optional: locations / scheduled tasks (see docs/CONFIG.md)
└── weeks/
    └── 2026/
        └── 2026-W32-0803-0809.md
```

### 2. Build and run

```bash
git clone git@github.com:sven0219/todo-panel.git
cd todo-panel
swift build -c release
./.build/release/TodoPanel        # run directly
./build-app.sh                     # or package as TodoPanel.app (drag to Applications)
```

### 3. First launch

- If the todo repository is auto-detected from the app's location, it goes straight to the main UI
- Otherwise a setup screen asks for the repository path (with Finder picker); it then enters the main UI
- The repository path can be changed later in Settings

## Configuration

Locations, scheduled tasks and more can be configured via `todo.config.json` in your repository root; missing fields use built-in defaults.
See [docs/CONFIG.md](docs/CONFIG.md) for the full reference.

## Docs

- [Configuration docs/CONFIG.md](docs/CONFIG.md)
- [Todo repository spec example/AGENTS.md](example/AGENTS.md)
- [Example repository example/](example/)

## Release

Tag a version and GitHub Actions builds and publishes it automatically:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Tech Stack

- SwiftUI + AppKit (macOS 14+), Swift Package Manager, no third-party dependencies
- Markdown parsing/rendering and git are handled directly by the app

## Project Structure

```
├── Package.swift
├── build-app.sh            # package as .app
├── Sources/
│   ├── main.swift          # entry point (incl. --selftest)
│   ├── App/                # menu bar, panel, orchestration, config
│   ├── Models/             # data models, date helpers
│   ├── Repo/               # markdown parse/generate + git
│   ├── Rules/              # clock rules, scheduled tasks, weekly summary
│   └── Views/              # UI
├── example/                # example todo repository
├── docs/                   # documentation
└── .github/workflows/      # release pipeline
```

## Development Self-Tests

```bash
swift run TodoPanel --selftest --sample=<path-to-a-week-file>
```

## License

MIT
