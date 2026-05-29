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
  (Join-Path $InstallRoot 'aws')
)

Write-Host "Removing PATH entries..." -ForegroundColor Cyan
Remove-FromUserPath $toRemove

if (Test-Path $InstallRoot) {
  Write-Host "Deleting $InstallRoot ..." -ForegroundColor Cyan
  Remove-Item $InstallRoot -Recurse -Force
}

$npmrc = Join-Path $env:USERPROFILE '.npmrc'
if (Test-Path $npmrc) {
  Write-Host "Note: $npmrc was left in place. Edit/remove manually if needed." -ForegroundColor Yellow
}

Write-Host "Uninstall complete. Open a new terminal." -ForegroundColor Green
