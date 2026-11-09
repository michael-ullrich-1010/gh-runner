#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Meldet alle Runner unter $Root bei GitHub ab und entfernt die Services.
#>
param([string]$Root = "C:\runners")
$ErrorActionPreference = "Stop"

function Invoke-Native([scriptblock]$Cmd) {
  $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { (& $Cmd 2>&1 | ForEach-Object { "$_" }) -join "`n" } finally { $ErrorActionPreference = $old }
}

Get-ChildItem $Root -Directory -Exclude _cache | ForEach-Object {
  $org = $_.Name -replace '-\d+$',''
  $t = Invoke-Native { gh api -X POST "orgs/$org/actions/runners/remove-token" --jq .token }
  if ($LASTEXITCODE -ne 0) { throw "Kein Remove-Token für '$org': $t" }
  Push-Location $_.FullName
  .\config.cmd remove --token $t
  $rc = $LASTEXITCODE
  Pop-Location
  if ($rc -ne 0) { throw "config.cmd remove für $($_.Name) fehlgeschlagen (Exit-Code $rc)" }
  Write-Host "Entfernt: $($_.Name)"
}
