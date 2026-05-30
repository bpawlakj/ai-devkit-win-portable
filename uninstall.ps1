<#
Removes ai-devkit portable install and cleans user PATH entries.
No admin needed (user-scope only).
#>

param(
  [string]$InstallRoot = (Join-Path $env:USERPROFILE 'ai-devkit')
)

$ErrorActionPreference = 'Stop'

function Remove-FromUserPath([string[]]$dirs) {
  $current = [Environment]::GetEnvironmentVariable('Path','User')
  if (-not $current) { return }
  $parts = $current -split ';' | Where-Object { $_ -and ($dirs -notcontains $_) }
  [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}

$toRemove = @(
  (Join-Path $InstallRoot 'git\cmd'),
  (Join-Path $InstallRoot 'node'),
  (Join-Path $InstallRoot 'npm-global'),
  (Join-Path $InstallRoot 'python'),
  (Join-Path $InstallRoot 'python\Scripts'),
  (Join-Path $InstallRoot 'aws'),
  # AWS CLI v2's per-user MSI installs here (it ignores INSTALLDIR).
  (Join-Path $env:LOCALAPPDATA 'Programs\Amazon\AWSCLIV2')
)

Write-Host "Removing PATH entries..." -ForegroundColor Cyan
Remove-FromUserPath $toRemove

if (Test-Path $InstallRoot) {
  Write-Host "Deleting $InstallRoot ..." -ForegroundColor Cyan
  Remove-Item $InstallRoot -Recurse -Force
}

$awsMsiDir = Join-Path $env:LOCALAPPDATA 'Programs\Amazon\AWSCLIV2'
if (Test-Path $awsMsiDir) {
  Write-Host "Note: AWS CLI v2 was installed by its per-user MSI at $awsMsiDir." -ForegroundColor Yellow
  Write-Host "      Its PATH entry was removed; uninstall the app itself via Settings > Apps if desired." -ForegroundColor Yellow
}

$npmrc = Join-Path $env:USERPROFILE '.npmrc'
if (Test-Path $npmrc) {
  Write-Host "Note: $npmrc was left in place. Edit/remove manually if needed." -ForegroundColor Yellow
}

# Claude Code is installed by its own official installer into %USERPROFILE%\.local\bin
# (it also manages its PATH entry), so we don't delete it here. Point the user at
# the supported removal path instead of clobbering a possibly-separate install.
$claudeBin = Join-Path $env:USERPROFILE '.local\bin'
if (Test-Path (Join-Path $claudeBin 'claude.exe')) {
  Write-Host "Note: Claude Code was installed by its official installer to $claudeBin." -ForegroundColor Yellow
  Write-Host "      To remove it, run:  claude uninstall   (then delete $claudeBin if empty)." -ForegroundColor Yellow
}

Write-Host "Uninstall complete. Open a new terminal." -ForegroundColor Green
