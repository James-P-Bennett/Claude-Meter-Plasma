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
   the JSON, and renders a compact panel readout, a popup, and a standalone
   resizable window (expand button in the popup, middle click, or the context
   menu). Popup and window share `contents/ui/UsageView.qml` (`detailed` toggles
   the window-only sections).

The repo is the source of truth; `install.sh` symlinks both into
`~/.local/bin` and `~/.local/share/plasma/plasmoids`. Edit files here, not in
the install locations (they're symlinks back to here).

## Critical facts (verify before trusting)

- **The `/api/oauth/usage` endpoint is unofficial.** Required headers:
  `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`.
- **It rate-limits (HTTP 429)** under rapid calls. Do NOT hammer it while
  testing — a handful of calls in a few seconds triggers a 429 that lasts
  minutes. The widget polls every 60s by default for this reason.
- Response shape (as of Sept 2026; plus many codenamed null slots like
  `nimbus_quill`, ignore those):
  ```json
  { "five_hour": {"utilization": 27.0, "resets_at": "..."},
    "seven_day": {"utilization": 5.0, "resets_at": "..."},
    "extra_usage": {"is_enabled": false, "used_credits": 0.0, "monthly_limit": null,
                    "currency": "USD", "disabled_reason": "out_of_credits"},
    "limits": [
      {"kind": "session", "group": "session", "percent": 27, "resets_at": "...", "scope": null},
      {"kind": "weekly_all", "group": "weekly", "percent": 5, "resets_at": "...", "scope": null},
      {"kind": "weekly_scoped", "group": "weekly", "percent": 0, "resets_at": "...",
       "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}} ],
    "spend": {"used": {"amount_minor": 0, "currency": "USD", "exponent": 2},
              "limit": null, "enabled": false, "disabled_reason": "out_of_credits",
              "cap": null, "balance": null, "auto_reload": null},
    "seven_day_breakdown": {"as_of": "...", "window_started_at": "...",
      "rows": [{"key": "claude_code", "display_name": "Claude Code", "percent": 82}, ...]} }
  ```
- `limits[]` is the source of truth for bars (it names scoped limits like Fable);
  the legacy `five_hour`/`seven_day_*` keys are only a fallback.
- `extra_usage.used_credits` / `monthly_limit` are **USD cents** (`10596` =
  `$105.96`). `spend` money is `{amount_minor, exponent}`. The non-null shapes of
  `spend.limit`/`cap`/`balance`/`auto_reload` haven't been observed yet;
  `_cents()`/`_flag()` guess and fall back to null.
- The endpoint does NOT provide daily routine-run counts or the credits reset
  date. Don't fabricate them.
- The token is refreshed by Claude Code, not by us. On expiry/401 the CLI
  returns status `auth`; on other failures `error`; both fall back to the cache
  as status `stale` when one exists.

## CLI output contract (what the QML depends on)

`claude-usage --json` emits: `status` (`ok`/`stale`/`auth`/`error`/`init`),
`plan`, `tier`, `fetched_at`, `max_pct`, `windows` (compact + notifications: 5h +
weekly), `limits[]` (every bar: `key`, `label`, `short`, `group`, `detail`, `pct`,
`resets_at`; keys `five_hour`, `seven_day`, `seven_day_<scope slug>`), `session`,
`weekly.bars[]` (the weekly group of `limits`), `credits` (`enabled`,
`disabled_reason`, `spent_cents`, `monthly_limit_cents`, `balance_cents`,
`auto_reload`, `currency`), and `breakdown` (`rows[]` of `label`/`pct`). Keep
this stable or update `main.qml` and `UsageView.qml` in lockstep.

## Testing

- **Lint QML:** `qmllint -I /usr/lib/qt6/qml plasmoid/com.starrift.claudeusage/contents/ui/main.qml`
  (and `UsageView.qml`, `configGeneral.qml`). Must exit 0.
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
