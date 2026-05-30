#requires -version 5.1
<#
ai-devkit portable installer for Windows.
Runs entirely in user-mode: no admin, no UAC, no MSI elevation.
Installs Git, Node.js, npm, Python, AWS CLI, and Claude Code into
%USERPROFILE%\ai-devkit, then adds each tool to the user PATH.

Tool binaries are downloaded from upstream at install time (an internet
connection is required). URLs are read from versions.json. If a matching
file already exists in .\payload it is reused instead of re-downloaded,
so a maintainer can pre-stage .\payload (./build.sh --prefetch) for a
fully offline install.

Usage:
  powershell -ExecutionPolicy Bypass -File .\install.ps1
#>

[CmdletBinding()]
param(
  [string]$InstallRoot = (Join-Path $env:USERPROFILE 'ai-devkit'),
  [switch]$NoPathUpdate,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------- helpers ----------
function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok  ([string]$msg) { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Die       ([string]$msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }

function Add-UserPath([string]$dir) {
  if (-not (Test-Path $dir)) { return }
  $current = [Environment]::GetEnvironmentVariable('Path','User')
  if (-not $current) { $current = '' }
  $parts = $current -split ';' | Where-Object { $_ -and ($_ -ne $dir) }
  $parts = ,$dir + $parts
  $newPath = ($parts -join ';').TrimEnd(';')
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  # propagate to current session
  $env:Path = "$dir;$env:Path"
}

# ---------- download helper ----------
# Reuse a pre-staged file in .\payload if present, otherwise download it.
function Get-Payload([string]$url, [string]$dest) {
  $name = Split-Path $dest -Leaf
  if (Test-Path $dest) { Write-Ok "cached: $name"; return }
  Write-Ok "downloading: $name"
  try {
    Invoke-WebRequest -Uri $url -OutFile "$dest.partial" -UseBasicParsing
    Move-Item "$dest.partial" $dest -Force
  } catch {
    if (Test-Path "$dest.partial") { Remove-Item "$dest.partial" -Force }
    Die "failed to download $name from $url`n$($_.Exception.Message)"
  }
}

# ---------- locate manifest + payload ----------
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$PayloadDir  = Join-Path $ScriptDir 'payload'
$VersionsFile= Join-Path $ScriptDir 'versions.json'
if (-not (Test-Path $VersionsFile)) { Die "versions.json not found next to install.ps1" }
if (-not (Test-Path $PayloadDir))   { New-Item -ItemType Directory -Path $PayloadDir | Out-Null }

$V = Get-Content $VersionsFile -Raw | ConvertFrom-Json

Write-Step "ai-devkit portable installer"
Write-Ok   "install root : $InstallRoot"
Write-Ok   "payload dir  : $PayloadDir"

# ---------- 0. download binaries (skips any already in payload\) ----------
Write-Step "Downloading tool binaries (reusing payload\ when present)"
Get-Payload $V.git_url    (Join-Path $PayloadDir $V.git_file)
Get-Payload $V.node_url   (Join-Path $PayloadDir $V.node_file)
Get-Payload $V.python_url (Join-Path $PayloadDir $V.python_file)
Get-Payload $V.getpip_url (Join-Path $PayloadDir 'get-pip.py')
Get-Payload $V.awscli_url (Join-Path $PayloadDir 'AWSCLIV2.msi')

if ((Test-Path $InstallRoot) -and -not $Force) {
  Write-Warn "$InstallRoot already exists. Re-run with -Force to overwrite."
} else {
  if (Test-Path $InstallRoot) { Remove-Item $InstallRoot -Recurse -Force }
  New-Item -ItemType Directory -Path $InstallRoot | Out-Null
}

# ---------- 1. PortableGit ----------
Write-Step "Installing Git $($V.git)"
$GitDir = Join-Path $InstallRoot 'git'
$GitExe = Join-Path $PayloadDir $V.git_file
if (-not (Test-Path $GitExe)) { Die "missing $($V.git_file)" }
New-Item -ItemType Directory -Path $GitDir -Force | Out-Null
# 7z self-extractor: -y silent, -o<dir> output
& $GitExe -y -gm2 "-o$GitDir" | Out-Null
if (-not (Test-Path (Join-Path $GitDir 'cmd\git.exe'))) { Die "git extraction failed" }
Write-Ok "git → $GitDir\cmd\git.exe"

# ---------- 2. Node.js + npm ----------
Write-Step "Installing Node.js $($V.node) (npm bundled)"
$NodeZip = Join-Path $PayloadDir $V.node_file
if (-not (Test-Path $NodeZip)) { Die "missing $($V.node_file)" }
$NodeTmp = Join-Path $InstallRoot '_node_tmp'
Expand-Archive -Path $NodeZip -DestinationPath $NodeTmp -Force
$NodeInner = Get-ChildItem $NodeTmp -Directory | Select-Object -First 1
$NodeDir = Join-Path $InstallRoot 'node'
if (Test-Path $NodeDir) { Remove-Item $NodeDir -Recurse -Force }
Move-Item $NodeInner.FullName $NodeDir
Remove-Item $NodeTmp -Recurse -Force
Write-Ok "node → $NodeDir\node.exe"

# Configure npm to keep global installs inside the portable tree
$NpmGlobal = Join-Path $InstallRoot 'npm-global'
$NpmCache  = Join-Path $InstallRoot 'npm-cache'
New-Item -ItemType Directory -Path $NpmGlobal,$NpmCache -Force | Out-Null
$Npmrc = Join-Path $env:USERPROFILE '.npmrc'
$NpmrcLines = @(
  "prefix=$NpmGlobal",
  "cache=$NpmCache"
)
Set-Content -Path $Npmrc -Value $NpmrcLines -Encoding ASCII
Write-Ok "npm prefix → $NpmGlobal"

# ---------- 3. Python embeddable + pip ----------
Write-Step "Installing Python $($V.python) (embeddable + pip)"
$PyZip = Join-Path $PayloadDir $V.python_file
if (-not (Test-Path $PyZip)) { Die "missing $($V.python_file)" }
$PyDir = Join-Path $InstallRoot 'python'
if (Test-Path $PyDir) { Remove-Item $PyDir -Recurse -Force }
Expand-Archive -Path $PyZip -DestinationPath $PyDir -Force

# Enable site-packages so pip works
$PthFile = Get-ChildItem $PyDir -Filter 'python*._pth' | Select-Object -First 1
if ($PthFile) {
  $pthContent = Get-Content $PthFile.FullName
  $pthContent = $pthContent -replace '^#\s*import site', 'import site'
  if (-not ($pthContent -match '^import site')) { $pthContent += 'import site' }
  Set-Content -Path $PthFile.FullName -Value $pthContent -Encoding ASCII
}

$PyExe = Join-Path $PyDir 'python.exe'
$GetPip = Join-Path $PayloadDir 'get-pip.py'
& $PyExe $GetPip --no-warn-script-location | Out-Null
if (-not (Test-Path (Join-Path $PyDir 'Scripts\pip.exe'))) { Die "pip bootstrap failed" }
Write-Ok "python → $PyExe"
Write-Ok "pip    → $(Join-Path $PyDir 'Scripts\pip.exe')"

# ---------- 4. AWS CLI v2 (per-user MSI install, no admin) ----------
Write-Step "Installing AWS CLI v2 (per-user)"
$AwsMsi = Join-Path $PayloadDir 'AWSCLIV2.msi'
$AwsDir = Join-Path $InstallRoot 'aws'
if (-not (Test-Path $AwsMsi)) { Die "missing AWSCLIV2.msi" }
if (Test-Path $AwsDir) { Remove-Item $AwsDir -Recurse -Force }
New-Item -ItemType Directory -Path $AwsDir -Force | Out-Null

# msiexec per-user: ALLUSERS=2 + MSIINSTALLPERUSER=1 → no UAC
$msiLog = Join-Path $InstallRoot 'aws-msi.log'
$msiArgs = @(
  '/i', "`"$AwsMsi`"",
  '/qn',
  'ALLUSERS=2',
  'MSIINSTALLPERUSER=1',
  "INSTALLDIR=`"$AwsDir`"",
  "/log", "`"$msiLog`""
)
$p = Start-Process 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
if ($p.ExitCode -ne 0) {
  Write-Warn "msiexec exit $($p.ExitCode). Falling back to pip install awscli (v1)."
  & $PyExe -m pip install --quiet --upgrade awscli
  $AwsCliPath = Join-Path $PyDir 'Scripts'
} else {
  $AwsCliPath = $AwsDir
}
Write-Ok "aws → $AwsCliPath"

# ---------- 5. Claude Code ----------
Write-Step "Installing Claude Code $($V.claude_code)"
$NpmCmd = Join-Path $NodeDir 'npm.cmd'
$ClaudeTgz = Get-ChildItem $PayloadDir -Filter 'anthropic-ai-claude-code-*.tgz' | Select-Object -First 1
if ($ClaudeTgz) {
  Write-Ok "using staged tarball: $($ClaudeTgz.Name)"
  & $NpmCmd install -g $ClaudeTgz.FullName 2>&1 | Out-Null
} else {
  Write-Ok "installing from npm registry"
  & $NpmCmd install -g "@anthropic-ai/claude-code@$($V.claude_code)" 2>&1 | Out-Null
}
$ClaudeExe = Join-Path $NpmGlobal 'claude.cmd'
if (-not (Test-Path $ClaudeExe)) {
  $ClaudeExe = Join-Path $NpmGlobal 'claude-code.cmd'
}
if (-not (Test-Path $ClaudeExe)) { Die "claude-code install failed" }
Write-Ok "claude → $ClaudeExe"

# ---------- 6. PATH ----------
if (-not $NoPathUpdate) {
  Write-Step "Updating user PATH"
  Add-UserPath (Join-Path $GitDir 'cmd')
  Add-UserPath $NodeDir
  Add-UserPath $NpmGlobal
  Add-UserPath $PyDir
  Add-UserPath (Join-Path $PyDir 'Scripts')
  Add-UserPath $AwsCliPath
  Write-Ok "PATH updated (User scope). Open a new terminal to pick it up."
} else {
  Write-Warn "Skipped PATH update (-NoPathUpdate). Use activate.ps1 for session-only PATH."
}

# ---------- summary ----------
Write-Step "Install complete"
Write-Ok ("Git          : " + (& (Join-Path $GitDir 'cmd\git.exe') --version))
Write-Ok ("Node.js      : " + (& (Join-Path $NodeDir 'node.exe') --version))
Write-Ok ("npm          : " + (& $NpmCmd --version))
Write-Ok ("Python       : " + (& $PyExe --version))
try   { Write-Ok ("AWS CLI      : " + (& (Join-Path $AwsCliPath 'aws.exe') --version)) }
catch { Write-Warn "AWS CLI not on PATH yet — open new terminal" }
try   { Write-Ok ("Claude Code  : " + (& $ClaudeExe --version)) }
catch { Write-Warn "Claude Code not on PATH yet — open new terminal" }

Write-Host ""
Write-Host "Open a NEW PowerShell/cmd window to use the tools." -ForegroundColor Cyan
Write-Host "Or run:  . .\activate.ps1   (session-only)"          -ForegroundColor Cyan
