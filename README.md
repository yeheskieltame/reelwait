# reelwait

Jendela reels kecil yang mengambang di pojok layar saat Claude Code mikir lama, dan tertutup sendiri begitu Claude selesai atau butuh input kamu. Jendelanya tidak mencuri fokus, jadi kamu tetap bisa mengetik di Claude.

![demo](docs/demo.gif) <!-- TODO: rekam gif demo -->

## Cara kerja

- Hook `UserPromptSubmit` → `reelwait start`: timer background. Kalau Claude belum selesai setelah `DELAY` detik, player reels dibuka.
- Dua mode:
  - `window` (default kalau ada layar): jendela mpv mengambang ala picture-in-picture, di atas semua jendela, tanpa border, tanpa ikon Dock, tidak mencuri fokus. Digambar GPU, jadi video dan suara sinkron. Tidak butuh tmux.
  - `pane` (default tanpa layar, mis. SSH): video di pane tmux sebelah kanan. Kasar (tct) atau tajam lewat protokol kitty, tapi lebih berat dan bisa tertinggal dari suara.
- Hook `Stop` / `StopFailure` / `Notification` / `SessionEnd` → `reelwait stop`: timer dibatalkan, pane ditutup, stats dicatat.
- Batasan: Claude Code tidak mengirim hook saat kamu menekan Esc. Kalau Esc ditekan sebelum `DELAY` habis, panel tetap muncul; tutup dengan `Alt+r` atau `q`.
- Tiap sesi Claude punya state sendiri (per pane tmux, atau per session id Claude Code), jadi beberapa sesi tidak saling ganggu.
- Hook selalu exit 0 tanpa output. Di mode pane, di luar tmux hook diam saja.

## Install

Butuh macOS atau Linux dengan layar, plus `mpv`, `yt-dlp`, `socat`, `jq`:

```sh
brew install mpv yt-dlp socat jq   # Linux: sudo apt install mpv yt-dlp socat jq
```

### Sebagai plugin Claude Code (disarankan)

Di Claude Code:

```
/plugin install reelwait --marketplace yeheskieltame/reelwait
```

(Claude Code sebelum 2.1.275: `/plugin marketplace add yeheskieltame/reelwait` lalu `/plugin install reelwait@reelwait`.)

Selesai. Plugin memasang hook-nya sendiri, dan perintah `reelwait` otomatis ada di PATH untuk `! reelwait …`. Cek dengan `! reelwait doctor`; video pertama di-download otomatis di background saat sesi dimulai. Minta Claude "setup reelwait" kalau ada yang kurang, karena plugin ini juga membawa skill untuk itu.

### Manual (tanpa plugin)

```sh
git clone https://github.com/yeheskieltame/reelwait && cd reelwait && ./install.sh
```

`install.sh` akan:
- symlink `bin/reelwait` ke `~/.local/bin/reelwait`
- menyalin config ke `~/.config/reelwait/config`
- merge hooks ke `~/.claude/settings.json` (backup dulu ke `settings.json.bak.<waktu>`, hook lain tidak disentuh)
- menambah blok keybind ke `~/.tmux.conf`
- mulai download reels di background

Copot: `./uninstall.sh` (tambah `--purge` untuk ikut hapus cache dan config). Pilih salah satu cara install; kalau dua-duanya terpasang tetap aman (semua perintah idempotent), hanya dobel.

## Kontrol

Mode window: **scroll trackpad/mouse di atas jendela = ganti video** (satu gesture = satu video, tanpa pindah fokus). Atau ketik di Claude: `! reelwait next`, `! reelwait prev`, `! reelwait mute`, `! reelwait toggle`. Klik jendelanya kalau mau pakai `j` / `k` / `m` / `SPACE` / `q`.

Dari pane mana pun di tmux (tanpa pindah fokus):

| Tombol  | Aksi            |
| ------- | --------------- |
| `Alt+j` | video berikutnya |
| `Alt+k` | video sebelumnya |
| `Alt+m` | mute/unmute     |
| `Alt+p` | pause           |
| `Alt+r` | buka/tutup panel manual |
| `Ctrl+b j` / `Ctrl+b k` | next / prev (cadangan kalau Alt tidak jalan; bisa diulang `Ctrl+b j j j`) |
| `Ctrl+b R` | buka/tutup panel |

Di macOS, Option harus diset sebagai Meta di terminal kamu supaya `Alt+…` jalan. Kalau tidak bisa, pakai `Ctrl+b …`.

Di mode pane, scroll di atas video hanya sampai ke player kalau mouse tmux aktif: `set -g mouse on`.

Kalau fokus di pane/jendela reels: `j` / `k` / `m` / `SPACE` / `q`.

## Command

```
reelwait start [--delay N]    timer, buka panel setelah N detik (dipakai hook)
reelwait stop                 batalkan timer + tutup panel (dipakai hook)
reelwait toggle               buka/tutup manual
reelwait next|prev|mute|pause
reelwait limit --until HH:MM  nonton dengan countdown, tutup sendiri di jam itu
reelwait fetch                download reels ke cache
reelwait play                 nonton di terminal ini tanpa tmux
reelwait stats                total reels hari ini
reelwait doctor               cek dependency dan setup
```

## Config

`~/.config/reelwait/config`:

```sh
SOURCES=("https://www.youtube.com/@Fireship/shorts" "https://www.youtube.com/@TheCodingSloth/shorts" "https://www.youtube.com/@ThePrimeTimeagen/shorts" "https://www.youtube.com/@PatrickAlphaC/shorts")
LOCAL_DIR=""      # folder video lokal (opsional)
DELAY=8           # detik sebelum panel muncul
MODE=""           # kosong = otomatis, atau window / pane
WINDOW="300x533-24+64"  # mode window: ukuran & posisi (pojok kanan atas)
PANE_SIZE=40%     # mode pane
MUTE=yes
MAX_CACHE_MB=500
MAX_HEIGHT=480
VO=""             # mode pane: kosong = otomatis, atau kitty / tct
MPV_OPTS=""       # opsi mpv tambahan, mis. "--volume=60"
```

Cache video ada di `~/.cache/reelwait/videos/`, stats di `~/.cache/reelwait/stats.log`.

Mode pane: di terminal yang mendukung gambar kitty (kitty, Ghostty, WezTerm, Orca) video tampil tajam lewat `--vo=kitty` (di tmux lewat `allow-passthrough`, dibatasi 15fps supaya terminal tidak lag). Terminal lain memakai `--vo=tct` (blok warna, kasar tapi jalan di mana saja). Kalau deteksi otomatis meleset (misalnya tmux dijalankan dengan env minimal), isi `VO=kitty` atau `VO=tct` di config.

## Test

```sh
tests/smoke.sh
```

Smoke test jalan di tmux server terpisah dengan cache dan HOME sementara, jadi setup asli kamu tidak tersentuh.

## Disclaimer konten

reelwait tidak scraping TikTok/Instagram. Sumbernya YouTube Shorts lewat `yt-dlp` (hasil pencarian `SOURCES`) dan folder video lokal kamu. Isi video sepenuhnya milik pembuatnya dan tergantung hasil pencarian; atur `SOURCES` sesuai selera. Tanggung jawab penggunaan ada di kamu, termasuk soal ToS YouTube.
