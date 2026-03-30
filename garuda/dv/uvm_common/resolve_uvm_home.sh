#!/usr/bin/env bash
set -euo pipefail

# Resolve a usable UVM_HOME and print it to stdout.
# Priority:
# 1) Existing UVM_HOME env var
# 2) Repo-local third_party/uvm-1.2
# 3) Optional auto-fetch (AUTO_FETCH_UVM=1)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOCAL_UVM_DIR="$ROOT_DIR/third_party/uvm-1.2"

is_valid_uvm() {
  local d="$1"
  [[ -n "$d" ]] && [[ -f "$d/src/uvm_pkg.sv" ]]
}

if is_valid_uvm "${UVM_HOME:-}"; then
  echo "$UVM_HOME"
  exit 0
fi

if is_valid_uvm "$LOCAL_UVM_DIR"; then
  echo "$LOCAL_UVM_DIR"
  exit 0
fi

if [[ "${AUTO_FETCH_UVM:-0}" == "1" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] AUTO_FETCH_UVM=1 but git is not installed." >&2
    exit 1
  fi

  mkdir -p "$ROOT_DIR/third_party"
  if [[ ! -d "$LOCAL_UVM_DIR/.git" ]]; then
    echo "[INFO] Fetching UVM into $LOCAL_UVM_DIR" >&2
    git clone --depth 1 https://github.com/accellera-official/uvm-core.git "$LOCAL_UVM_DIR" >&2
  fi

  if is_valid_uvm "$LOCAL_UVM_DIR"; then
    echo "$LOCAL_UVM_DIR"
    exit 0
  fi
fi

echo "[ERROR] UVM_HOME is not set and no local UVM found." >&2
echo "Set UVM_HOME to a directory containing src/uvm_pkg.sv" >&2
echo "or place UVM at: $LOCAL_UVM_DIR" >&2
echo "or run with AUTO_FETCH_UVM=1 to auto-clone UVM core." >&2
exit 1
