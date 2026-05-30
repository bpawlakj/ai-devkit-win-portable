<#
Session-only activator for ai-devkit.
Prepends the portable tools to $env:Path for the CURRENT PowerShell session.
No registry write, no admin needed.

Usage:
  . .\activate.ps1
  . .\activate.ps1 -InstallRoot 'D:\portable\ai-devkit'
#>

param(
  [string]$InstallRoot = (Join-Path $env:USERPROFILE 'ai-devkit')
)

if (-not (Test-Path $InstallRoot)) {
  Write-Host "ai-devkit not found at $InstallRoot" -ForegroundColor Red
  Write-Host "Run install.ps1 first." -ForegroundColor Red
  return
}

$dirs = @(
  (Join-Path $InstallRoot 'git\cmd'),
  (Join-Path $InstallRoot 'node'),
  (Join-Path $InstallRoot 'npm-global'),
  (Join-Path $InstallRoot 'python'),
  (Join-Path $InstallRoot 'python\Scripts'),
  (Join-Path $InstallRoot 'aws'),
  # AWS CLI v2's per-user MSI ignores INSTALLDIR and lands here instead.
  (Join-Path $env:LOCALAPPDATA 'Programs\Amazon\AWSCLIV2'),
  # Claude Code is installed by its official installer to %USERPROFILE%\.local\bin.
  (Join-Path $env:USERPROFILE '.local\bin')
) | Where-Object { Test-Path $_ }

$prefix = ($dirs -join ';')
$env:Path = "$prefix;$env:Path"

Write-Host "ai-devkit activated for this session." -ForegroundColor Green
Write-Host "Tools available: git, node, npm, python, aws, claude" -ForegroundColor Green
