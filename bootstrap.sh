#!/usr/bin/env bash
set -euo pipefail

APP_NAME="claude-diag"
SCRIPT_URL="https://cdiag.link/claude-diag.py"
tmpfile=""

say() {
  printf '%s\n' "$*" > /dev/tty
}

die() {
  printf '%s\n' "$APP_NAME: $*" >&2
  exit 1
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
say "Downloads and runs a redacted Claude Code diagnostic report generator."
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
command -v python3 >/dev/null 2>&1 || die "python3 is required."

if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)' >/dev/null 2>&1; then
  version="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null || printf 'unknown')"
  die "python3 3.12+ is required; found ${version}."
fi

tmpfile="$(mktemp "${TMPDIR:-/tmp}/claude-diag.XXXXXX")"
chmod 600 "$tmpfile"

say "Downloading diagnostic script..."
curl -fsSL "$SCRIPT_URL" -o "$tmpfile"

python3 "$tmpfile" "$@" < /dev/tty
