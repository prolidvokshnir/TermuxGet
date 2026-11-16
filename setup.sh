#!/data/data/com.termux/files/usr/bin/bash
# Setup for the "get" downloader (Termux + yt-dlp)

pkg update -y
pkg install -y python ffmpeg curl
pip install -U yt-dlp
[ -d /sdcard ] || termux-setup-storage

# ---------- ~/.get_q.py ----------
cat > ~/.get_q.py << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
fs = d.get("formats", []) or []
dur = d.get("duration") or 0
def sz(f):
    s = f.get("filesize") or f.get("filesize_approx")
    if not s and f.get("tbr") and dur:
        s = f["tbr"] * 1000 / 8 * dur
    return s
audio = [sz(f) for f in fs if f.get("vcodec") == "none" and f.get("acodec") not in (None, "none")]
audio = [a for a in audio if a]
a = max(audio) if audio else 0
best = {}
for f in fs:
    h = f.get("height")
    if not h or f.get("vcodec") in (None, "none"):
        continue
    s = sz(f)
    if f.get("acodec") in (None, "none") and s:
        s += a
    if h not in best or (s or 0) > (best[h] or 0):
        best[h] = s
for h in sorted(best, reverse=True):
    s = best[h]
    print(h, "?" if not s else round(s / 1048576, 1))
PYEOF

