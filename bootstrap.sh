#!/usr/bin/env bash
set -euo pipefail

APP_NAME="claude-diag"
SCRIPT_URL="https://cdiag.link/claude-diag.py"
REPOSITORY_URL="https://github.com/engels74/claude-diag"
tmpfile=""
PYTHON_BIN=""
PYTHON_VERSION=""
SKIPPED_CANDIDATES=()

say() {
  printf '%s\n' "$*" > /dev/tty
}

die() {
  printf '%s\n' "$APP_NAME: $*" >&2
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

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
  printf '%s\n' "$APP_NAME: interactive terminal required (/dev/tty unavailable)." >&2
  exit 1
fi

say ""
say "claude-diag"
say "Repository: $REPOSITORY_URL"
say ""
say "This bootstrap will:"
say "- choose a compatible Python runtime (3.12+, preferring 3.14)"
say "- download the diagnostic script"
say "- run it locally and redact sensitive values before output"
say ""

printf 'Continue? [y/N] ' > /dev/tty
IFS= read -r reply < /dev/tty || die "failed to read from /dev/tty"

case "$reply" in
  [yY]|[yY][eE][sS]) ;;
  *)
    say "Cancelled."
    exit 0
    ;;
esac

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
  say "Skipped Python candidates:"
  for item in "${SKIPPED_CANDIDATES[@]}"; do
    say "- $item"
  done
fi

if [ -z "$PYTHON_BIN" ]; then
  say ""
  say "No compatible Python runtime was found."
  say "Install one of:"
  say "- brew install python3"
  say "- uv python install 3.14"
  exit 1
fi

say "Using Python: $PYTHON_BIN ($PYTHON_VERSION)"

tmpfile="$(mktemp "${TMPDIR:-/tmp}/claude-diag.XXXXXX")"
chmod 600 "$tmpfile"

say "Downloading diagnostic script..."
curl -fsSL "$SCRIPT_URL" -o "$tmpfile"

"$PYTHON_BIN" "$tmpfile" "$@" < /dev/tty
