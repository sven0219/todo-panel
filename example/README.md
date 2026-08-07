# Example Todo Repository

A reference repository for use with TodoPanel. Copy this structure to create your own todo repository:

```
my-todo-repo/
├── AGENTS.md          # logging spec TodoPanel follows
├── README.md          # weekly summaries are written here
├── todo.config.json   # optional config: locations, scheduled tasks, etc.
└── weeks/
    └── 2026/
        └── 2026-W24-0608-0614.md
```

Notes:

- **`weeks/` layout and file format**: see [AGENTS.md](AGENTS.md)
- **`todo.config.json`**: all fields are optional, see [docs/CONFIG.md](../docs/CONFIG.md)
- The app auto-detects the repository by looking for `AGENTS.md` or `.git`
