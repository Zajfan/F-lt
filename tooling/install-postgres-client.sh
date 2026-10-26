#!/usr/bin/env bash
set -euo pipefail

if command -v psql >/dev/null 2>&1; then
  printf 'psql is already installed: %s\n' "$(command -v psql)"
  exit 0
fi

if [[ "$(id -u)" -eq 0 ]]; then
  FALT_SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  FALT_SUDO=(sudo)
else
  printf 'Install PostgreSQL client with your system package manager; sudo is unavailable.\n' >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  "${FALT_SUDO[@]}" apt-get update
  "${FALT_SUDO[@]}" apt-get install -y postgresql-client
elif command -v dnf >/dev/null 2>&1; then
  "${FALT_SUDO[@]}" dnf install -y postgresql
elif command -v pacman >/dev/null 2>&1; then
  "${FALT_SUDO[@]}" pacman -Sy --needed postgresql-libs
else
  printf 'No supported package manager found; install the PostgreSQL client manually.\n' >&2
  exit 1
fi

psql --version
