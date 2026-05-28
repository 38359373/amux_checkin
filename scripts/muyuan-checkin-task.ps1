$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "logs"
$logFile = Join-Path $logDir "muyuan-checkin.log"
$scriptPath = Join-Path $PSScriptRoot "muyuan-checkin.js"

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
if (-not (Test-Path $logFile)) {
  "" | Out-File -FilePath $logFile -Encoding utf8
}

function Write-Log {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[$timestamp] $Message"
  $line | Out-File -FilePath $logFile -Append -Encoding utf8
  Write-Host $line
}

if (-not $env:MUYUAN_ACCESS_TOKEN) {
  $env:MUYUAN_ACCESS_TOKEN = [Environment]::GetEnvironmentVariable("MUYUAN_ACCESS_TOKEN", "User")
}

if (-not $env:MUYUAN_USER_ID) {
  $env:MUYUAN_USER_ID = [Environment]::GetEnvironmentVariable("MUYUAN_USER_ID", "User")
}

if ([string]::IsNullOrWhiteSpace($env:MUYUAN_ACCESS_TOKEN)) {
  Write-Log "Missing MUYUAN_ACCESS_TOKEN."
  exit 1
}

if ([string]::IsNullOrWhiteSpace($env:MUYUAN_USER_ID)) {
  Write-Log "Missing MUYUAN_USER_ID."
  exit 1
}

$nodePath = (Get-Command node -ErrorAction Stop).Source

Write-Log "Starting MUYUAN check-in task."
$output = & $nodePath $scriptPath 2>&1 | ForEach-Object { $_.ToString() }
$exitCode = $LASTEXITCODE

if ($output) {
  foreach ($line in $output) {
    Write-Log $line
  }
}

Write-Log "MUYUAN check-in task finished with exit code $exitCode."
exit $exitCode
