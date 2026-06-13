# claude-meter

A KDE Plasma 6 panel/tray meter for your **Claude subscription usage limits** —
the same numbers Claude Code's `/usage` shows, always visible on your desktop.

The compact readout sits on your panel (e.g. `5h 23% · Week 3%`, colour-coded by
severity). Click it for a popup with the full breakdown, and get a desktop
notification before you hit a limit.

## Features

- **Live limits** from `api.anthropic.com/api/oauth/usage` — current 5-hour
  session and weekly windows, as real utilisation percentages.
- **Sectioned popup:** Current session · Weekly limits (All models / Sonnet /
  Opus when active) · Usage credits (spent + monthly limit) — each with reset
  countdowns and a coloured progress bar.
- **Configurable panel readout:** toggle which windows show while minimised
  (5h, weekly all-models, Sonnet, Opus).
- **Threshold notifications** at 80% / 95% (configurable, fire once per window
  per reset cycle).
- **Refresh** every N seconds (default 60), on click, or via the popup's ↻ button.
- **Resilient:** caches the last good reading and shows it (dimmed) on a
  transient failure instead of blanking; backs off cleanly on rate limits.

## Requirements

- KDE Plasma 6 (developed on 6.6)
- Python 3 (standard library only — no pip installs)
- An active Claude subscription, signed in via **Claude Code** (the widget reads
  the OAuth token Claude Code stores in `~/.claude/.credentials.json` and never
  modifies it)
- `notify-send` for notifications (usually preinstalled on KDE)

## Install

```bash
git clone <this repo> ~/Documents/GitHub/claude-meter
cd ~/Documents/GitHub/claude-meter
./install.sh
```

`install.sh` symlinks `bin/claude-usage` into `~/.local/bin` and the plasmoid
into `~/.local/share/plasma/plasmoids`, so the repo stays the single source of
truth. Then add the widget: **right-click panel → Add Widgets → "Claude Usage"**.
If it doesn't appear, reload the shell:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

## Layout

```
bin/claude-usage                         # Python CLI: fetch + normalize + notify
plasmoid/com.starrift.claudeusage/       # the Plasma 6 widget (QML)
  metadata.json
  contents/ui/main.qml                   # compact readout + popup
  contents/ui/configGeneral.qml          # settings page
  contents/config/{main.xml,config.qml}  # config schema
install.sh                               # symlink into the install locations
```

## The CLI

`claude-usage` is usable on its own:

```bash
claude-usage --json                      # normalized JSON (what the widget reads)
claude-usage --line                      # e.g.  5h 23% · Week 3%
claude-usage --notify --thresholds 80,95 # also fire threshold notifications
```

## Caveats

- **The `/api/oauth/usage` endpoint is unofficial.** A future Claude update could
  change its shape; the tool degrades to a status message rather than showing
  wrong data. See [`CLAUDE.md`](CLAUDE.md) for the response shape.
- It only returns **utilisation percentages**. The **daily routine-run count**,
  **credits balance**, and **credits reset date** shown on claude.ai are web-only
  data behind your browser session and are *not* available to this tool.
- `extra_usage` values are in **USD cents** (`10596` = `$105.96`).
- The OAuth token is refreshed by Claude Code itself. If it expires (you haven't
  run `claude` in a while), the widget shows an "auth" hint — run `claude` once.

## License

[MIT](LICENSE)
