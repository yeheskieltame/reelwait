#!/usr/bin/env bash
# Pasang reelwait: symlink, config, hooks Claude Code, keybind tmux.
set -eu
ROOT=$(cd "$(dirname "$0")" && pwd)
BIN=$HOME/.local/bin/reelwait
SETTINGS=$HOME/.claude/settings.json
TMUXCONF=$HOME/.tmux.conf
CONF_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/reelwait

missing=""
for c in tmux mpv yt-dlp socat jq; do command -v "$c" >/dev/null || missing="$missing $c"; done
if [ -n "$missing" ]; then
  echo "Dependency kurang:$missing"
  echo "  macOS: brew install$missing"
  echo "  Linux: sudo apt install$missing"
  exit 1
fi

mkdir -p "$(dirname "$BIN")" "$CONF_DIR" "$(dirname "$SETTINGS")"
ln -sf "$ROOT/bin/reelwait" "$BIN"
[ -f "$CONF_DIR/config" ] || cp "$ROOT/config/default.conf" "$CONF_DIR/config"

# Hooks: merge, jangan timpa hook user. Tulis lewat cat supaya symlink/permission file tetap.
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
tmp=$(mktemp)
jq --arg bin "$BIN" '
  def add(ev; arg):
    .hooks[ev] = ((.hooks[ev] // []) as $g
      | if any($g[]; any(.hooks[]?; (.command // "") | contains("reelwait"))) then $g
        else $g + [{hooks: [{type: "command", command: "\($bin) \(arg)"}]}] end);
  add("UserPromptSubmit"; "start") | add("Stop"; "stop") | add("Notification"; "stop")
  | add("StopFailure"; "stop") | add("SessionEnd"; "stop") | add("SessionStart"; "warm")
' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS" && rm -f "$tmp"

if ! grep -q '>>> reelwait >>>' "$TMUXCONF" 2>/dev/null; then
  if [ -s "$TMUXCONF" ] && [ -n "$(tail -c1 "$TMUXCONF")" ]; then echo >> "$TMUXCONF"; fi
  cat >> "$TMUXCONF" <<EOF
# >>> reelwait >>>
bind-key -n M-j run-shell -b "REELWAIT_PANE='#{pane_id}' '$BIN' next"
bind-key -n M-k run-shell -b "REELWAIT_PANE='#{pane_id}' '$BIN' prev"
bind-key -n M-m run-shell -b "REELWAIT_PANE='#{pane_id}' '$BIN' mute"
bind-key -n M-p run-shell -b "REELWAIT_PANE='#{pane_id}' '$BIN' pause"
bind-key -n M-r run-shell -b "REELWAIT_PANE='#{pane_id}' '$BIN' toggle"
bind-key -r j run-shell -b "REELWAIT_PANE='#{pane_id}' '$BIN' next"
bind-key -r k run-shell -b "REELWAIT_PANE='#{pane_id}' '$BIN' prev"
bind-key R run-shell -b "REELWAIT_PANE='#{pane_id}' '$BIN' toggle"
set -g allow-passthrough on
# <<< reelwait <<<
EOF
fi
tmux info >/dev/null 2>&1 && tmux source-file "$TMUXCONF"

[ -n "${REELWAIT_SKIP_FETCH:-}" ] || nohup "$BIN" fetch >/dev/null 2>&1 &
echo "reelwait terpasang. Pakai Claude Code seperti biasa, lalu cek: reelwait doctor"
case ":$PATH:" in *":$(dirname "$BIN"):"*) ;; *) echo "Tambahkan $(dirname "$BIN") ke PATH." ;; esac
