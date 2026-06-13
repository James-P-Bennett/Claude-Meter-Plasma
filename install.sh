#!/usr/bin/env bash
# Install claude-meter by symlinking this repo's files into the locations
# Plasma and your shell look in. Re-runnable; safe to run after `git pull`.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
PLASMOID_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids"

mkdir -p "$BIN_DIR" "$PLASMOID_DIR"

ln -sfn "$REPO/bin/claude-usage" "$BIN_DIR/claude-usage"
ln -sfn "$REPO/plasmoid/com.starrift.claudeusage" "$PLASMOID_DIR/com.starrift.claudeusage"

echo "Linked:"
echo "  $BIN_DIR/claude-usage -> $REPO/bin/claude-usage"
echo "  $PLASMOID_DIR/com.starrift.claudeusage -> $REPO/plasmoid/com.starrift.claudeusage"
echo
echo "The widget's default script path is /home/james/.local/bin/claude-usage."
echo "If your username differs, edit it in the widget's Configure dialog (Script path),"
echo "or update the default in plasmoid/com.starrift.claudeusage/contents/config/main.xml."
echo
echo "Now add the widget: right-click your panel -> Add Widgets -> 'Claude Usage'."
echo "If it doesn't appear, reload the shell:  kquitapp6 plasmashell && kstart plasmashell"
