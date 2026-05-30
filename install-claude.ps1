#requires -version 5.1
<#
Standalone Claude Code installer for ai-devkit (Windows, user-mode).

Installs Claude Code via the official installer (https://claude.ai/install.ps1),
which downloads a native claude.exe, verifies its SHA256, runs `claude install`,
and places the launcher in %USERPROFILE%\.local\bin (the installer adds that dir
to the user PATH itself). No Node.js dependency. Internet is required.

This is the same step install.ps1 runs first; it lives here so Claude Code can
be installed (or reinstalled) on its own. install.ps1 delegates to this script.

Usage:
  powershell -ExecutionPolicy Bypass -File .\install-claude.ps1
  powershell -ExecutionPolicy Bypass -File .\install-claude.ps1 -Target latest
  powershell -ExecutionPolicy Bypass -File .\install-claude.ps1 -Target 2.1.149
#>
[CmdletBinding()]
param(
  # Install target passed to the official installer: "stable", "latest", or a
  # pinned semver. If omitted, read from versions.json (claude_code), else "stable".
  [string]$Target
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok  ([string]$msg) { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Die       ([string]$msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }

# Resolve target: explicit -Target wins, else versions.json (claude_code), else 'stable'.
if (-not $Target) {
  $ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
  $VersionsFile = Join-Path $ScriptDir 'versions.json'
  if (Test-Path $VersionsFile) {
    try {
      $V = Get-Content $VersionsFile -Raw | ConvertFrom-Json
      if (($V.PSObject.Properties.Name -contains 'claude_code') -and $V.claude_code) {
        $Target = $V.claude_code
      }
    } catch { }
  }
  if (-not $Target) { $Target = 'stable' }
}

Write-Step "Installing Claude Code (official installer)"
Write-Ok   "target version: $Target"
try {
  $bootstrap     = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1' -UseBasicParsing
  $installClaude = [scriptblock]::Create($bootstrap)
  & $installClaude $Target
} catch {
  Die "Claude Code install failed: $($_.Exception.Message)"
}

$ClaudeBin = Join-Path $env:USERPROFILE '.local\bin'
$ClaudeExe = Join-Path $ClaudeBin 'claude.exe'
if (-not (Test-Path $ClaudeExe)) {
  Write-Warn "claude.exe not found in $ClaudeBin (installer may use a different layout)."
} else {
  Write-Ok "claude -> $ClaudeExe"
}
