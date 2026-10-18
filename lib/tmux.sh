# Sesi & lifecycle player. State per sesi Claude: $STATE_ROOT/pane<kunci>/ berisi started,
# timer.pid, pane.id (mode pane) atau player.pid (mode window), mpv.sock, count.
# Kunci sesi: pane tmux Claude kalau ada, kalau tidak session id Claude Code (diwarisi hook).

session_key() { echo "${TMUX_PANE:-${CLAUDE_CODE_SESSION_ID:-default}}"; }

state_dir() { echo "$STATE_ROOT/pane$(printf %s "$1" | tr -cd 'A-Za-z0-9')"; }

# window = jendela mpv mengambang (butuh layar), pane = video di pane tmux.
pick_mode() {
  if [ -n "${MODE:-}" ]; then echo "$MODE"; return; fi
  if [ "$(uname)" = Darwin ] || [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then echo window; else echo pane; fi
}

# Pane id bisa basi (tmux restart memberi id yang sama ke pane lain), jadi pastikan
# pane itu memang menjalankan player kita sebelum dipercaya atau di-kill.
pane_alive() { [ -n "$1" ] && tmux display -p -t "$1" '#{pane_start_command}' 2>/dev/null | grep -q ' _player '; }
# Sama untuk pid: hanya percaya kalau prosesnya memang player kita (pid bisa dipakai ulang).
pid_alive() { [ -n "$1" ] && ps -p "$1" -o command= 2>/dev/null | grep -q ' _player '; }

player_alive() { # $1 state dir
  local p
  if p=$(cat "$1/pane.id" 2>/dev/null) && [ -n "$p" ]; then pane_alive "$p"; return; fi
  pid_alive "$(cat "$1/player.pid" 2>/dev/null)"
}

# Cari sesi untuk kunci $1: punya dia sendiri, atau sesi yang pane reels-nya satu window tmux
# dengan $1 (keybind tmux bisa dipencet saat fokus di pane Claude maupun pane reels).
resolve_state() {
  local d w p
  d=$(state_dir "$1")
  player_alive "$d" && { echo "$d"; return 0; }
  w=$(tmux display -p -t "$1" '#{window_id}' 2>/dev/null) || return 1
  for d in "$STATE_ROOT"/pane*; do
    p=$(cat "$d/pane.id" 2>/dev/null)
    pane_alive "$p" || continue
    [ "$(tmux display -p -t "$p" '#{window_id}' 2>/dev/null)" = "$w" ] && { echo "$d"; return 0; }
  done
  return 1
}

# Hanya bunuh pid kalau memang timer kita (pid bisa sudah dipakai ulang proses lain).
kill_timer() {
  local p
  p=$(cat "$1/timer.pid" 2>/dev/null) || return 0
  ps -p "$p" -o command= 2>/dev/null | grep -q 'reelwait _open' && kill "$p" 2>/dev/null
  rm -f "$1/timer.pid"
}

start_timer() { # $1 kunci sesi, $2 delay
  local d
  d=$(state_dir "$1")
  if [ -f "$d/pane.id" ] || [ -f "$d/player.pid" ]; then
    player_alive "$d" && return 0
    rm -rf "$d" # player ditutup manual, buang state basi
  fi
  kill_timer "$d"
  mkdir -p "$d" && date +%s > "$d/started"
  nohup "$SELF" _open "$1" "$2" >/dev/null 2>&1 </dev/null &
  echo $! > "$d/timer.pid"
}

# ponytail: kalau stop datang tepat saat player sedang dibuka (jendela beberapa ms), player
# bisa yatim. _player keluar sendiri kalau state-nya sudah hilang, cukup untuk MVP.
open_player() { # $1 kunci sesi, $2 opsional epoch akhir (mode limit)
  local d
  d=$(state_dir "$1")
  [ -d "$d" ] || return 0
  if [ "$(pick_mode)" = window ]; then
    REELWAIT_MODE=window REELWAIT_IN_PLAYER=1 nohup "$SELF" _player "$d" "${2:-}" >/dev/null 2>&1 </dev/null &
    echo $! > "$d/player.pid"
    return 0
  fi
  # Bentuk argv (tanpa shell): path dengan spasi/apostrof aman.
  tmux split-window -h -d -l "$PANE_SIZE" -t "$1" -P -F '#{pane_id}' \
    -e "PATH=$PATH" -e "REELWAIT_CACHE=$CACHE" -e "REELWAIT_CONF=$CONF_DIR" -e "REELWAIT_VO=$(pick_vo)" \
    -e REELWAIT_IN_PLAYER=1 "$SELF" _player "$d" "${2:-}" > "$d/pane.id"
}

stop_session() { # $1 state dir
  [ -d "$1" ] || return 0
  kill_timer "$1"
  finish "$1"
}

# Idempotent: siapa yang duluan me-rename folder state, dia yang catat stats dan tutup player.
finish() {
  local d=$1.closing.$$ pane pid i=0
  mv "$1" "$d" 2>/dev/null || return 0
  pane=$(cat "$d/pane.id" 2>/dev/null)
  pid=$(cat "$d/player.pid" 2>/dev/null)
  [ -f "$d/count" ] && record_stats "$d"
  # Minta mpv keluar sendiri dulu (jendela tertutup rapi, gambar kitty terhapus dari layar).
  (cd "$d" && echo quit | socat -t 0.2 - UNIX-CONNECT:mpv.sock) >/dev/null 2>&1
  rm -rf "$d"
  [ -n "${REELWAIT_IN_PLAYER:-}" ] && return 0 # dipanggil dari player sendiri: dia selesai sendiri
  while { pane_alive "$pane" || pid_alive "$pid"; } && [ $i -lt 10 ]; do sleep 0.1; i=$((i + 1)); done
  pane_alive "$pane" && tmux kill-pane -t "$pane" 2>/dev/null
  pid_alive "$pid" && { pkill -P "$pid"; kill "$pid"; } 2>/dev/null
  return 0
}

toggle() {
  local p=${REELWAIT_PANE:-$(session_key)} d
  if d=$(resolve_state "$p"); then
    stop_session "$d"
    return
  fi
  [ "$(pick_mode)" = window ] || [ -n "${TMUX:-}" ] || die "mode pane butuh tmux (atau pakai MODE=window)"
  d=$(state_dir "$p")
  kill_timer "$d"
  mkdir -p "$d" && date +%s > "$d/started"
  open_player "$p"
}
