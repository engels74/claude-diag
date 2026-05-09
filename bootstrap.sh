#!/usr/bin/env bash
set -euo pipefail

APP_NAME="claude-diag"
SCRIPT_URL="https://sh.cdiag.link/claude-diag.py"
REPOSITORY_URL="https://github.com/engels74/claude-diag"
tmpfile=""
PYTHON_BIN=""
PYTHON_VERSION=""
SKIPPED_CANDIDATES=()
COLOR_ENABLED=0
UNICODE_ENABLED=0
DECORATED_ENABLED=0
TERM_WIDTH=80
PANEL_WIDTH=72

detect_terminal() {
  local cols

  if [ -n "${NO_COLOR:-}" ]; then
    COLOR_ENABLED=0
  elif [ "${FORCE_COLOR:-}" = "0" ]; then
    COLOR_ENABLED=0
  elif [ "${TERM:-}" = "dumb" ]; then
    COLOR_ENABLED=0
  elif [ -n "${FORCE_COLOR:-}" ]; then
    COLOR_ENABLED=1
  elif [ -t 1 ] || [ -t 2 ]; then
    COLOR_ENABLED=1
  else
    COLOR_ENABLED=0
  fi

  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UNICODE_ENABLED=1 ;;
    *) UNICODE_ENABLED=0 ;;
  esac

  if [ "${TERM:-}" != "dumb" ] && [ -t 1 -o -t 2 ]; then
    DECORATED_ENABLED=1
  else
    DECORATED_ENABLED=0
  fi

  cols="${COLUMNS:-}"
  if [ -z "$cols" ] && command -v tput >/dev/null 2>&1; then
    cols="$(tput cols 2>/dev/null || true)"
  fi
  case "$cols" in
    ''|*[!0-9]*) cols=80 ;;
  esac
  TERM_WIDTH="$cols"
  PANEL_WIDTH="$TERM_WIDTH"
  if [ "$PANEL_WIDTH" -gt 78 ]; then
    PANEL_WIDTH=78
  fi
  if [ "$PANEL_WIDTH" -lt 44 ]; then
    PANEL_WIDTH=44
  fi
}

style() {
  local code="$1"
  shift
  if [ "$COLOR_ENABLED" -eq 1 ]; then
    printf '\033[%sm%s\033[0m' "$code" "$*"
  else
    printf '%s' "$*"
  fi
}

bold() {
  style "1" "$*"
}

dim() {
  style "2" "$*"
}

green() {
  style "32" "$*"
}

yellow() {
  style "33" "$*"
}

red() {
  style "31" "$*"
}

blue() {
  style "34" "$*"
}

symbol() {
  local name="$1"
  if [ "$UNICODE_ENABLED" -eq 1 ]; then
    case "$name" in
      bullet) printf '•' ;;
      ok) printf '✓' ;;
      warn) printf '!' ;;
      error) printf '✕' ;;
      arrow) printf '→' ;;
      h) printf '─' ;;
      v) printf '│' ;;
      tl) printf '╭' ;;
      tr) printf '╮' ;;
      bl) printf '╰' ;;
      br) printf '╯' ;;
    esac
  else
    case "$name" in
      bullet) printf '-' ;;
      ok) printf 'OK' ;;
      warn) printf '!' ;;
      error) printf 'ERROR' ;;
      arrow) printf '->' ;;
      h) printf '-' ;;
      v) printf '|' ;;
      tl) printf '+' ;;
      tr) printf '+' ;;
      bl) printf '+' ;;
      br) printf '+' ;;
    esac
  fi
}

repeat_char() {
  local char="$1"
  local count="$2"
  local out=""
  while [ "$count" -gt 0 ]; do
    out="${out}${char}"
    count=$((count - 1))
  done
  printf '%s' "$out"
}

say() {
  printf '%s\n' "$*" > /dev/tty
}

frame_border() {
  local left="$1"
  local right="$2"
  local h
  h="$(repeat_char "$(symbol h)" "$((PANEL_WIDTH - 2))")"
  if [ "$COLOR_ENABLED" -eq 1 ]; then
    say "$(blue "${left}${h}${right}")"
  else
    say "${left}${h}${right}"
  fi
}

frame_line() {
  local text="${1:-}"
  local inner="$((PANEL_WIDTH - 4))"
  local len
  local pad

  len="${#text}"
  if [ "$len" -gt "$inner" ]; then
    text="${text:0:$((inner - 3))}..."
    len="${#text}"
  fi
  pad="$(repeat_char " " "$((inner - len))")"
  say "$(symbol v) ${text}${pad} $(symbol v)"
}

panel() {
  local title="$1"
  shift

  if [ "$DECORATED_ENABLED" -ne 1 ]; then
    say "$title"
    for line in "$@"; do
      if [ -n "$line" ]; then
        say "$line"
      else
        say ""
      fi
    done
    return
  fi

  frame_border "$(symbol tl)" "$(symbol tr)"
  frame_line "$title"
  frame_line ""
  for line in "$@"; do
    frame_line "$line"
  done
  frame_border "$(symbol bl)" "$(symbol br)"
}

divider() {
  if [ "$DECORATED_ENABLED" -eq 1 ]; then
    say "$(dim "$(repeat_char "$(symbol h)" "$PANEL_WIDTH")")"
  fi
}

