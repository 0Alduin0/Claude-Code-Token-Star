#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PYTHON=""
for CANDIDATE in python3 python; do
  if command -v "$CANDIDATE" >/dev/null 2>&1 &&
    "$CANDIDATE" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
    PYTHON=$CANDIDATE
    break
  fi
done
[ -n "$PYTHON" ] || { echo "Python 3.10+ was not found on PATH." >&2; exit 1; }
exec "$PYTHON" "$SCRIPT_DIR/token-mass.py" --uninstall "$@"
