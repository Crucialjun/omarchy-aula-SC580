#!/usr/bin/env bash
# Local/offline installer: sc580ctl on PATH, the udev rule and the Omarchy shell plugin.
# (On Omarchy you can instead use: omarchy plugin add <repo-url> --enable)
#   ./install.sh            everything
#   ./install.sh --no-plugin  just the CLI + udev rule (any Linux)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="io.github.crucialjun.aula-sc580"
BIN_DIR="${HOME}/.local/bin"
PLUGIN_DIR="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
WITH_PLUGIN=1
[[ "${1:-}" == "--no-plugin" ]] && WITH_PLUGIN=0

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# 1. CLI
mkdir -p "$BIN_DIR"
install -m 0755 "$HERE/bin/sc580ctl" "$BIN_DIR/sc580ctl"
say "installed $BIN_DIR/sc580ctl"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "    note: $BIN_DIR is not on your PATH (Omarchy normally adds it)";;
esac

# 2. udev rule (needs root)
RULE=/etc/udev/rules.d/70-aula-sc580.rules
if [[ -f "$RULE" ]] && cmp -s "$RULE" "$HERE/udev/70-aula-sc580.rules"; then
  say "udev rule already installed"
else
  say "installing udev rule (sudo)"
  sudo install -m 0644 "$HERE/udev/70-aula-sc580.rules" "$RULE"
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=hidraw
  echo "    replug the mouse/receiver if sc580ctl still reports permission denied"
fi

# 3. Omarchy plugin
if (( WITH_PLUGIN )); then
  if ! command -v omarchy-plugin-validate >/dev/null 2>&1; then
    echo "omarchy-plugin-validate not found — is this an Omarchy install? (use --no-plugin for CLI only)" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  rm -rf "$PLUGIN_DIR"
  mkdir -p "$PLUGIN_DIR"
  cp -r "$HERE"/manifest.json "$HERE"/Panel.qml "$HERE"/Model.js "$HERE"/bin "$HERE"/udev "$HERE"/README.md "$HERE"/LICENSE "$PLUGIN_DIR"/
  omarchy-plugin-validate "$PLUGIN_DIR"
  say "plugin copied to $PLUGIN_DIR"
  # The running shell only knows plugins it scanned; ask it to look again.
  omarchy-shell -q shell rescanPlugins 2>/dev/null || true
  sleep 1
  if omarchy-plugin-enable "$PLUGIN_ID" --section right 2>/dev/null; then
    say "bar widget enabled (right section)"
  else
    echo "    shell not running or plugin not picked up yet — after a restart run:"
    echo "      omarchy plugin enable $PLUGIN_ID --section right"
  fi
fi

say "done — try: sc580ctl status"
