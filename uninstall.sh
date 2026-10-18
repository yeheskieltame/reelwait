#!/usr/bin/env bash
# Copot reelwait. Cache & config dibiarkan kecuali --purge.
set -eu
BIN=$HOME/.local/bin/reelwait
SETTINGS=$HOME/.claude/settings.json
TMUXCONF=$HOME/.tmux.conf

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  tmp=$(mktemp)
  # Hapus hanya handler yang command-nya memuat "reelwait", lalu buang grup/event yang jadi kosong.
  jq '
    if .hooks then
      .hooks |= with_entries(
        .value |= (map(.hooks |= map(select((.command // "") | contains("reelwait") | not)))
                   | map(select(.hooks | length > 0)))
        | select(.value | length > 0))
      | if .hooks == {} then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$tmp"
  cat "$tmp" > "$SETTINGS" && rm -f "$tmp"
fi

# Hanya kalau marker penutup masih ada; tanpa itu sed akan menghapus sampai akhir file.
if [ -f "$TMUXCONF" ] && grep -q '^# <<< reelwait <<<$' "$TMUXCONF"; then
  tmp=$(mktemp)
  sed '/^# >>> reelwait >>>$/,/^# <<< reelwait <<<$/d' "$TMUXCONF" > "$tmp"
  cat "$tmp" > "$TMUXCONF" && rm -f "$tmp"
  [ -s "$TMUXCONF" ] || rm -f "$TMUXCONF"
fi
if tmux info >/dev/null 2>&1; then
  for k in M-j M-k M-m M-p M-r; do tmux unbind-key -n "$k" 2>/dev/null || true; done
  for k in j k R; do tmux unbind-key "$k" 2>/dev/null || true; done
fi

[ -L "$BIN" ] && rm -f "$BIN"
if [ "${1:-}" = --purge ]; then
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/reelwait" "${XDG_CONFIG_HOME:-$HOME/.config}/reelwait"
fi
echo "reelwait dicopot."
