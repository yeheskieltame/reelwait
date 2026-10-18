# reelwait MVP Plan

Working name: `reelwait` (boleh diganti). CLI yang otomatis membuka panel reels pendek di tmux saat Claude Code sedang memproses lama, dan menutupnya saat Claude selesai atau butuh input.

## Tujuan MVP

1. Panel reels muncul otomatis kalau Claude memproses lebih dari N detik.
2. Panel tertutup otomatis saat Claude selesai (`Stop`) atau butuh input (`Notification`).
3. User bisa "swipe" (next/prev/mute/pause) tanpa pindah fokus dari pane Claude.
4. Mode limit manual dengan countdown.
5. Statistik lucu: jumlah reels yang ditonton per sesi.

## Non-goals (MVP)

- Tidak scraping TikTok/Instagram (melanggar ToS, rawan ban, endpoint sering berubah). Sumber MVP: YouTube Shorts via `yt-dlp` dan folder video lokal.
- Tidak support Windows native (macOS + Linux, WSL boleh best effort).
- Deteksi rate limit otomatis ditunda ke fase 2.

## Dependencies

`tmux`, `mpv` (&gt;= 0.36 untuk `--vo=kitty`), `yt-dlp`, `socat`, `jq`, `bash` &gt;= 4 (di macOS install via brew).

## Struktur repo

```
reelwait/
  bin/reelwait            # entry point bash, subcommand dispatcher
  lib/player.sh           # start/stop mpv + IPC
  lib/fetch.sh            # yt-dlp prefetch + cache management
  lib/tmux.sh             # split pane, simpan/hapus pane id
  lib/stats.sh            # counter reels + ringkasan
  lib/render.sh           # deteksi terminal -> pilih --vo
  config/default.conf
  config/input.conf       # keybind mpv
  install.sh
  uninstall.sh
  README.md
  tests/smoke.sh

```

## Config

Lokasi: `~/.config/reelwait/config` (copy dari `config/default.conf` saat install).

```
SOURCES=("ytsearch15:web3 developer shorts" "ytsearch15:coding memes shorts")
LOCAL_DIR=""               # opsional, folder video lokal
DELAY=8                    # detik sebelum panel muncul
PANE_SIZE=40%              # lebar split pane
MUTE=yes
MAX_CACHE_MB=500
MAX_HEIGHT=480             # resolusi download

```

Cache video: `~/.cache/reelwait/videos/`. State runtime: `~/.cache/reelwait/state/`.

## Subcommands


| Command                                     | Fungsi                                                                                                 |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `reelwait start [--delay N]`                | Mulai timer background. Kalau belum di-cancel setelah N detik, buka pane reels. Harus exit &lt; 100ms. |
| `reelwait stop`                             | Cancel timer, tutup pane, catat stats sesi. Idempotent.                                                |
| `reelwait toggle`                           | Buka/tutup manual.                                                                                     |
| `reelwait next` / `prev` / `mute` / `pause` | Kirim perintah ke mpv via IPC socket.                                                                  |
| `reelwait limit --until HH:MM`              | Buka pane dengan countdown overlay (mpv `show-text` tiap 1 detik via IPC).                             |
| `reelwait fetch`                            | Prefetch video dari SOURCES ke cache, hormati MAX\_CACHE\_MB (hapus file terlama).                     |
| `reelwait play`                             | Mode standalone di terminal saat ini (tanpa tmux).                                                     |
| `reelwait stats`                            | Tampilkan total reels hari ini dan per sesi.                                                           |
| `reelwait doctor`                           | Cek dependency, terminal, tmux, hooks terpasang.                                                       |


## Detail implementasi

### 1. Keying state per pane Claude

Hook mewarisi env dari proses Claude Code, jadi `$TMUX_PANE` = pane Claude. Semua state (pid timer, pane id reels, socket mpv, counter) disimpan di `state/<TMUX_PANE sanitized>/`. Ini bikin beberapa sesi Claude di pane berbeda tidak saling bentrok.

### 2. Start dengan delay (non-blocking)

```
reelwait start:
  kalau tidak di tmux ($TMUX kosong) -> exit 0 diam-diam
  kalau pane reels sudah ada -> exit 0
  spawn background: (sleep $DELAY && open_pane) & ; simpan pid ke timer.pid
  disown, redirect semua output ke /dev/null, exit 0

```

