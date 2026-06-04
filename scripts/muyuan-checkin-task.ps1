$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "logs"
$logFile = Join-Path $logDir "muyuan-checkin.log"
$scriptPath = Join-Path $PSScriptRoot "muyuan-checkin.js"
$configPath = Join-Path $repoRoot "config\muyuan-accounts.json"

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

function Get-EnvValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  if (Get-Item "Env:$Name" -ErrorAction SilentlyContinue) {
    return (Get-Item "Env:$Name").Value
  }

  return [Environment]::GetEnvironmentVariable($Name, "User")
}

function Get-AccountConfig {
  if (-not (Test-Path $configPath)) {
    return $null
  }

  $raw = Get-Content $configPath -Raw -Encoding utf8
  if ([string]::IsNullOrWhiteSpace($raw)) {
    throw "Config file is empty: $configPath"
  }

  return $raw | ConvertFrom-Json
}

function Get-Accounts {
  $config = Get-AccountConfig
  if ($null -ne $config) {
    $accounts = @()
    foreach ($account in $config.accounts) {
      $enabled = $true
      if ($null -ne $account.enabled) {
        $enabled = [bool]$account.enabled
      }

      if (-not $enabled) {
        continue
      }

      $name = [string]$account.name
      if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "unnamed-account"
      }

      $userId = [string]$account.user_id
      $accessToken = [string]$account.access_token

      if ([string]::IsNullOrWhiteSpace($userId) -or [string]::IsNullOrWhiteSpace($accessToken)) {
        throw "Account [$name] is missing user_id or access_token in $configPath"
      }

      $accounts += [pscustomobject]@{
        Name        = $name
        UserId      = $userId
        AccessToken = $accessToken
      }
    }

    if ($accounts.Count -eq 0) {
      throw "No enabled accounts found in $configPath"
    }

    $delayMin = 5
    $delayMax = 12
    if ($null -ne $config.delay_seconds_min) {
      $delayMin = [int]$config.delay_seconds_min
    }
    if ($null -ne $config.delay_seconds_max) {
      $delayMax = [int]$config.delay_seconds_max
    }
    if ($delayMin -lt 0) { $delayMin = 0 }
    if ($delayMax -lt $delayMin) { $delayMax = $delayMin }

    return [pscustomobject]@{
      Accounts = $accounts
      DelayMin = $delayMin
      DelayMax = $delayMax
      Source   = $configPath
    }
  }

  $accessToken = Get-EnvValue -Name "MUYUAN_ACCESS_TOKEN"
  $userId = Get-EnvValue -Name "MUYUAN_USER_ID"

  if ([string]::IsNullOrWhiteSpace($accessToken)) {
    throw "Missing MUYUAN_ACCESS_TOKEN."
  }

  if ([string]::IsNullOrWhiteSpace($userId)) {
    throw "Missing MUYUAN_USER_ID."
  }

  return [pscustomobject]@{
    Accounts = @(
      [pscustomobject]@{
        Name        = "env-account-1"
        UserId      = $userId
        AccessToken = $accessToken
      }
    )
    DelayMin = 0
    DelayMax = 0
    Source   = "environment variables"
  }
}

function Invoke-CheckinForAccount {
  param(
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Account
  )

  $env:MUYUAN_ACCESS_TOKEN = $Account.AccessToken
  $env:MUYUAN_USER_ID = $Account.UserId

  Write-Log "Starting account [$($Account.Name)] user_id=$($Account.UserId)."
  $output = & $nodePath $scriptPath 2>&1 | ForEach-Object { $_.ToString() }
  $exitCode = $LASTEXITCODE

  if ($output) {
    foreach ($line in $output) {
      Write-Log "[$($Account.Name)] $line"
    }
  }

  Write-Log "Finished account [$($Account.Name)] with exit code $exitCode."
  return $exitCode
}

$nodePath = (Get-Command node -ErrorAction Stop).Source
$originalAccessToken = $env:MUYUAN_ACCESS_TOKEN
$originalUserId = $env:MUYUAN_USER_ID

Write-Log "Starting MUYUAN check-in task."
$overallExitCode = 0

try {
  $accountConfig = Get-Accounts
  $accounts = @($accountConfig.Accounts)
  Write-Log "Loaded $($accounts.Count) account(s) from $($accountConfig.Source)."

  for ($index = 0; $index -lt $accounts.Count; $index++) {
    $account = $accounts[$index]
    $exitCode = Invoke-CheckinForAccount -Account $account
    if ($exitCode -ne 0) {
      $overallExitCode = 1
    }

    $isLast = $index -eq ($accounts.Count - 1)
    if (-not $isLast -and $accountConfig.DelayMax -gt 0) {
      $delay = Get-Random -Minimum $accountConfig.DelayMin -Maximum ($accountConfig.DelayMax + 1)
      Write-Log "Waiting $delay second(s) before next account."
      Start-Sleep -Seconds $delay
    }
  }
}
catch {
  Write-Log $_.Exception.Message
  $overallExitCode = 1
}
finally {
  $env:MUYUAN_ACCESS_TOKEN = $originalAccessToken
  $env:MUYUAN_USER_ID = $originalUserId
}

Write-Log "MUYUAN check-in task finished with exit code $overallExitCode."
exit $overallExitCode
