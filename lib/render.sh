# Pilih video output mpv: kitty (tajam) kalau terminal mendukung, selain itu tct (blok warna).
pick_vo() {
  local forced=${REELWAIT_VO:-${VO:-}} # env untuk sekali jalan, VO dari config untuk permanen
  if [ -n "$forced" ]; then echo "$forced"; return; fi
  local term="${KITTY_WINDOW_ID:+kitty} ${ORCA_IMAGE_PROTOCOL:-} ${TERM_PROGRAM:-}"
  # Di dalam tmux TERM_PROGRAM=tmux, jadi tanya tmux terminal aslinya.
  [ -n "${TMUX:-}" ] && term="$term $(tmux display -p '#{client_termtype}' 2>/dev/null)"
  case $term in
    *kitty* | *WezTerm* | *ghostty*)
      # Gambar kitty di tmux harus lewat passthrough; kalau dimatikan, pakai tct.
      if [ -n "${TMUX:-}" ]; then
        case $(tmux show -gv allow-passthrough 2>/dev/null) in on | all) ;; *) echo tct; return ;; esac
      fi
      echo kitty ;;
    *) echo tct ;;
  esac
}