# ---------- ~/get.sh ----------
cat > ~/get.sh << 'EOF'
_getbar() {
  local f=$(( $1 * $2 / 100 )) i
  BAR=$'\033[32m'
  for ((i=0;i<f;i++)); do BAR+="█"; done
  BAR+=$'\033[0m'
  for ((i=f;i<$2;i++)); do BAR+="░"; done
}
_getmb() {
  if [ "$1" -gt 0 ]; then
    SZ="$(( $1 / 1048576 )).$(( ($1 % 1048576) * 10 / 1048576 ))MB"
  else
    SZ="?MB"
  fi
}
_getdraw() {
  local pct=$(( ($2 - 1) * 100 + $3 ))
  pct=$(( pct / $1 ))
  _getbar "$pct" 10; local b1="$BAR"
  _getbar "$3" 10; local b2="$BAR"
  printf '\033[KTotal Videos %s [%s] %s%%\n\033[KVideo %s/%s %s [%s] %s%%\n' "$1" "$b1" "$pct" "$2" "$1" "$4" "$b2" "$3"
}
get() {
  local url="$1" folder base start end log ask=1
  local fmt="bv*+ba/b" choice h s i first_url live=0 cnt loc
  local -a Q arrh arrs
  if [ -z "$url" ]; then
    echo "Usage: get URL"
    return 1
  fi
  case "$url" in
    *tiktok.com*|tiktokuser:*) folder="TikTok"; ask=0 ;;
    *facebook.com*|*fb.watch*|*fb.com*) folder="Facebook"; ask=0 ;;
    *pinterest.*|*pin.it*) folder="Pinterest"; ask=0 ;;
    *twitter.com*|*://x.com/*|*://www.x.com/*|*://mobile.x.com/*) folder="X"; ask=0 ;;
    *xhamster*) folder="XHamster" ;;
    *pornhub.*) folder="Pornhub" ;;
    *youtube.com*|*youtu.be*) folder="YouTube" ;;
    *) folder=$(echo "$url" | sed -E 's#^https?://(www\.)?([^/]+).*#\2#') ;;
  esac
  base="/sdcard/Download/$folder"

  if [ "$ask" = 1 ]; then
    echo -e "\033[36mFetching exact sizes, please wait...\033[0m"
    first_url=$(yt-dlp --flat-playlist --playlist-items 1 --no-warnings --print url "$url" 2>/dev/null | head -1)
    [ -z "$first_url" ] && first_url="$url"
    yt-dlp -J --no-warnings --no-playlist "$first_url" 2>/dev/null > ~/.get_info.json
    mapfile -t Q < <(python3 ~/.get_q.py ~/.get_info.json)

    if [ ${#Q[@]} -eq 0 ]; then
      echo -e "\033[33mCould not read qualities, using Best.\033[0m"
    else
      echo
      echo -e "\033[36mSelect Video Quality:\033[0m"
      i=1
      for line in "${Q[@]}"; do
        read -r h s <<< "$line"
        arrh+=("$h"); arrs+=("$s")
        if [ "$s" = "?" ]; then
          printf '\033[32m%d.\033[0m %sp\n' "$i" "$h"
        else
          printf '\033[32m%d.\033[0m %sp  ->\033[33m %sMB\033[0m\n' "$i" "$h" "$s"
        fi
        i=$((i+1))
      done
      printf '\033[32m%d.\033[0m Best Quality (Default)\n' "$i"
      echo
      read -rp "$(echo -e "\033[36mEnter your choice (1-$i, default $i): \033[0m")" choice
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        h="${arrh[choice-1]}"
        fmt="b[height<=$h]/bv*[height<=$h]+ba/b"
      fi
    fi
  fi

  log=$(mktemp)
  echo
  printf '\033[96mPreparing, please wait...\033[0m'
  start=$(date +%s)
  local tpl="download:%(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(info.playlist_index)s %(info.n_entries)s %(progress.filename)s"
  local out="$base/%(uploader,channel,playlist_title|Unknown)s/%(title).100s.%(ext)s"
  PYTHONUNBUFFERED=1 yt-dlp -f "$fmt" --newline --no-colors --ignore-errors --continue --no-overwrites --download-archive ~/.get_archive.txt --quiet --no-warnings --progress --progress-template "$tpl" --print-to-file "after_move:filepath" "$log" -o "$out" "$url" 2> >(grep -v linker >&2) | while read -r got total est idx n fname; do
      [ "$total" = "NA" ] && total="$est"
      case "$got" in ''|*[!0-9]*) got=0 ;; esac
      case "$total" in ''|*[!0-9]*) total=0 ;; esac
      case "$idx" in ''|*[!0-9]*) idx=1 ;; esac
      case "$n" in ''|*[!0-9]*) n=1 ;; esac
      [ "$n" -lt 1 ] && n=1
      [ "$fname" = "NA" ] && fname=""
      nf="$fname"
      if [[ "$nf" =~ ^(.*)\.f[0-9]+(\.[A-Za-z0-9]+)$ ]]; then
        nf="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
      fi
      fp=0
      [ "$total" -gt 0 ] && fp=$(( got * 100 / total ))
      [ "$fp" -gt 100 ] && fp=100
      _getmb "$total"
      key="$idx|$nf"
      if [ "$key" != "${lastkey:-}" ]; then
        lastkey="$key"
        shown=0
        if [ "${pfirst:-0}" = 0 ] && [ -n "$nf" ]; then
          pfirst=1
          printf '\r\033[K'
          echo -e "\033[95mPath:\033[0m \033[94m${nf%/*}/\033[0m"
          echo -e "\033[96m-----------------------------\033[0m"
          live=0
        fi
        [ "$live" = 1 ] && printf '\033[2A'
        printf '\r'
        live=1
        _getdraw "$n" "$idx" 0 "$SZ"
      fi
      if [ "$fp" -gt "${shown:-0}" ]; then
        v="${shown:-0}"
        while [ "$v" -lt "$fp" ]; do
          v=$(( v + 10 ))
          [ "$v" -gt "$fp" ] && v="$fp"
          printf '\033[2A'
          _getdraw "$n" "$idx" "$v" "$SZ"
          sleep 0.02
        done
        shown="$fp"
      fi
    done
  end=$(date +%s)
  cnt=$(wc -l < "$log")
  if [ "$cnt" -eq 1 ]; then
    loc=$(head -1 "$log")
  elif [ "$cnt" -gt 1 ]; then
    loc=$(dirname "$(head -1 "$log")")
  else
    loc="$base"
  fi
  echo
  echo -e "\033[96m=============================\033[0m"
  echo -e "\033[92mDownload finished\033[0m"
  echo -e "\033[93mFiles:\033[0m    \033[97m$cnt\033[0m"
  echo -e "\033[93mSize:\033[0m     \033[97m$(tr '\n' '\0' < "$log" | xargs -0 -r du -ch 2>/dev/null | tail -1 | cut -f1)\033[0m"
  echo -e "\033[93mDuration:\033[0m \033[97m$(( end - start )) sec\033[0m"
  echo -e "\033[95mLocation:\033[0m \033[94m$loc\033[0m"
  echo -e "\033[95mURL:\033[0m      \033[94m$url\033[0m"
  rm -f "$log"
}
EOF

# ---------- load automatically in every Termux session ----------
grep -q 'source ~/get.sh' ~/.bashrc 2>/dev/null || echo 'source ~/get.sh' >> ~/.bashrc

echo
echo "Done. Close and reopen Termux, then: get URL"
