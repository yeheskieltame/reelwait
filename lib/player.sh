# mpv + IPC.

build_playlist() {
  local dirs=$VIDEOS local_dir=${LOCAL_DIR/#\~/$HOME}
  [ -n "$local_dir" ] && [ -d "$local_dir" ] && dirs="$dirs
$local_dir"
  local IFS='
'
  # shellcheck disable=SC2086
  find $dirs -type f \( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \) 2>/dev/null
}

player_run() { # $1 state dir, $2 opsional epoch akhir (mode limit)
  local d=$1 list=$1/playlist.m3u fp
  build_playlist > "$list" || return 0
  if [ ! -s "$list" ]; then
    echo "Cache reels masih kosong, lagi download... sabar ya."
    fetch_all >/dev/null 2>&1 &
    fp=$!
    until [ -s "$list" ]; do
      sleep 2
      [ -d "$d" ] || return 0
      build_playlist > "$list"
      if [ ! -s "$list" ] && ! kill -0 "$fp" 2>/dev/null; then
        echo "Gagal dapat video. Cek: reelwait doctor / reelwait fetch"
        sleep 5
        return 1
      fi
    done
  fi
  local vo extra="" row=""
  vo=$(pick_vo)
  if [ "${REELWAIT_MODE:-}" = window ]; then
    # Jendela mengambang ala picture-in-picture: di atas semua jendela, tanpa border,
    # tidak mencuri fokus, tanpa ikon Dock. Digambar GPU, jadi video & suara tetap sinkron.
    vo=gpu
    extra="--ontop --no-border --on-all-workspaces --keepaspect-window=no --geometry=$WINDOW --title=reelwait"
    [ "$(uname)" = Darwin ] && extra="$extra --focus-on=never --macos-app-activation-policy=accessory"
  fi
  # Mode limit di tct (tanpa OSD): sisakan baris terakhir untuk countdown (lihat reelwait.lua).
  if [ -n "${2:-}" ] && [ "$vo" = tct ] && row=$(tput lines 2>/dev/null); then
    extra="--vo-tct-height=$((row - 1))"
  fi
  # kitty kirim tiap frame sebagai gambar mentah (~1MB); 15fps supaya terminal tidak ikut lag.
  [ "$vo" = kitty ] && extra="--vf=fps=15"
  local wrap="" c r cw ch top left st pos
  if [ "$vo" = kitty ] && [ -n "${TMUX:-}" ]; then
    # stdout mpv disaring lib/kitty-tmux.pl, jadi ukuran pane harus diberikan eksplisit.
    c=$(tput cols) r=$(tput lines)
    read -r cw ch top left st pos <<<"$(tmux display -p -t "${TMUX_PANE:-}" \
      '#{client_cell_width} #{client_cell_height} #{pane_top} #{pane_left} #{status} #{status-position}')"
    [ "${cw:-0}" -gt 0 ] || { cw=8; ch=16; }
    [ "$pos" = top ] && [ "$st" != off ] && top=$((top + ${st/on/1}))
    extra="$extra --vo-kitty-cols=$c --vo-kitty-rows=$r --vo-kitty-width=$((c * cw)) --vo-kitty-height=$((r * ch))"
    wrap="$top $left"
  fi
  # shellcheck disable=SC2086
  set -- --vo="$vo" $extra --really-quiet --ytdl=no --loop-playlist=inf --shuffle \
    --mute="$MUTE" --keep-open=no --input-ipc-server="$d/mpv.sock" \
    --input-conf="$ROOT/config/input.conf" --script="$ROOT/lib/reelwait.lua" \
    --script-opts="reelwait-count=$d/count,reelwait-until=${2:-},reelwait-row=$row" \
    --playlist="$list" $MPV_OPTS
  # shellcheck disable=SC2086
  if [ -n "$wrap" ]; then in_pty mpv "$@" | perl "$ROOT/lib/kitty-tmux.pl" $wrap; else mpv "$@"; fi
}

# Jalankan "$@" di pty sendiri: kalau stdout mpv dipipe, mpv berhenti membaca keyboard.
in_pty() {
  if script -V 2>/dev/null | grep -q util-linux; then
    script -qfec "$(printf '%q ' "$@")" /dev/null
  else
    script -q /dev/null "$@"
  fi
}

# Sesi yang dikontrol: dari pane aktif (keybind kirim REELWAIT_PANE) / sesi Claude ini,
# kalau tidak ketemu, player yang terakhir dibuka.
find_session() {
  local s
  resolve_state "${REELWAIT_PANE:-$(session_key)}" && return 0
  # ponytail: "terakhir dibuka" cukup selama biasanya cuma satu player yang jalan.
  s=$(ls -t "$STATE_ROOT"/*/mpv.sock 2>/dev/null | head -1)
  [ -n "$s" ] && dirname "$s"
}

ipc() { # ipc <arg>... -> {"command":["arg",...]} ke socket mpv
  local d json
  d=$(find_session) || return 0
  json=$(printf '"%s",' "$@")
  # cd dulu: socat mem-parse ' " , : di alamat, path relatif menghindarinya.
  (cd "$d" && printf '{"command":[%s]}\n' "${json%,}" | socat -t 0.2 - UNIX-CONNECT:mpv.sock) >/dev/null 2>&1
  return 0
}

until_epoch() { # HH:MM -> epoch berikutnya jam itu (besok kalau sudah lewat)
  case $1 in [01][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9] | [0-9]:[0-5][0-9]) ;; *) return 1 ;; esac
  local now cur target diff
  now=$(date +%s)
  cur=$((10#$(date +%H) * 3600 + 10#$(date +%M) * 60 + 10#$(date +%S)))
  target=$((10#${1%%:*} * 3600 + 10#${1#*:} * 60))
  diff=$((target - cur))
  [ $diff -le 0 ] && diff=$((diff + 86400))
  echo $((now + diff))
}
