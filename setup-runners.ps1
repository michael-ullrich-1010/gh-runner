#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Richtet GitHub Actions self-hosted Runner (Windows, als Service) für eine oder mehrere Orgs ein.
.EXAMPLE
  .\setup-runners.ps1 -Orgs my-org -Count 2
.EXAMPLE
  .\setup-runners.ps1 -Orgs org-a,org-b -Labels gpu,z8
#>
param(
  [Parameter(Mandatory)][string[]]$Orgs,   # z.B. -Orgs org-a,org-b
  [int]$Count = 1,                          # Runner pro Org = parallele Jobs
  [string]$Labels = "local",                # zusätzliche Labels (Komma-getrennt)
  [string]$Root = "C:\runners"
)
$ErrorActionPreference = "Stop"

# 1) Werkzeuge
winget install --id GitHub.cli -e --silent --accept-source-agreements --accept-package-agreements
winget install --id Git.Git    -e --silent --accept-source-agreements --accept-package-agreements
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path","User")
git config --system core.longpaths true

# 2) Einziger Login (Browser), Scope admin:org für Runner-Registrierung
$st = gh auth status 2>&1 | Out-String
if ($st -notmatch "Logged in")     { gh auth login --web --scopes admin:org }
elseif ($st -notmatch "admin:org") { gh auth refresh --scopes admin:org }

# 3) Aktuellen Runner holen
$cache = Join-Path $Root "_cache"
New-Item -ItemType Directory -Force $cache | Out-Null
gh release download -R actions/runner -p "actions-runner-win-x64-*.zip" -D $cache --skip-existing
$zip = Get-ChildItem $cache -Filter "actions-runner-win-x64-*.zip" |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1

# 4) Pro Org registrieren und als Service installieren
foreach ($org in $Orgs) {
  $token = gh api -X POST "orgs/$org/actions/runners/registration-token" --jq .token
  for ($i = 1; $i -le $Count; $i++) {
    $name = "$env:COMPUTERNAME-$org-$i".ToLower()
    $dir  = Join-Path $Root "$org-$i"
    if (Test-Path "$dir\.runner") { Write-Host "$name existiert, übersprungen"; continue }

    New-Item -ItemType Directory -Force $dir | Out-Null
    Expand-Archive $zip.FullName -DestinationPath $dir -Force
    Push-Location $dir
    .\config.cmd --unattended --url "https://github.com/$org" --token $token `
      --name $name --labels "$Labels,$($env:COMPUTERNAME.ToLower())" `
      --work _work --runasservice --replace
    Pop-Location
    Write-Host "OK: $name"
  }
}
