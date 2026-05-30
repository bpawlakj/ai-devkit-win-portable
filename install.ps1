#requires -version 5.1
<#
ai-devkit portable installer for Windows.
Runs entirely in user-mode: no admin, no UAC, no MSI elevation.
Installs Git, Node.js, npm, Python, AWS CLI into %USERPROFILE%\ai-devkit and
adds each tool to the user PATH. Claude Code is installed FIRST by delegating
to install-claude.ps1 (official installer -> %USERPROFILE%\.local\bin).

Tool binaries are downloaded from upstream at install time (an internet
connection is required). URLs are read from versions.json. If a matching
file already exists in .\payload it is reused instead of re-downloaded,
so a maintainer can pre-stage .\payload (./build.sh --prefetch) for a
fully offline install.

Usage:
  powershell -ExecutionPolicy Bypass -File .\install.ps1               # everything (Claude first)
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipClaude   # everything except Claude
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Claude       # Claude Code only
  powershell -ExecutionPolicy Bypass -File .\install-claude.ps1        # Claude Code only (standalone)
#>

[CmdletBinding()]
param(
  [string]$InstallRoot = (Join-Path $env:USERPROFILE 'ai-devkit'),
  [switch]$NoPathUpdate,
  [switch]$Force,
  # Install ONLY Claude Code (delegates to install-claude.ps1), then exit.
  [switch]$Claude,
  # Install everything EXCEPT Claude Code.
  [switch]$SkipClaude
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

if ($Claude -and $SkipClaude) {
  Write-Host "FAIL: -Claude and -SkipClaude are mutually exclusive." -ForegroundColor Red
  exit 1
}

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

$ClaudeBin = Join-Path $env:USERPROFILE '.local\bin'

# ---------- 1. Claude Code (delegated to install-claude.ps1) - installed FIRST ----------
# Claude Code is a self-contained native binary with NO dependency on Git/Node/
# Python/AWS, so it goes first - usable even if a later step fails. The actual
# work lives in install-claude.ps1 (which can also be run standalone); we invoke
# it as a child process so its exit codes don't abort this script unexpectedly.
# Skipped entirely with -SkipClaude; with -Claude we install only Claude and stop.
if (-not $SkipClaude) {
  $ClaudeScript = Join-Path $ScriptDir 'install-claude.ps1'
  if (-not (Test-Path $ClaudeScript)) { Die "install-claude.ps1 not found next to install.ps1" }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ClaudeScript
  if ($LASTEXITCODE -ne 0) { Die "Claude Code install failed (see output above)" }
  if ($Claude) {
    Write-Step "Done - installed Claude Code only (-Claude)."
    exit 0
  }
} else {
  Write-Step "Skipping Claude Code (-SkipClaude)"
}

# ---------- 2. download binaries (skips any already in payload\) ----------
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

# ---------- 3. PortableGit ----------
Write-Step "Installing Git $($V.git)"
$GitDir = Join-Path $InstallRoot 'git'
$GitExe = Join-Path $PayloadDir $V.git_file
if (-not (Test-Path $GitExe)) { Die "missing $($V.git_file)" }
New-Item -ItemType Directory -Path $GitDir -Force | Out-Null
# 7-Zip self-extractor: -y = assume yes, -o"<dir>" = output dir.
# Must run via Start-Process -Wait: the SFX is a GUI-subsystem exe that detaches
# from `&`, so the script would race ahead and see an empty dir. (The old
# `& $GitExe -y -gm2 "-o$GitDir"` failed for exactly this reason - and -gm2 is
# not a valid SFX switch.)
$p = Start-Process -FilePath $GitExe -ArgumentList '-y', "-o`"$GitDir`"" -Wait -PassThru
if ($p.ExitCode -ne 0 -or -not (Test-Path (Join-Path $GitDir 'cmd\git.exe'))) {
  Die "git extraction failed (SFX exit $($p.ExitCode))"
}
Write-Ok "git -> $GitDir\cmd\git.exe"

# ---------- 4. Node.js + npm ----------
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
$NpmCmd = Join-Path $NodeDir 'npm.cmd'
Write-Ok "node -> $NodeDir\node.exe"

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
Write-Ok "npm prefix -> $NpmGlobal"

# ---------- 5. Python embeddable + pip ----------
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
Write-Ok "python -> $PyExe"
Write-Ok "pip    -> $(Join-Path $PyDir 'Scripts\pip.exe')"

# ---------- 6. AWS CLI v2 (per-user MSI install, no admin) ----------
Write-Step "Installing AWS CLI v2 (per-user)"
$AwsMsi = Join-Path $PayloadDir 'AWSCLIV2.msi'
$AwsDir = Join-Path $InstallRoot 'aws'
if (-not (Test-Path $AwsMsi)) { Die "missing AWSCLIV2.msi" }
if (Test-Path $AwsDir) { Remove-Item $AwsDir -Recurse -Force }
New-Item -ItemType Directory -Path $AwsDir -Force | Out-Null

# msiexec per-user: ALLUSERS=2 + MSIINSTALLPERUSER=1 -> no UAC
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
  # The AWS CLI v2 MSI IGNORES INSTALLDIR for per-user installs - it always
  # lands in %LOCALAPPDATA%\Programs\Amazon\AWSCLIV2. Resolve the real dir
  # (checking our requested dir first in case AWS ever honors it).
  $AwsCliPath = @(
    $AwsDir,
    (Join-Path $env:LOCALAPPDATA 'Programs\Amazon\AWSCLIV2')
  ) | Where-Object { Test-Path (Join-Path $_ 'aws.exe') } | Select-Object -First 1
  if (-not $AwsCliPath) {
    Write-Warn "MSI reported success but aws.exe not found; falling back to pip install awscli (v1)."
    & $PyExe -m pip install --quiet --upgrade awscli
    $AwsCliPath = Join-Path $PyDir 'Scripts'
  }
}
Write-Ok "aws -> $AwsCliPath"

# ---------- 7. PATH ----------
if (-not $NoPathUpdate) {
  Write-Step "Updating user PATH"
  Add-UserPath (Join-Path $GitDir 'cmd')
  Add-UserPath $NodeDir
  Add-UserPath $NpmGlobal
  Add-UserPath $PyDir
  Add-UserPath (Join-Path $PyDir 'Scripts')
  Add-UserPath $AwsCliPath
  # Claude Code's own installer already added this; re-add idempotently so the
  # devkit's PATH set stays self-describing (Add-UserPath dedupes).
  Add-UserPath $ClaudeBin
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
catch { Write-Warn "AWS CLI not on PATH yet - open new terminal" }
$ClaudeExe = Join-Path $ClaudeBin 'claude.exe'
if (Test-Path $ClaudeExe) {
  try   { Write-Ok ("Claude Code  : " + (($null | & $ClaudeExe --version 2>$null) -join ' ')) }
  catch { Write-Warn "Claude Code not on PATH yet - open new terminal" }
} elseif ($SkipClaude) {
  Write-Warn "Claude Code  : skipped (-SkipClaude)"
}

Write-Host ""
Write-Host "Open a NEW PowerShell/cmd window to use the tools." -ForegroundColor Cyan
Write-Host "Or run:  . .\activate.ps1   (session-only)"          -ForegroundColor Cyan
