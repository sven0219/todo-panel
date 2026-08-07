# Configuration

Put a `todo.config.json` in the root of your todo repository to override defaults. **All fields are optional**; missing fields fall back to built-in defaults. Config changes take effect on the next launch (or when you change the repository path).

## Full Example

```json
{
  "appName": "My Todo",
  "locations": ["Office", "Home", "Remote"],
  "scheduledTasks": [
    { "project": "Report", "text": "Send weekly report", "weekday": 2 },
    { "project": "Ops",    "text": "Check cloud costs",  "weekday": 4 },
    { "project": "Finance", "text": "Renew subscription", "monthDay": 1 },
    { "project": "Finance", "text": "Send invoice",        "monthDay": 3 },
    { "project": "Report",  "text": "Log expenses",        "monthDay": 5 },
    { "project": "Ops",     "text": "Top up balance",      "monthDay": 20 }
  ],
  "commitMessagePrefix": "update:",
  "defaultLanguage": "system"
}
```

## Fields

### `appName`
Type: `string`, default `TodoPanel`
Used in the setup screen and prompt texts.

### `locations`
Type: `string[]`, default `["PG", "Marriott", "Remote"]`
Work locations offered when clocking in. Replace with your own locations.

### `scheduledTasks`
Type: `object[]`, defaults shown above.
When a task matches on the first clock-in of the day, it is added to that day's "follow-ups".

Each task:
- `project`: project name (required)
- `text`: task text (required)
- `weekday`: trigger on a day of week, `1`=Sunday … `7`=Saturday (optional)
- `monthDay`: trigger on a day of month (optional)
- At least one of `weekday` / `monthDay`; if both match, one entry is added per match
- A fixed monthly date falling on a weekend is deferred to the next workday

### `commitMessagePrefix`
Type: `string`, default `update:`
Prefix for auto-commit messages, e.g. `update: 添加待办 xxx`.

### `defaultLanguage`
Type: `string`, default `system`
Initial UI language: `system` (follow the system) / `zh` / `en`.
A language chosen later in Settings takes precedence.
