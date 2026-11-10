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

- **Service health comes from a second, unauthenticated source:**
  `GET https://status.claude.com/api/v2/summary.json` (a Statuspage feed;
  `status.anthropic.com` 301s to it). Cached in `~/.cache/claude-usage/status.json`
  for `STATUS_TTL` (60s) and reused for up to an hour when unreachable. Severity
  is derived, not given: component `major_outage` or incident impact `critical`
  → `outage` (red); `degraded_performance`/`partial_outage` or incident impact
  `minor`/`major` → `warn` (yellow); page-wide `indicator` is capped at `warn`
  because it also covers components we don't watch (`WATCHED_COMPONENTS`).
  Real incidents ("elevated errors") carry impact `major` while every component
  stays `operational`, so don't key outage detection off component status alone.
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
- **No endpoint gives the subscription end/renewal date.** The `subscription`
  block is an estimate: monthly anniversary of `oauthAccount.subscriptionCreatedAt`
  from `~/.claude.json` (Claude Code's cached `/api/oauth/profile` read; no API
  call of ours), clamped to month end like Stripe. Wrong for annual plans.
- **Free limit resets (`cedar_ember`) are deliberately not implemented.**
  `GET /api/oauth/usage?cedar_ember=1` fills a `cedar_ember` block (`grants[]`
  with `resets_left`, `resets_total`, `ends_at`, `type`, `usable_now`), but the
  server gates it on client surface via User-Agent: ours gets
  `eligible: false, ineligible_reason: "surface"`. Unlocking it means spoofing
  Claude Code's `claude-cli/<ver>` User-Agent, which the owner declined
  (account risk). A browser extension polling claude.ai's internal API was also
  declined: nothing that risks the ToS. Claude Code exposes no other route
  (`claude -p "/usage"` and the statusline input omit grants;
  `unusedLimitResetStatusCache` in `~/.claude.json` is a bare flag and unset).
  Don't add it unless an official, non-spoofed source appears.
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
`auto_reload`, `currency`), `breakdown` (`rows[]` of `label`/`pct`), and
`service` (`severity` one of `none`/`maintenance`/`warn`/`outage`, plus
`indicator`, `description`, `headline`, `url`, `updated_at`, `stale`,
`components[]`, `incidents[]`, `maintenances[]`; null with `--no-status` or when
the status page has never been reachable), and `subscription` (`created_at`,
`billing_type`, `period_start`, `period_end`, `ends_in`; null when Claude Code
hasn't cached `subscriptionCreatedAt`). `service` and `subscription` are attached
after the cache fallback, so an `auth`/`stale`/`error` payload still carries live
service health and the current period — which is the point, since an outage is
when the usage call itself fails. Keep
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
- **Verifying UI without clicking the panel:** `qml6` a harness that imports a
  copy of `UsageView.qml` with a synthetic `usage` object, and have it call
  `grabToImage(...).saveToFile(path)` — `spectacle` only grabs the whole 3x4K
  desktop, and `spectacle -a` doesn't honour the active window here. Bare `qml6`
  has no Plasma palette, so `negativeTextColor` renders green there; check
  colours on the real panel. To see the real popup, temporarily set
  `root.expanded = true` from a `Timer`, restart plasmashell, screenshot, revert.
- Listing/adding/removing widgets programmatically:
  `qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '<js>'`
  using `panels()[i].widgets()` and `addWidget`/`.remove()`. After a restart the
  DBus interface lags — poll until the call succeeds.

## Gotchas for this environment

- `plasmawindowed` does not reliably map a titled window here, so screenshotting
  the popup standalone is unreliable — verify on the real panel.
- When matching windows in a KWin script, match on `resourceClass`, not caption
  (a Konsole tab named "claude" will false-match a `claude` caption search).
