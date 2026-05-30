#!/usr/bin/env bash
# Generate versions.json — the manifest install.ps1 reads to know which
# tool versions to download at install time. No ZIP is produced anymore:
# the package is distributed via git (clone or GitHub "Download ZIP") and
# install.ps1 fetches every binary from the URLs recorded here.
#
# Usage:
#   ./build.sh              # write versions.json at the repo root (no network)
#   ./build.sh --prefetch   # also pre-download binaries into ./payload for
#                           # OFFLINE installs (install.ps1 skips any file
#                           # that already exists in ./payload)

set -euo pipefail

# ---- pinned versions (single source of truth) ----
GIT_VERSION="2.54.0"
GIT_BUILD="1"                        # PortableGit-<ver>.windows.<build>
NODE_VERSION="24.16.0"
PYTHON_VERSION="3.14.3"
CLAUDE_CODE_VERSION="2.1.76"
AWSCLI_URL="https://awscli.amazonaws.com/AWSCLIV2.msi"
GETPIP_URL="https://bootstrap.pypa.io/get-pip.py"

# ---- paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="${SCRIPT_DIR}/payload"
VERSIONS_FILE="${SCRIPT_DIR}/versions.json"

# ---- derived filenames + URLs ----
GIT_FILE="PortableGit-${GIT_VERSION}-64-bit.7z.exe"
GIT_URL="https://github.com/git-for-windows/git/releases/download/v${GIT_VERSION}.windows.${GIT_BUILD}/${GIT_FILE}"
NODE_FILE="node-v${NODE_VERSION}-win-x64.zip"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_FILE}"
PY_FILE="python-${PYTHON_VERSION}-embed-amd64.zip"
PY_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PY_FILE}"

# ---- helpers ----
log()  { printf "\033[1;34m[build]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[fail]\033[0m  %s\n" "$*" >&2; exit 1; }

require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing dependency: $cmd"
  done
}

fetch() {
  local url="$1" out="$2"
  if [[ -f "$out" ]]; then log "cached: $(basename "$out")"; return 0; fi
  log "fetch: $url"
  curl -fL --retry 3 --retry-delay 2 -o "$out.partial" "$url"
  mv "$out.partial" "$out"
}

# ---- write versions.json ----
log "writing $VERSIONS_FILE"
cat > "$VERSIONS_FILE" <<EOF
{
  "git":          "${GIT_VERSION}",
  "node":         "${NODE_VERSION}",
  "python":       "${PYTHON_VERSION}",
  "claude_code":  "${CLAUDE_CODE_VERSION}",
  "git_file":     "${GIT_FILE}",
  "node_file":    "${NODE_FILE}",
  "python_file":  "${PY_FILE}",
  "git_url":      "${GIT_URL}",
  "node_url":     "${NODE_URL}",
  "python_url":   "${PY_URL}",
  "getpip_url":   "${GETPIP_URL}",
  "awscli_url":   "${AWSCLI_URL}"
}
EOF
log "done: versions.json"

# ---- optional: pre-download binaries for offline installs ----
if [[ "${1:-}" == "--prefetch" ]]; then
  require curl npm
  mkdir -p "$PAYLOAD_DIR"
  fetch "$GIT_URL"    "$PAYLOAD_DIR/$GIT_FILE"
  fetch "$NODE_URL"   "$PAYLOAD_DIR/$NODE_FILE"
  fetch "$PY_URL"     "$PAYLOAD_DIR/$PY_FILE"
  fetch "$GETPIP_URL" "$PAYLOAD_DIR/get-pip.py"
  fetch "$AWSCLI_URL" "$PAYLOAD_DIR/AWSCLIV2.msi"
  log "npm pack @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
  ( cd "$PAYLOAD_DIR" && npm pack "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" >/dev/null )
  log "payload staged for offline install: $PAYLOAD_DIR"
fi
