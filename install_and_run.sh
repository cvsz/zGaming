#!/usr/bin/env bash
# Interactive/non-interactive installer + runner for bug_finder.py

set -Eeuo pipefail

log() { printf '[%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./install_and_run.sh [options]

Options:
  --project-path PATH   Absolute/relative path to project root (default: current dir)
  --python EXEC         Python executable for venv creation (default: python3)
  --api-key KEY         OpenAI API key (otherwise read from env/prompt)
  --remote-url URL      Git remote URL to set as origin
  --run-tests           Run pytest at end of setup
  --yes                 Non-interactive mode (requires needed inputs)
  -h, --help            Show this help
USAGE
}

PROJECT_PATH=""
PYTHON_EXEC=""
OPENAI_KEY="${OPENAI_API_KEY:-}"
REMOTE_URL=""
RUN_TESTS="false"
NON_INTERACTIVE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-path)
      PROJECT_PATH="${2:-}"
      shift 2
      ;;
    --python)
      PYTHON_EXEC="${2:-}"
      shift 2
      ;;
    --api-key)
      OPENAI_KEY="${2:-}"
      shift 2
      ;;
    --remote-url)
      REMOTE_URL="${2:-}"
      shift 2
      ;;
    --run-tests)
      RUN_TESTS="true"
      shift
      ;;
    --yes)
      NON_INTERACTIVE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

log "=== Interactive Installer for Repo ==="

if [[ -z "$PROJECT_PATH" ]]; then
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    PROJECT_PATH="$(pwd)"
  else
    read -r -p "Enter the absolute path to your project (default: $(pwd)): " PROJECT_PATH
    PROJECT_PATH=${PROJECT_PATH:-$(pwd)}
  fi
fi
[[ -d "$PROJECT_PATH" ]] || fail "Project path does not exist: $PROJECT_PATH"

if [[ -z "$PYTHON_EXEC" ]]; then
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    PYTHON_EXEC="python3"
  else
    read -r -p "Enter Python executable (default: python3): " PYTHON_EXEC
    PYTHON_EXEC=${PYTHON_EXEC:-python3}
  fi
fi
command -v "$PYTHON_EXEC" >/dev/null 2>&1 || fail "Python executable not found: $PYTHON_EXEC"

if [[ -d "$PROJECT_PATH/venv" ]]; then
  log "[SETUP] Reusing existing virtual environment: $PROJECT_PATH/venv"
else
  log "[SETUP] Creating virtual environment..."
  "$PYTHON_EXEC" -m venv "$PROJECT_PATH/venv"
fi

# shellcheck source=/dev/null
source "$PROJECT_PATH/venv/bin/activate"

log "[SETUP] Installing dependencies..."
python -m pip install --upgrade pip
if [[ -f "$PROJECT_PATH/requirements.txt" ]]; then
  python -m pip install -r "$PROJECT_PATH/requirements.txt"
else
  python -m pip install requests pytest
fi

if [[ -z "$OPENAI_KEY" ]]; then
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    fail "OPENAI API key is required in non-interactive mode (set OPENAI_API_KEY or pass --api-key)"
  fi
  read -r -s -p "Enter your OpenAI API Key (input hidden): " OPENAI_KEY
  echo
  [[ -n "$OPENAI_KEY" ]] || fail "API key cannot be empty"
fi
export OPENAI_API_KEY="$OPENAI_KEY"

ACTIVATE_FILE="$PROJECT_PATH/venv/bin/activate"
if ! grep -q "OPENAI_API_KEY" "$ACTIVATE_FILE"; then
  printf '\nexport OPENAI_API_KEY="%s"\n' "$OPENAI_API_KEY" >> "$ACTIVATE_FILE"
fi

cd "$PROJECT_PATH"
if [[ ! -d ".git" ]]; then
  log "[SETUP] Initializing Git repository..."
  git init
fi

if [[ -z "$REMOTE_URL" && "$NON_INTERACTIVE" != "true" ]]; then
  read -r -p "Enter remote Git URL (leave blank to skip): " REMOTE_URL
fi
if [[ -n "$REMOTE_URL" ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    log "[INFO] Remote origin already exists. Skipping update."
  else
    git remote add origin "$REMOTE_URL"
  fi
fi

if [[ "$RUN_TESTS" != "true" && "$NON_INTERACTIVE" != "true" ]]; then
  read -r -p "Do you want to run initial tests with pytest? (y/n): " TEST_CONFIRM
  [[ "$TEST_CONFIRM" == "y" ]] && RUN_TESTS="true"
fi

if [[ "$RUN_TESTS" == "true" ]]; then
  pytest || log "[WARNING] Initial tests failed; please check manually."
fi

log "[SETUP] bug_finder.py is already included in the project root."
log "=== Installation Complete ==="
log "To start bug finder loop, run:"
echo "source $PROJECT_PATH/venv/bin/activate"
echo "python $PROJECT_PATH/bug_finder.py --project-path $PROJECT_PATH"
