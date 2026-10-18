#!/usr/bin/env bash
# Smoke test: tmux server terpisah (-L rwtest), cache/config/HOME sementara.
# Tidak menyentuh tmux, cache, atau settings.json asli.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RW=$ROOT/bin/reelwait
TT=$(mktemp -d)
T="$TT/it's" # apostrof di path: menguji quoting command pane
mkdir -p "$T"
export REELWAIT_CACHE=$T/cache REELWAIT_CONF=$T/conf
mkdir -p "$REELWAIT_CONF" "$T/vids"
for c in red blue green; do
  ffmpeg -loglevel error -f lavfi -i "color=$c:size=160x120:rate=5:duration=60" -y "$T/vids/$c.mp4"
done
printf 'SOURCES=()\nLOCAL_DIR="%s"\nMODE=pane\n' "$T/vids" > "$REELWAIT_CONF/config"

tm() { tmux -L rwtest "$@"; }
tm -f /dev/null new-session -d -x 200 -y 50
P1=$(tm display -p '#{pane_id}')
export TMUX="$(tm display -p '#{socket_path}'),0,0" TMUX_PANE=$P1
trap 'tm kill-server 2>/dev/null; rm -rf "$TT"' EXIT

fail=0
check() { local name=$1; shift; if "$@"; then echo "ok    $name"; else echo "FAIL  $name"; fail=1; fi; }
wait_for() { local i=0; while [ $i -lt 50 ]; do "$@" && return 0; sleep 0.2; i=$((i + 1)); done; return 1; }
panes_is() { [ "$(tm list-panes -t "$1" | wc -l | tr -d ' ')" = "$2" ]; }
count_is() { [ "$(cat "$REELWAIT_CACHE/state/pane${P1#%}/count" 2>/dev/null)" = "$1" ]; }
reels_pane() { cat "$REELWAIT_CACHE/state/pane${P1#%}/pane.id"; }

# Timer di-cancel sebelum delay habis: panel tidak muncul.
"$RW" start --delay 2 && "$RW" stop
sleep 2.5
check "start+stop cepat: panel tidak muncul" panes_is "$P1" 1

t=$({ TIMEFORMAT=%R; time "$RW" start --delay 1 >/dev/null 2>&1; } 2>&1)
check "start exit < 100ms (${t}s)" awk -v t="$t" 'BEGIN { exit !(t < 0.1) }'
check "panel muncul setelah delay" wait_for panes_is "$P1" 2
check "fokus tetap di pane asal" [ "$(tm display -p -t "$P1" '#{pane_active}')" = 1 ]
check "reels pertama ter-load" wait_for count_is 1

REELWAIT_PANE=$P1 "$RW" next
check "next dari pane Claude ganti video" wait_for count_is 2
REELWAIT_PANE=$(reels_pane) "$RW" next
check "next dari pane reels ganti video" wait_for count_is 3

# Scroll trackpad: satu gesture (banyak event wheel beruntun) = satu video.
wheel() { (cd "$REELWAIT_CACHE/state/pane${P1#%}" && printf '{"command":["keypress","WHEEL_DOWN"]}\n' | socat -t 0.1 - UNIX-CONNECT:mpv.sock) >/dev/null; }
sleep 0.5; wheel; wheel; wheel; wheel
check "scroll 1 gesture = 1 video" wait_for count_is 4
sleep 1
check "scroll tidak lompat lebih dari 1" count_is 4

"$RW" stop; s1=$?
"$RW" stop; s2=$?
check "stop dua kali tidak error" [ "$s1$s2" = 00 ]
check "stop menutup panel" panes_is "$P1" 1
check "stats tercatat" grep -q ",pane${P1#%},4," "$REELWAIT_CACHE/stats.log"
check "stats hari ini" sh -c "'$RW' stats | grep -q 'Hari ini: 4 reels'"

# pane.id basi (tmux restart / pane ditutup manual) menunjuk pane lain: jangan dibunuh.
OTHER=$(tm split-window -d -t "$P1" -P -F '#{pane_id}' "sleep 300")
SD=$REELWAIT_CACHE/state/pane${P1#%}
mkdir -p "$SD" && echo "$OTHER" > "$SD/pane.id" && echo 1 > "$SD/count"
"$RW" start --delay 0
check "state basi: start tetap buka panel" wait_for panes_is "$P1" 3
"$RW" stop
other_alive() { tm display -p -t "$OTHER" '#{pane_start_command}' 2>/dev/null | grep -q 'sleep 300'; }
check "state basi: pane lain tidak dibunuh" other_alive
tm kill-pane -t "$OTHER"

# Dua sesi Claude di dua pane: independen.
P2=$(tm new-window -d -P -F '#{pane_id}')
"$RW" start --delay 0
TMUX_PANE=$P2 "$RW" start --delay 0
check "dua sesi buka panel masing-masing" wait_for sh -c "[ \$(tmux -L rwtest list-panes -t $P1 | wc -l) = 2 ] && [ \$(tmux -L rwtest list-panes -t $P2 | wc -l) = 2 ]"
TMUX_PANE=$P2 "$RW" stop
check "stop sesi 2 hanya tutup panel sesi 2" sh -c "[ \$(tmux -L rwtest list-panes -t $P2 | wc -l) = 1 ] && [ \$(tmux -L rwtest list-panes -t $P1 | wc -l) = 2 ]"
"$RW" stop

# Toggle manual dari keybind.
REELWAIT_PANE=$P1 "$RW" toggle
check "toggle buka panel" wait_for panes_is "$P1" 2
REELWAIT_PANE=$P1 "$RW" toggle
check "toggle tutup panel" wait_for panes_is "$P1" 1

# Di luar tmux: diam dan exit 0.
out=$(env -u TMUX -u TMUX_PANE "$RW" start 2>&1; env -u TMUX -u TMUX_PANE "$RW" stop 2>&1; echo "rc=$?")
check "di luar tmux: tanpa output, exit 0" [ "$out" = "rc=0" ]

vo() { env -u REELWAIT_VO ORCA_IMAGE_PROTOCOL=kitty bash -c ". '$ROOT/lib/render.sh'; pick_vo"; }
check "vo: terminal kitty + passthrough off -> tct" [ "$(vo)" = tct ]
tm set -g allow-passthrough on
check "vo: terminal kitty + passthrough on -> kitty" [ "$(vo)" = kitty ]
tm set -g allow-passthrough off
check "vo: VO di config dipakai" [ "$(env -u REELWAIT_VO VO=kitty bash -c ". '$ROOT/lib/render.sh'; pick_vo")" = kitty ]
check "vo: terminal biasa -> tct" [ "$(env -u REELWAIT_VO -u ORCA_IMAGE_PROTOCOL -u KITTY_WINDOW_ID bash -c ". '$ROOT/lib/render.sh'; pick_vo")" = tct ]

E=$(printf '\033')
got=$(printf '\033[0;4f\033_Ga=T,m=1;QUFB\033\\\033_Ga=d;\033[?25h\033[?1049l' | perl "$ROOT/lib/kitty-tmux.pl" 2 10)
want="${E}[0;4f${E}Ptmux;${E}${E}[3;14H${E}${E}_Ga=T,m=1;QUFB${E}${E}\\${E}\\${E}[?25h${E}Ptmux;${E}${E}_Ga=d${E}${E}\\${E}\\${E}[?1049l"
check "kitty-tmux: paket utuh + posisi layar + hapus gambar saat selesai" [ "$got" = "$want" ]

# Mode window (jendela mengambang): jalan tanpa tmux. vo/ao null supaya test tidak memunculkan jendela.
mkdir -p "$T/conf-win"
printf 'SOURCES=()\nLOCAL_DIR="%s"\nMODE=window\nMPV_OPTS="--vo=null --ao=null"\n' "$T/vids" > "$T/conf-win/config"
win() { env -u TMUX -u TMUX_PANE REELWAIT_CONF="$T/conf-win" CLAUDE_CODE_SESSION_ID=sess-1 "$RW" "$@"; }
WS=$REELWAIT_CACHE/state/panesess1
win_count_is() { [ "$(cat "$WS/count" 2>/dev/null)" = "$1" ]; }
out=$(win start --delay 1 2>&1; win stop 2>&1)
sleep 1.5
check "window: start+stop cepat tidak buka player, tanpa output" [ -z "$out" ] && [ ! -d "$WS" ]
win start --delay 0
check "window: player jalan tanpa tmux" wait_for win_count_is 1
win next
check "window: next lewat IPC" wait_for win_count_is 2
win stop
check "window: stop menutup player" sh -c "! pgrep -f 'state/panesess1/mpv.sock' >/dev/null"
win_cleaned() { [ ! -d "$WS" ] && grep -q ',panesess1,2,' "$REELWAIT_CACHE/stats.log"; }
check "window: state bersih + stats tercatat" win_cleaned
win toggle
check "window: toggle buka" wait_for win_count_is 1
win toggle 2>/dev/null
check "window: toggle tutup" sh -c "! pgrep -f 'state/panesess1/mpv.sock' >/dev/null"

# warm (hook SessionStart): tanpa output, cepat, dan tidak fetch lagi kalau baru saja fetch.
touch "$REELWAIT_CACHE/last-fetch"
out=$("$RW" warm 2>&1); rc=$?
check "warm: diam, exit 0, skip kalau baru fetch" sh -c "[ -z \"$out\" ] && [ $rc = 0 ] && ! pgrep -f 'reelwait fetch' >/dev/null"
check "plugin: hooks.json valid + semua event pakai CLAUDE_PLUGIN_ROOT" sh -c "jq -e '[.hooks[][].hooks[].command | test(\"CLAUDE_PLUGIN_ROOT\")] | all and length == 6' '$ROOT/hooks/hooks.json' >/dev/null"

check "limit tolak jam invalid" sh -c "! '$RW' limit --until 25:00 2>/dev/null"
"$RW" limit --until "$(date -v+5M +%H:%M 2>/dev/null || date -d '+5 min' +%H:%M)"
countdown_shown() { tm capture-pane -p -t "$(reels_pane)" 2>/dev/null | grep -Eq 'limit [0-9]+:[0-9]{2} lagi'; }
check "limit tampilkan countdown" wait_for countdown_shown
"$RW" stop
# Waktu limit habis: player keluar sendiri, pane tertutup, stats tercatat.
mkdir -p "$REELWAIT_CACHE/state/pane${P1#%}"
tm split-window -d -t "$P1" -e "REELWAIT_CACHE=$REELWAIT_CACHE" -e "REELWAIT_CONF=$REELWAIT_CONF" \
  "$RW" _player "$REELWAIT_CACHE/state/pane${P1#%}" $(($(date +%s) + 3))
check "limit habis: pane tutup sendiri" wait_for panes_is "$P1" 1
check "limit habis: state dibersihkan" [ ! -d "$REELWAIT_CACHE/state/pane${P1#%}" ]

# install -> install lagi -> uninstall mengembalikan config user.
H=$T/home
mkdir -p "$H/.claude"
echo '{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$H/.claude/settings.json"
printf 'set -g mouse on\n' > "$H/.tmux.conf"
cp "$H/.claude/settings.json" "$T/settings.orig"
cp "$H/.tmux.conf" "$T/tmux.orig"
inst() { env -u TMUX -u TMUX_PANE HOME="$H" TMUX_TMPDIR="$T" REELWAIT_SKIP_FETCH=1 "$ROOT/$1" >/dev/null; }
inst install.sh && inst install.sh
n=$(jq '[.hooks[][].hooks[] | select(.command | contains("reelwait"))] | length' "$H/.claude/settings.json")
check "install (2x) pasang tepat 6 hook" [ "$n" = 6 ]
check "hook StopFailure + SessionEnd" jq -e '.hooks.StopFailure and .hooks.SessionEnd' "$H/.claude/settings.json" >/dev/null
check "hook user tetap ada" jq -e '.hooks.Stop[] | select(.hooks[0].command == "echo mine")' "$H/.claude/settings.json" >/dev/null
tmux -L rwparse -f "$H/.tmux.conf" new-session -d 2>/dev/null
check "tmux.conf hasil install valid + Ctrl+b j terpasang" sh -c "tmux -L rwparse list-keys -T prefix j | grep -q reelwait"
tmux -L rwparse kill-server 2>/dev/null
check "keybind tmux terpasang sekali" [ "$(grep -c '>>> reelwait >>>' "$H/.tmux.conf")" = 1 ]
inst uninstall.sh
check "uninstall kembalikan settings.json" [ "$(jq -S . "$H/.claude/settings.json")" = "$(jq -S . "$T/settings.orig")" ]
check "uninstall kembalikan .tmux.conf" cmp -s "$H/.tmux.conf" "$T/tmux.orig"
check "uninstall hapus symlink" [ ! -e "$H/.local/bin/reelwait" ]
printf 'set -g mouse on\n# >>> reelwait >>>\nbind x y\nset -g status off\n' > "$H/.tmux.conf"
inst uninstall.sh
check "uninstall tanpa marker penutup tidak hapus config" grep -q 'status off' "$H/.tmux.conf"

[ $fail = 0 ] && echo "SEMUA LULUS" || echo "ADA YANG GAGAL"
exit $fail
