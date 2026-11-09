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

# Externe Programme aufrufen, ohne dass stderr-Ausgaben in Windows PowerShell 5.1
# das Skript abbrechen. Liefert die Ausgabe als Text, Exit-Code in $LASTEXITCODE.
function Invoke-Native([scriptblock]$Cmd) {
  $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { (& $Cmd 2>&1 | ForEach-Object { "$_" }) -join "`n" } finally { $ErrorActionPreference = $old }
}
# Dienstkonto sprachneutral setzen und Service starten. Hintergrund: Auf deutschem
# Windows trägt config.cmd "NT-AUTORITÄT\Netzwerkdienst" ein und der Start scheitert
# mit Fehler 1068. "NT AUTHORITY\NetworkService" funktioniert in jeder Sprache.
function Start-RunnerService([string]$Dir) {
  $svcFile = Join-Path $Dir ".service"
  if (-not (Test-Path $svcFile)) { throw "In $Dir ist kein Service installiert" }
  $svcName = (Get-Content $svcFile -Raw).Trim()
  $s = Get-CimInstance Win32_Service -Filter "Name='$svcName'"
  if (-not $s) { throw "Service $svcName nicht gefunden" }
  $rv = ($s | Invoke-CimMethod -MethodName Change -Arguments @{
          StartName = 'NT AUTHORITY\NetworkService'; StartPassword = '' }).ReturnValue
  if ($rv -ne 0) { throw "Dienstkonto für $svcName nicht änderbar (Code $rv)" }
  if ((Get-Service $svcName).Status -ne 'Running') { Start-Service $svcName }
  Write-Host "Läuft: $svcName"
}
function Assert-Ok([string]$What) {
  if ($LASTEXITCODE -ne 0) { throw "$What fehlgeschlagen (Exit-Code $LASTEXITCODE)" }
}

# 1) Werkzeuge
winget install --id GitHub.cli -e --silent --accept-source-agreements --accept-package-agreements
winget install --id Git.Git    -e --silent --accept-source-agreements --accept-package-agreements
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path","User")
git config --system core.longpaths true

# 2) Einziger Login (Browser), Scope admin:org für Runner-Registrierung
$st = Invoke-Native { gh auth status }
if ($LASTEXITCODE -ne 0 -or $st -notmatch "Logged in") {
  gh auth login --hostname github.com --git-protocol https --web --scopes admin:org; Assert-Ok "gh auth login"
} elseif ($st -notmatch "admin:org") {
  gh auth refresh --hostname github.com --scopes admin:org; Assert-Ok "gh auth refresh"
}

# 3) Aktuellen Runner holen
$cache = Join-Path $Root "_cache"
New-Item -ItemType Directory -Force $cache | Out-Null
$out = Invoke-Native { gh release download -R actions/runner -p "actions-runner-win-x64-*.zip" -D $cache --skip-existing }
if ($LASTEXITCODE -ne 0) { throw "Runner-Download fehlgeschlagen: $out" }
$zip = Get-ChildItem $cache -Filter "actions-runner-win-x64-*.zip" |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1

# 4) Pro Org registrieren und als Service installieren
foreach ($org in $Orgs) {
  $token = Invoke-Native { gh api -X POST "orgs/$org/actions/runners/registration-token" --jq .token }
  if ($LASTEXITCODE -ne 0) { throw "Kein Registrierungs-Token für '$org' (Org-Owner? Scope admin:org?): $token" }
  for ($i = 1; $i -le $Count; $i++) {
    $name = "$env:COMPUTERNAME-$org-$i".ToLower()
    $dir  = Join-Path $Root "$org-$i"
    if (Test-Path "$dir\.runner") {
      Write-Host "$name ist schon registriert"
      Start-RunnerService $dir
      continue
    }

    New-Item -ItemType Directory -Force $dir | Out-Null
    Expand-Archive $zip.FullName -DestinationPath $dir -Force
    Push-Location $dir
    .\config.cmd --unattended --url "https://github.com/$org" --token $token `
      --name $name --labels "$Labels,$($env:COMPUTERNAME.ToLower())" `
      --work _work --runasservice --replace
    $rc = $LASTEXITCODE
    Pop-Location
    # config.cmd meldet Exit-Code 1, wenn nur der Service-Start scheitert (deutsches
    # Windows). Entscheidend ist, ob Registrierung und Service angelegt wurden.
    if (-not (Test-Path "$dir\.service")) { throw "config.cmd für $name fehlgeschlagen (Exit-Code $rc)" }
    if ($rc -ne 0) { Write-Host "Service-Start durch config.cmd fehlgeschlagen, korrigiere Dienstkonto ..." }
    Start-RunnerService $dir
    Write-Host "OK: $name"
  }
}
