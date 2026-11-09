#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Meldet alle Runner unter $Root bei GitHub ab und entfernt die Services.
#>
param([string]$Root = "C:\runners")
$ErrorActionPreference = "Stop"

Get-ChildItem $Root -Directory -Exclude _cache | ForEach-Object {
  $org = $_.Name -replace '-\d+$',''
  $t = gh api -X POST "orgs/$org/actions/runners/remove-token" --jq .token
  Push-Location $_.FullName
  .\config.cmd remove --token $t
  Pop-Location
  Write-Host "Entfernt: $($_.Name)"
}
