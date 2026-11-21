# Shared helpers for before-after scripts. Source it: . "$(dirname "$0")/lib.sh"

die() { echo "$(basename "$0" .sh): $*" >&2; exit 1; }

# Worktree cache for one repo: <root>/<repo name>-<cksum of repo path>
ba_cache_dir() {
  local root=${BA_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/before-after} p
  case $root in /*) ;; *) root=$PWD/$root ;; esac
  p=$(cd "$1" 2>/dev/null && pwd -P) || p=$1  # same repo, same key: /x/repo/ = /x/repo, /tmp = /private/tmp
  printf '%s/%s-%s\n' "$root" "$(basename "$p")" "$(printf '%s' "$p" | cksum | cut -d' ' -f1)"
}

# Where Playwright keeps its browsers and its own ffmpeg (findings #1)
ba_playwright_cache() {
  if [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ]; then
    echo "$PLAYWRIGHT_BROWSERS_PATH"
  elif [ "$(uname)" = Darwin ]; then
    echo "$HOME/Library/Caches/ms-playwright"
  else
    echo "${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright"
  fi
}

# First H.264 encoder in the system ffmpeg: libx264, else libopenh264 (Fedora ffmpeg-free).
ba_h264() {
  local encs
  encs=$(ffmpeg -hide_banner -encoders 2>/dev/null) || return 1
  case $encs in
    *" libx264 "*) echo libx264 ;;
    *" libopenh264 "*) echo libopenh264 ;;
    *) return 1 ;;
  esac
}
