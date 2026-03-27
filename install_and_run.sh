#!/usr/bin/env bash
# Interactive installer + runner for bug_finder.py

set -Eeuo pipefail

log() { printf '[%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

log "=== Interactive Installer for Repo ==="

read -r -p "Enter the absolute path to your project (default: $(pwd)): " PROJECT_PATH
PROJECT_PATH=${PROJECT_PATH:-$(pwd)}
[[ -d "$PROJECT_PATH" ]] || fail "Project path does not exist: $PROJECT_PATH"

read -r -p "Enter Python executable (default: python3): " PYTHON_EXEC
PYTHON_EXEC=${PYTHON_EXEC:-python3}
command -v "$PYTHON_EXEC" >/dev/null 2>&1 || fail "Python executable not found: $PYTHON_EXEC"

log "[SETUP] Creating virtual environment..."
"$PYTHON_EXEC" -m venv "$PROJECT_PATH/venv"
# shellcheck source=/dev/null
source "$PROJECT_PATH/venv/bin/activate"

log "[SETUP] Installing dependencies..."
python -m pip install --upgrade pip
python -m pip install requests pytest

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  read -r -s -p "Enter your OpenAI API Key (input hidden): " OPENAI_KEY
  echo
  [[ -n "$OPENAI_KEY" ]] || fail "API key cannot be empty"
  export OPENAI_API_KEY="$OPENAI_KEY"
fi

ACTIVATE_FILE="$PROJECT_PATH/venv/bin/activate"
if ! grep -q "OPENAI_API_KEY" "$ACTIVATE_FILE"; then
  printf '\nexport OPENAI_API_KEY="%s"\n' "$OPENAI_API_KEY" >> "$ACTIVATE_FILE"
fi

cd "$PROJECT_PATH"
if [[ ! -d ".git" ]]; then
  log "[SETUP] Initializing Git repository..."
  git init
fi

read -r -p "Enter remote Git URL (leave blank to skip): " REMOTE_URL
if [[ -n "$REMOTE_URL" ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    log "[INFO] Remote origin already exists."
  else
    git remote add origin "$REMOTE_URL"
  fi
fi

read -r -p "Do you want to run initial tests with pytest? (y/n): " RUN_TESTS
if [[ "$RUN_TESTS" == "y" ]]; then
  pytest || log "[WARNING] Initial tests failed; please check manually."
fi

log "[SETUP] bug_finder.py is already included in the project root."
log "=== Installation Complete ==="
log "To start bug finder loop, run:"
echo "source $PROJECT_PATH/venv/bin/activate"
echo "python $PROJECT_PATH/bug_finder.py --project-path $PROJECT_PATH"
