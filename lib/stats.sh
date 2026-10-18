# stats.log: timestamp,session,count,duration_sec

record_stats() { # $1 state dir (sudah di-rename oleh finish)
  local n s dur name
  n=$(cat "$1/count" 2>/dev/null || echo 0)
  s=$(cat "$1/started" 2>/dev/null || date +%s)
  dur=$(($(date +%s) - s))
  name=$(basename "${1%.closing.*}")
  echo "$(date +%Y-%m-%dT%H:%M:%S),$name,$n,$dur" >> "$CACHE/stats.log"
  local msg="brainrot: $n reels selama Claude kerja $((dur / 60))m$((dur % 60))s"
  if [ -n "${TMUX:-}" ]; then tmux display-message -d 4000 "$msg" 2>/dev/null; else echo "$msg" >&2; fi
}

show_stats() {
  local f=$CACHE/stats.log
  [ -s "$f" ] || { echo "Belum ada reels yang ditonton. Produktif amat."; return 0; }
  awk -F, -v today="$(date +%Y-%m-%d)" '
    index($1, today) == 1 {
      n += $3; s += $4; k++
      rows = rows sprintf("  %s  %-10s %4d reels  %dm%02ds\n", substr($1, 12, 5), $2, $3, $4 / 60, $4 % 60)
    }
    END { printf "Hari ini: %d reels, %d sesi, %dm%02ds nunggu Claude\n%s", n, k, s / 60, s % 60, rows }
  ' "$f"
}
