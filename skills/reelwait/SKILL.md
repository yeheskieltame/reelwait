---
name: reelwait
description: Set up, control, or troubleshoot reelwait, the floating short-video (reels) window that opens while Claude Code is thinking and closes when Claude finishes. Use when the user mentions reelwait, wants reels/shorts/brainrot while waiting for Claude, asks why the video window doesn't appear, or wants to change its size, position, sound, sources, delay, or mode.
---

# reelwait

reelwait plays short vertical videos in a small floating mpv window while Claude Code is working. The plugin's hooks do everything automatically:

- `UserPromptSubmit` starts a timer. If Claude is still working after `DELAY` seconds (default 8), the window opens.
- `Stop`, `StopFailure`, `Notification` and `SessionEnd` close it.
- `SessionStart` refreshes the video cache in the background, at most once a day.

The window floats on top, has no border or Dock icon, and doesn't take keyboard focus, so the user keeps typing in Claude. The `reelwait` command is on the Bash tool's PATH while the plugin is enabled.

## First-time setup

1. Run `reelwait doctor` and read each line.
2. If a dependency shows `MISS`, tell the user which ones are missing and offer the install command. Run it only after the user agrees:
   - macOS: `brew install mpv yt-dlp socat jq` (tmux is only needed for pane mode)
   - Debian/Ubuntu: `sudo apt install mpv yt-dlp socat jq`
3. If the cache is empty, run `reelwait fetch` to download the first videos. It takes a minute or two; the window can't open until at least one video exists.
4. Ignore any `MISS hooks` or `MISS keybind tmux` lines that `doctor` prints when it runs as a plugin. The plugin provides the hooks, and the tmux keybinds are optional.

## Controls

Tell the user to type these at the Claude prompt with the `!` prefix, which runs them without a model turn:

| Command | Effect |
| --- | --- |
| `! reelwait next` / `! reelwait prev` | next / previous video |
| `! reelwait mute` / `! reelwait pause` | toggle sound / pause |
| `! reelwait toggle` | open or close the window manually |
| `! reelwait limit --until 23:00` | watch with a countdown, auto-close at that time |
| `! reelwait stats` | reels watched today |

Scrolling with a trackpad or mouse wheel over the window also switches videos, one video per gesture, without moving focus. After clicking the window, `j`, `k`, `m`, `SPACE` and `q` work too.

## Configuration

Settings live in `~/.config/reelwait/config` (bash syntax). The file may not exist yet; create it with only the keys the user wants to change, because missing keys fall back to defaults.

| Key | Default | Meaning |
| --- | --- | --- |
| `DELAY` | `8` | seconds Claude must be busy before the window opens |
| `WINDOW` | `"300x533-24+64"` | window size and position (mpv `--geometry`; `-24+64` = 24px from the right edge, 64px from the top) |
| `MUTE` | `yes` | start muted (`no` for sound) |
| `SOURCES` | YouTube `/shorts` tabs of dev channels | bash array of yt-dlp URLs, e.g. `("https://www.youtube.com/@Fireship/shorts" "ytsearch20:cat shorts")`; channel `/shorts` tabs reliably give vertical videos |
| `LOCAL_DIR` | empty | folder of the user's own videos to mix in |
| `MAX_CACHE_MB` | `500` | cache size limit; the oldest videos are deleted first |
| `MODE` | auto | `window` (floating window; default when a display exists) or `pane` (video inside a tmux pane, for SSH/headless) |
| `MPV_OPTS` | empty | extra mpv options, e.g. `"--volume=60"` |

Changes apply the next time the window opens. After editing `SOURCES`, run `reelwait fetch`.

## Troubleshooting

- **Window never appears:** run `reelwait doctor`.
  - Check that the cache has videos and that `mpv` is installed.
  - Remember the window only opens after `DELAY` seconds, so a quick answer from Claude won't show it. Run `reelwait toggle` to test right away.
- **Video stutters or the window is too small:** increase `WINDOW`, e.g. `"360x640-24+64"`.
- **The user is on SSH or a machine without a display:** use `MODE=pane` inside tmux. The video renders in a tmux pane instead, and it looks blocky in most terminals.
- **Two copies of the hooks:** an older manual install (`install.sh`) can coexist with the plugin. It is harmless because every command is idempotent, but `./uninstall.sh` from the repo removes the manual copy.

Content comes from YouTube via yt-dlp. reelwait doesn't scrape TikTok or Instagram.
