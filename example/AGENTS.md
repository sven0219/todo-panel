# Daily Todo Repository

A plain-markdown todo list archived by ISO week. No build / test / lint required.

## 1. File Layout

```
weeks/YYYY/YYYY-WWW-MMDD-MMDD.md
```

- `YYYY` year, `WWW` ISO week number (with `W` prefix, e.g. `W24`), `MMDD-MMDD` Monday–Sunday range
- Example: `weeks/2026/2026-W24-0608-0614.md`
- Archived by year under `weeks/YYYY/`

## 2. File Format

```markdown
# 2026-W24 Weekly Log

- [2026-06-08 Mon](#2026-06-08-mon)

## 2026-06-08 Mon

### Completed
- **Project** - task text
  - subtask

### Time Record
- Clock-in: 09:45
- Location: Office
- Clock-out: 18:17
- Duration: 8h 32m
```

Format rules:
- Level-1 heading `# YYYY-WW Weekly Log`, followed by a TOC (anchor links, one per day)
- One `## YYYY-MM-DD Weekday` per day, **in reverse-chronological order** (newest first)
- Lists use `-`; multiple tasks of the same project are grouped under one `**Project**` with sub-lists
- `###` sections (as needed): `Completed` / `Unfinished` / `Follow-up` / `Time Record`
- Time record lines: Clock-in / Location / Clock-out / Duration

## 3. Operations

### Basics
- **Create the current week file**: before an operation, check whether the current ISO-week file exists; create it if missing (and its year directory first)
- **Append entries**: edit the relevant day's section directly
- **Auto-commit**: after every change run `git add -A && git commit -m "update: <description>" && git push`
- **Pull before modifying**: run `git pull --rebase` before any change to stay in sync

### Clock In
0. Read that day's `### Follow-up` section and present it to the user
1. Record the clock-in time in `### Time Record`, plus the work location (locations come from `todo.config.json`)
2. On the first clock-in of the day, check and add scheduled tasks (see `todo.config.json`)
3. Check the closest previous day's `### Follow-up`; if it still has items and today has no transfer yet, move them to today's `### Follow-up`

### Clock Out
1. Record the clock-out time and auto-compute the day's duration (later clock-out of the same day overrides earlier)
2. Transfer follow-ups: if today's `### Follow-up` has items, move them to the **next workday** (Mon–Thu → next day; Fri → next Mon, creating next week's file if needed)

### Weekly Summary
- On the first modification of a Monday, summarize the previous week into the repo root `README.md`
- Each summary uses a level-2 heading `## [YYYY-WW](<weeks/YYYY/YYYY-WW-MMDD-MMDD.md>)`, with per-project bullet items and a final total-duration line
- Summaries are ordered newest-first

## 4. Scheduled Tasks

Defined by `scheduledTasks` in `todo.config.json` (optional). Matching rules are in [docs/CONFIG.md](../docs/CONFIG.md).
