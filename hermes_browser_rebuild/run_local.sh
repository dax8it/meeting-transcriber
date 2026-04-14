#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/hermes_browser_rebuild/.venv"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PORT="${PORT:-8792}"
HOST="${HOST:-127.0.0.1}"

if [ ! -x "$VENV/bin/python" ]; then
  "$PYTHON_BIN" -m venv "$VENV"
fi

source "$VENV/bin/activate"
python -m pip install --upgrade pip >/dev/null
python -m pip install -r "$ROOT/hermes_browser_rebuild/requirements.txt" >/dev/null

exec python -m uvicorn hermes_browser_rebuild.app:app --host "$HOST" --port "$PORT"
