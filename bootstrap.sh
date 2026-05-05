#!/usr/bin/env bash
set -euo pipefail

APP_NAME="claude-diag"
SCRIPT_URL="https://cdiag.link/claude-diag.py"
REPOSITORY_URL="https://github.com/engels74/claude-diag"
tmpfile=""
PYTHON_BIN=""
PYTHON_VERSION=""
SKIPPED_CANDIDATES=()
COLOR_ENABLED=0
UNICODE_ENABLED=0

detect_color() {
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
}

detect_unicode() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UNICODE_ENABLED=1 ;;
    *) UNICODE_ENABLED=0 ;;
  esac
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

symbol() {
  local name="$1"
  if [ "$UNICODE_ENABLED" -eq 1 ]; then
    case "$name" in
      bullet) printf '•' ;;
      ok) printf '✓' ;;
      warn) printf '!' ;;
      error) printf '✕' ;;
      arrow) printf '→' ;;
    esac
  else
    case "$name" in
      bullet) printf '-' ;;
      ok) printf 'OK' ;;
      warn) printf '!' ;;
      error) printf 'ERROR' ;;
      arrow) printf '->' ;;
    esac
  fi
}

say() {
  printf '%s\n' "$*" > /dev/tty
}

status() {
  local kind="$1"
  shift
  local mark
  mark="$(symbol "$kind")"
  case "$kind" in
    ok) say "$(green "$mark") $*" ;;
    warn) say "$(yellow "$mark") $*" ;;
    error) say "$(red "$mark") $*" ;;
    *) say "$mark $*" ;;
  esac
}

step() {
  say "$(dim "$(symbol arrow)") $*"
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

detect_color
detect_unicode

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
  printf '%s\n' "$APP_NAME: interactive terminal required (/dev/tty unavailable)." >&2
  exit 1
fi

say ""
say "$(bold "claude-diag")"
say "Redacted Claude Code diagnostics for sharing and support."
say "$(dim "Repository: $REPOSITORY_URL")"
say ""
say "This will:"
say "  $(symbol bullet) choose a compatible Python runtime (3.12+, preferring 3.14)"
say "  $(symbol bullet) download the diagnostic script"
say "  $(symbol bullet) run locally and redact sensitive values before output"
say ""

printf '%s ' "$(bold "Continue?")$(dim " [y/N]")" > /dev/tty
IFS= read -r reply < /dev/tty || die "failed to read from /dev/tty"

case "$reply" in
  [yY]|[yY][eE][sS]) ;;
  *)
    status warn "Cancelled."
    exit 0
    ;;
esac

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
  say "$(dim "Skipped Python candidates:")"
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

step "Handing off to diagnostics"
"$PYTHON_BIN" "$tmpfile" "$@" < /dev/tty