`stop` membunuh [`timer.pid`](http://timer.pid) dulu, baru tutup pane. Jadi respons cepat Claude tidak memunculkan panel.

### 3. Buka pane tmux

```
tmux split-window -h -d -l "$PANE_SIZE" -t "$TMUX_PANE" -P -F '#{pane_id}' "<mpv command>"

```

`-d` menjaga fokus tetap di pane Claude. Simpan pane id ke [`pane.id`](http://pane.id). Tutup dengan `tmux kill-pane -t <id>` (abaikan error kalau sudah tertutup).

### 4. Player mpv

```
mpv --vo=$VO --really-quiet --loop-playlist=inf --shuffle \
    --mute=$MUTE --input-ipc-server=$STATE/mpv.sock \
    --input-conf=$CONFIG/input.conf --keep-open=no \
    --playlist=<generated m3u dari cache + LOCAL_DIR>

```

[`render.sh`](http://render.sh) pilih `--vo`:

- `$KITTY_WINDOW_ID` ada, atau `$TERM_PROGRAM` = `WezTerm` / `ghostty` -&gt; `kitty`
- selain itu -&gt; `tct`
- override via env `REELWAIT_VO` Catatan: kitty graphics di dalam tmux butuh `set -g allow-passthrough on`. Kalau tidak bisa, fallback ke `tct`. `doctor` harus cek ini.

Kalau cache kosong: tampilkan pesan di pane dan jalankan `fetch` di background.

### 5. Swipe tanpa pindah fokus

`reelwait next` kirim ke socket:

```
echo '{"command":["playlist-next"]}' | socat - "$STATE/mpv.sock"

```

Install menambahkan blok tmux (dibungkus marker supaya bisa di-uninstall):

```
# >>> reelwait >>>
bind-key -n M-j run-shell -b "reelwait next"
bind-key -n M-k run-shell -b "reelwait prev"
bind-key -n M-m run-shell -b "reelwait mute"
bind-key -n M-p run-shell -b "reelwait pause"
bind-key -n M-r run-shell -b "reelwait toggle"
set -g allow-passthrough on
# <<< reelwait <<<

```

Penting: `run-shell` jalan dari server tmux, jadi `$TMUX_PANE` milik pane aktif. Pastikan resolusi state tetap ketemu (pakai `tmux display -p '#{pane_id}'`, lalu fallback cari state yang punya pane reels di window yang sama).

`input.conf` untuk saat fokus di pane reels: `j` next, `k` prev, `m` mute, `SPACE` pause, `q` quit.

### 6. Stats

Observe event `file-loaded` lewat IPC (`observe_property` atau loop `get_property playlist-pos`) di proses kecil background, increment `count`. Saat `stop`, append ke `~/.cache/reelwait/stats.log`: `timestamp,session_pane,count,duration_sec`. `stop` juga bisa `tmux display-message "brainrot: 12 reels selama Claude kerja 3m40s"`.

### 7. Fetch

```
yt-dlp -f "best[height<=$MAX_HEIGHT][ext=mp4]/best[height<=$MAX_HEIGHT]" \
  --match-filter "duration < 90" --no-playlist-reverse \
  --download-archive "$CACHE/archive.txt" \
  -o "$CACHE/videos/%(id)s.%(ext)s" "<source>"

```

Setelah download, prune cache sampai di bawah MAX_CACHE_MB (hapus file terlama). Jalankan via lock file supaya tidak dobel.

### 8. Hooks Claude Code

Sebelum menulis, **cek dulu schema hooks terbaru di dokumentasi Claude Code** (format `settings.json` dan nama event), jangan asumsi.

Target (ekspektasi format saat ini):

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "reelwait start" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "reelwait stop" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "reelwait stop" }] }]
  }
}

```

Aturan:

- Hook command harus selesai cepat dan selalu exit 0 (jangan pernah memblok atau mengubah perilaku Claude).
- Jangan print ke stdout dari hook (output `UserPromptSubmit` bisa masuk ke context Claude).
- Install merge ke `~/.claude/settings.json` pakai `jq`, backup dulu ke `settings.json.bak.<timestamp>`, jangan timpa hooks user yang sudah ada.

### 9. [install.sh](http://install.sh) / [uninstall.sh](http://uninstall.sh)

install: cek deps (tampilkan perintah brew/apt kalau kurang), symlink `bin/reelwait` ke `~/.local/bin`, copy config, merge hooks, tambah blok tmux, `tmux source-file ~/.tmux.conf` kalau tmux jalan, jalankan `reelwait fetch` di background. uninstall: hapus hook entries milik reelwait saja (match command `reelwait`), hapus blok marker tmux, hapus symlink. Cache dibiarkan kecuali `--purge`.

## Urutan eksekusi

1. Scaffold repo + [`render.sh`](http://render.sh) + `reelwait play` (bisa nonton dari cache lokal). Verifikasi manual.
2. [`fetch.sh`](http://fetch.sh) + prune cache.
3. [`tmux.sh`](http://tmux.sh) + `toggle` + IPC (`next/prev/mute/pause`).
4. `start/stop` dengan delay + state per pane.
5. Stats.
6. `limit --until` dengan countdown.
7. Hooks + install/uninstall + `doctor`.
8. README (gif demo placeholder, cara install, keybind, disclaimer konten).

## Acceptance test (tests/[smoke.sh](http://smoke.sh) + manual)

- `reelwait start --delay 2 && reelwait stop` dalam 1 detik: tidak ada pane muncul.
- `reelwait start --delay 2`, tunggu 3 detik: pane muncul, fokus tetap di pane asal.
- `Alt+j` ganti video tanpa pindah fokus.
- `reelwait stop` dua kali berturut-turut: tidak error.
- Dua sesi Claude di dua pane: masing-masing panel independen.
- Di luar tmux: hook tidak error dan tidak output apa-apa.
- Prompt singkat di Claude Code: panel tidak muncul. Task panjang: panel muncul, tertutup saat Claude selesai atau minta izin tool.
- Uninstall mengembalikan `settings.json` dan `.tmux.conf` tanpa merusak config lain.

## Fase 2 (setelah MVP)

- Deteksi rate limit otomatis (cek apakah ada hook event atau output yang bisa dipakai; kalau tidak, parse waktu reset dari pesan limit).
- "Productive mode": sumber konten edukasi dev/Web3 terkurasi.
- Fallback non-tmux (buka window terminal baru via kitty/wezterm CLI).
- Paket distribusi: Homebrew tap, npm wrapper.