# yt-dlp prefetch + batas ukuran cache.

fetch_all() {
  local lock=$CACHE/fetch.lock s
  find "$lock" -maxdepth 0 -mmin +30 -exec rmdir {} \; 2>/dev/null # lock basi dari fetch yang di-kill
  mkdir "$lock" 2>/dev/null || { echo "fetch lain masih jalan"; return 0; }
  trap "rmdir '$lock' 2>/dev/null" EXIT
  for s in ${SOURCES[@]+"${SOURCES[@]}"}; do
    echo "fetch: $s"
    yt-dlp --quiet --no-warnings \
      -f "b[height<=$MAX_HEIGHT][ext=mp4]/bv*[height<=$MAX_HEIGHT]+ba/b[height<=$MAX_HEIGHT]" \
      --merge-output-format mp4 --match-filter "duration < 90 & !is_live & aspect_ratio <? 1" \
      --download-archive "$CACHE/archive.txt" --max-downloads 15 \
      -P "temp:$CACHE/tmp" -o "$VIDEOS/%(id)s.%(ext)s" "$s"
  done
  prune_cache
  [ -n "$(ls "$VIDEOS")" ] && touch "$CACHE/last-fetch" # dibaca `reelwait warm`
  echo "cache: $(ls "$VIDEOS" | wc -l | tr -d ' ') video"
}

# ponytail: du per file yang dihapus, O(n^2) tapi n cuma ratusan video.
prune_cache() {
  local f
  while [ "$(du -sk "$VIDEOS" | cut -f1)" -gt $((MAX_CACHE_MB * 1024)) ]; do
    f=$(ls -tr "$VIDEOS" | head -1)
    [ -n "$f" ] || break
    rm -f "$VIDEOS/$f"
  done
}
