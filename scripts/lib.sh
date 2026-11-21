# Shared helpers for provenfix scripts. Source it: . "$(dirname "$0")/lib.sh"

die() { echo "$(basename "$0" .sh): $*" >&2; exit 1; }

# Worktree cache for one repo: <root>/<repo name>-<cksum of repo path>
ba_cache_dir() {
  local root=${BA_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/provenfix} p
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

# ba_lstart <pid>: the process start time, whitespace trimmed. macOS ps pads "-o lstart=" with
# trailing spaces that `read` strips from the pid file, so every writer and reader goes through here.
ba_lstart() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

# ba_json '<js expression over j>': read JSON on stdin, print the expression's value, one line per array item.
# node, not jq: Playwright MCP already needs node, jq would be a new dependency.
ba_json() {
  command -v node >/dev/null 2>&1 || die "node not found (Playwright MCP needs it too)"
  node -e 'let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
    const j = JSON.parse(s); const v = eval(process.argv[1]);
    for (const l of [].concat(v)) if (l !== undefined && l !== null && l !== "") console.log(l); });' "$1"
}

# ba_forge: github when origin points at GitHub, else gitlab (gitlab.com and self-hosted alike)
ba_forge() {
  case $(git remote get-url origin 2>/dev/null) in *github*) echo github ;; *) echo gitlab ;; esac
}
