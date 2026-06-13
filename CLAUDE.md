# CLAUDE.md — claude-meter

KDE Plasma 6 widget + Python CLI that displays Claude subscription usage limits.

## Architecture

Two components, one data flow:

1. **`bin/claude-usage`** (Python 3, stdlib only) — reads the OAuth token from
   `~/.claude/.credentials.json` (`claudeAiOauth.accessToken`), calls
   `GET https://api.anthropic.com/api/oauth/usage`, and prints normalized JSON.
   It **never writes** the credentials file. Caches the last good reading in
   `~/.cache/claude-usage/last.json`; notification state in `notify-state.json`.
2. **`plasmoid/com.starrift.claudeusage/`** — runs `claude-usage --json` on a
   QML `Timer` via the `org.kde.plasma.plasma5support` executable engine, parses
   the JSON, and renders a compact panel readout + a popup.

The repo is the source of truth; `install.sh` symlinks both into
`~/.local/bin` and `~/.local/share/plasma/plasmoids`. Edit files here, not in
the install locations (they're symlinks back to here).

## Critical facts (verify before trusting)

- **The `/api/oauth/usage` endpoint is unofficial.** Required headers:
  `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`.
- **It rate-limits (HTTP 429)** under rapid calls. Do NOT hammer it while
  testing — a handful of calls in a few seconds triggers a 429 that lasts
  minutes. The widget polls every 60s by default for this reason.
- Response shape (only utilisation %, plus codenamed null slots):
  ```json
  { "five_hour": {"utilization": 23.0, "resets_at": "..."},
    "seven_day": {"utilization": 3.0, "resets_at": "..."},
    "seven_day_sonnet": {"utilization": 0.0, "resets_at": null},
    "seven_day_opus": null,
    "extra_usage": {"is_enabled": true, "used_credits": 10596.0,
                    "monthly_limit": null, "currency": "USD"} }
  ```
- `used_credits` / `monthly_limit` are **USD cents** (`10596` = `$105.96`).
- The endpoint does NOT provide daily routine-run counts, credits balance, or
  credits reset date — those are claude.ai web-only (browser session, not this
  token). Don't fabricate them.
- The token is refreshed by Claude Code, not by us. On expiry/401 the CLI
  returns status `auth`; on other failures `error`; both fall back to the cache
  as status `stale` when one exists.

## CLI output contract (what the QML depends on)

`claude-usage --json` emits: `status` (`ok`/`stale`/`auth`/`error`/`init`),
`plan`, `tier`, `fetched_at`, `max_pct`, `windows` (compact: 5h + weekly),
`session`, `weekly.bars[]` (keyed `seven_day`/`seven_day_sonnet`/`seven_day_opus`),
and `credits` (`spent_cents`, `monthly_limit_cents`, `currency`). Keep this
stable or update `contents/ui/main.qml` in lockstep.

## Testing

- **Lint QML:** `qmllint -I /usr/lib/qt6/qml plasmoid/com.starrift.claudeusage/contents/ui/main.qml`
  (and `configGeneral.qml`). Must exit 0.
- **Unit-test the parser without an API call:** load `bin/claude-usage` with
  `importlib.machinery.SourceFileLoader` (no `.py` extension) and call
  `normalize(raw, blob)` with a synthetic `raw` matching the shape above.
- **Apply QML changes to the running widget:** Plasma caches plasmoid QML, so
  `kquitapp6 plasmashell && kstart plasmashell` is required after editing QML.
  Config-only changes (the `cfg_*` settings) apply live, no restart.
- Listing/adding/removing widgets programmatically:
  `qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '<js>'`
  using `panels()[i].widgets()` and `addWidget`/`.remove()`. After a restart the
  DBus interface lags — poll until the call succeeds.

## Gotchas for this environment

- `plasmawindowed` does not reliably map a titled window here, so screenshotting
  the popup standalone is unreliable — verify on the real panel.
- When matching windows in a KWin script, match on `resourceClass`, not caption
  (a Konsole tab named "claude" will false-match a `claude` caption search).
