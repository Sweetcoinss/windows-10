#Requires -Version 5.1
<#
.SYNOPSIS
  Registers a Windows 10 machine as a self-hosted GitHub Actions runner for Sweetcoinss/windows-10.

.DESCRIPTION
  Downloads the official actions/runner, configures it with the label "windows-10",
  installs it as a Windows service and starts it.
  Must be run as Administrator.

.PARAMETER RegistrationToken
  A runner registration token. Registration tokens expire after 1 hour.
  Get a fresh one with:
    gh api -X POST repos/Sweetcoinss/windows-10/actions/runners/registration-token --jq .token

.EXAMPLE
  .\register-runner.ps1 -RegistrationToken "ABCDEF..."

.EXAMPLE
  # one-liner (download + run), from an elevated PowerShell:
  iwr https://raw.githubusercontent.com/Sweetcoinss/windows-10/main/register-runner.ps1 -OutFile $env:TEMP\register-runner.ps1
  & $env:TEMP\register-runner.ps1 -RegistrationToken "ABCDEF..."
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $RegistrationToken,

  [string] $RunnerVersion = "2.338.0",
  [string] $RunnerDir     = "C:\actions-runner",
  [string] $Labels        = "windows-10",
  [string] $RepoUrl       = "https://github.com/Sweetcoinss/windows-10"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-Administrator {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
  Write-Error "Run this script as Administrator (right-click PowerShell -> Run as administrator)."
  exit 1
}

# ---------------------------------------------------------------- checks ---
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "OS: $($os.Caption) $($os.Version) ($($os.OSArchitecture))" -ForegroundColor Cyan

if ($os.OSArchitecture -ne "64-bit") {
  Write-Error "A 64-bit OS is required."
  exit 1
}
if ($os.ProductType -ne 1) {
  Write-Warning "This looks like Windows Server, not Windows 10."
}
if ($os.Caption -notmatch "Windows 10") {
  Write-Warning "This machine is not Windows 10, but the workflow requests the 'windows-10' label."
}

$edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
              -Name EditionID -ErrorAction SilentlyContinue).EditionID
if ($edition -match '^(Core|CoreSingleLanguage|CoreCountrySpecific)') {
  Write-Warning "Windows 10 Home cannot host Remote Desktop (RDP). Use Pro or Enterprise."
}

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
  Write-Host "Node.js: $(& node --version)"
} else {
  Write-Warning "Node.js not found. Install Node.js 18+ first, e.g.: winget install OpenJS.NodeJS.LTS"
}

# -------------------------------------------------------------- download ---
New-Item -ItemType Directory -Path $RunnerDir -Force | Out-Null
Set-Location $RunnerDir

$RunnerVersion = $RunnerVersion.TrimStart("v")
$zip = Join-Path $env:TEMP "actions-runner-win-x64-$RunnerVersion.zip"
$url = "https://github.com/actions/runner/releases/download/v$RunnerVersion/actions-runner-win-x64-$RunnerVersion.zip"

Write-Host "Downloading $url" -ForegroundColor Cyan
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $RunnerDir -Force
Remove-Item $zip -Force

# ------------------------------------------------------------- configure ---
Write-Host "Configuring runner (labels: $Labels)" -ForegroundColor Cyan
$configArgs = @(
  "--url",    $RepoUrl,
  "--token",  $RegistrationToken,
  "--labels", $Labels,
  "--name",   $env:COMPUTERNAME,
  "--work",   "_work",
  "--unattended",
  "--replace"
)
& "$RunnerDir\config.cmd" @configArgs
if ($LASTEXITCODE -ne 0) { Write-Error "config.cmd failed with exit code $LASTEXITCODE"; exit 1 }

# --------------------------------------------------------------- service ---
Write-Host "Installing the runner as a Windows service" -ForegroundColor Cyan
& "$RunnerDir\svc.cmd" install
if ($LASTEXITCODE -ne 0) { Write-Error "svc.cmd install failed with exit code $LASTEXITCODE"; exit 1 }
& "$RunnerDir\svc.cmd" start

Start-Sleep -Seconds 5
Write-Host ""
Write-Host "Runner service status:" -ForegroundColor Green
& "$RunnerDir\svc.cmd" status
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1) Verify the runner online: $RepoUrl/settings/actions/runners"
Write-Host "  2) Trigger the workflow:      gh workflow run my-custom-rdp.yml --repo Sweetcoinss/windows-10"