status() {
  local kind="$1"
  shift
  local mark
  mark="$(symbol "$kind")"
  if [ "$DECORATED_ENABLED" -eq 1 ]; then
    case "$kind" in
      ok) say "$(green "$mark")  $*" ;;
      warn) say "$(yellow "$mark")  $*" ;;
      error) say "$(red "$mark")  $*" ;;
      *) say "$(dim "$mark")  $*" ;;
    esac
  else
    case "$kind" in
      ok) say "OK: $*" ;;
      warn) say "WARN: $*" ;;
      error) say "ERROR: $*" ;;
      *) say "$APP_NAME: $*" ;;
    esac
  fi
}

step() {
  if [ "$DECORATED_ENABLED" -eq 1 ]; then
    say "$(dim "$(symbol arrow)")  $*"
  else
    say "$APP_NAME: $*"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="$2"
  local suffix reply

  if [ "$default" = "yes" ]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  if [ "$DECORATED_ENABLED" -eq 1 ]; then
    printf '%s %s %s ' "$(bold "$prompt")" "$(dim "$suffix")" "$(dim "$(symbol arrow)")" > /dev/tty
  else
    printf '%s %s ' "$prompt" "$suffix" > /dev/tty
  fi
  IFS= read -r reply < /dev/tty || die "failed to read from /dev/tty"

  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    [nN]|[nN][oO]) return 1 ;;
    "")
      if [ "$default" = "yes" ]; then
        return 0
      fi
      return 1
      ;;
    *) return 1 ;;
  esac
}

die() {
  if [ "$COLOR_ENABLED" -eq 1 ]; then
    printf '%s\n' "$(red "$(symbol error)") $APP_NAME: $*" >&2
  else
    printf '%s\n' "$APP_NAME: $*" >&2
  fi
  exit 1
}

note_skip() {
  SKIPPED_CANDIDATES+=("$*")
}

cleanup() {
  if [ -n "${tmpfile:-}" ] && [ -f "$tmpfile" ]; then
    rm -f "$tmpfile"
  fi
}

on_signal() {
  cleanup
  exit 130
}

trap cleanup EXIT
trap on_signal HUP INT TERM

detect_terminal

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
  printf '%s\n' "$APP_NAME: interactive terminal required (/dev/tty unavailable)." >&2
  exit 1
fi

say ""
panel \
  "claude-diag" \
  "Redacted Claude Code diagnostics for sharing and support." \
  "Repository: $REPOSITORY_URL" \
  "" \
  "This will:" \
  "  $(symbol bullet) choose a compatible Python runtime (3.12+, preferring 3.14)" \
  "  $(symbol bullet) download the diagnostic script" \
  "  $(symbol bullet) run locally and redact sensitive values before output"
say ""

if ! prompt_yes_no "Continue?" "no"; then
  status warn "Cancelled."
  exit 0
fi
divider

step "Checking prerequisites"
command -v curl >/dev/null 2>&1 || die "curl is required."

try_python() {
  local path="$1"
  local version

  if [ -z "$path" ] || [ ! -x "$path" ]; then
    return 1
  fi

  version="$("$path" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null || true)"
  if [ -z "$version" ]; then
    note_skip "$path is not runnable"
    return 1
  fi

  if "$path" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)' >/dev/null 2>&1; then
    PYTHON_BIN="$path"
    PYTHON_VERSION="$version"
    return 0
  fi

  note_skip "$path $version is too old (need Python 3.12+)"
  return 1
}

find_path_command() {
  local name="$1"
  type -P "$name" 2>/dev/null || true
}

step "Selecting Python runtime"
for version in 3.14 3.13 3.12; do
  for prefix in /opt/homebrew /usr/local; do
    try_python "$prefix/bin/python$version" && break 2
  done
  try_python "$(find_path_command "python$version")" && break
done

if [ -z "$PYTHON_BIN" ]; then
  try_python "$(find_path_command python3)" || true
fi

if [ -z "$PYTHON_BIN" ]; then
  uv_path="$(find_path_command uv)"
  if [ -n "$uv_path" ]; then
    for version in 3.14 3.13 3.12; do
      uv_python="$("$uv_path" python find --no-project --no-python-downloads "$version" 2>/dev/null || true)"
      try_python "$uv_python" && break
    done
  fi
fi

if [ ${#SKIPPED_CANDIDATES[@]} -gt 0 ]; then
  say ""
  status warn "Skipped Python candidates:"
  for item in "${SKIPPED_CANDIDATES[@]}"; do
    say "$(dim "  $(symbol bullet) $item")"
  done
fi

if [ -z "$PYTHON_BIN" ]; then
  say ""
  status error "No compatible Python runtime was found."
  say "Install one of:"
  say "  $(symbol bullet) brew install python3"
  say "  $(symbol bullet) uv python install 3.14"
  exit 1
fi

status ok "Using Python: $PYTHON_BIN ($PYTHON_VERSION)"

tmpfile="$(mktemp "${TMPDIR:-/tmp}/claude-diag.XXXXXX")"
chmod 600 "$tmpfile"

step "Downloading diagnostic script"
curl -fsSL "$SCRIPT_URL" -o "$tmpfile"
status ok "Downloaded diagnostic script"

step "Handing off to diagnostics"
"$PYTHON_BIN" "$tmpfile" "$@" < /dev/tty
