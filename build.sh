#!/usr/bin/env bash
# Build ai-devkit-win-portable.zip on Linux/macOS/WSL.
# Downloads upstream binaries, stages payload/, produces a single ZIP
# that a Windows user without admin rights can install via install.ps1.

set -euo pipefail

# ---- pinned versions ----
GIT_VERSION="2.54.0"
GIT_BUILD="1"                        # PortableGit-<ver>.windows.<build>
NODE_VERSION="24.16.0"
PYTHON_VERSION="3.14.3"
CLAUDE_CODE_VERSION="2.1.76"
AWSCLI_URL="https://awscli.amazonaws.com/AWSCLIV2.msi"

# ---- paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PAYLOAD_DIR="${BUILD_DIR}/payload"
DIST_DIR="${SCRIPT_DIR}/dist"
ZIP_NAME="ai-devkit-win-portable-$(date +%Y%m%d).zip"

# ---- helpers ----
log()  { printf "\033[1;34m[build]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m  %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[fail]\033[0m  %s\n" "$*" >&2; exit 1; }

require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing dependency: $cmd"
  done
}

fetch() {
  local url="$1" out="$2"
  if [[ -f "$out" ]]; then
    log "cached: $(basename "$out")"
    return 0
  fi
  log "fetch: $url"
  curl -fL --retry 3 --retry-delay 2 -o "$out.partial" "$url"
  mv "$out.partial" "$out"
}

# ---- prerequisites ----
require curl zip npm

# ---- prepare dirs ----
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$PAYLOAD_DIR" "$DIST_DIR"

# ---- PortableGit ----
GIT_FILE="PortableGit-${GIT_VERSION}-64-bit.7z.exe"
GIT_URL="https://github.com/git-for-windows/git/releases/download/v${GIT_VERSION}.windows.${GIT_BUILD}/${GIT_FILE}"
fetch "$GIT_URL" "$PAYLOAD_DIR/$GIT_FILE"

# ---- Node.js (ships with npm 11.x at this Node version) ----
NODE_FILE="node-v${NODE_VERSION}-win-x64.zip"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_FILE}"
fetch "$NODE_URL" "$PAYLOAD_DIR/$NODE_FILE"

# ---- Python embeddable + pip bootstrap ----
PY_FILE="python-${PYTHON_VERSION}-embed-amd64.zip"
PY_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PY_FILE}"
fetch "$PY_URL" "$PAYLOAD_DIR/$PY_FILE"
fetch "https://bootstrap.pypa.io/get-pip.py" "$PAYLOAD_DIR/get-pip.py"

# ---- AWS CLI v2 MSI (per-user install supported, no admin needed) ----
fetch "$AWSCLI_URL" "$PAYLOAD_DIR/AWSCLIV2.msi"

# ---- Claude Code: pack the npm tarball offline ----
log "npm pack @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
( cd "$PAYLOAD_DIR" && npm pack "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" >/dev/null )
# Resulting file: anthropic-ai-claude-code-<ver>.tgz

# ---- copy installer scripts ----
cp "$SCRIPT_DIR/install.ps1"   "$BUILD_DIR/install.ps1"
cp "$SCRIPT_DIR/activate.ps1"  "$BUILD_DIR/activate.ps1"
cp "$SCRIPT_DIR/uninstall.ps1" "$BUILD_DIR/uninstall.ps1"
cp "$SCRIPT_DIR/README.txt"    "$BUILD_DIR/README.txt"

# ---- write versions.json (read by install.ps1) ----
cat > "$BUILD_DIR/versions.json" <<EOF
{
  "git":          "${GIT_VERSION}",
  "node":         "${NODE_VERSION}",
  "python":       "${PYTHON_VERSION}",
  "claude_code":  "${CLAUDE_CODE_VERSION}",
  "git_file":     "${GIT_FILE}",
  "node_file":    "${NODE_FILE}",
  "python_file":  "${PY_FILE}"
}
EOF

# ---- zip it ----
log "zipping → ${DIST_DIR}/${ZIP_NAME}"
( cd "$BUILD_DIR" && zip -rq "${DIST_DIR}/${ZIP_NAME}" . )

log "done"
log "output: ${DIST_DIR}/${ZIP_NAME}"
log "size:   $(du -h "${DIST_DIR}/${ZIP_NAME}" | cut -f1)"
