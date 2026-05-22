[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $ConfigPath,
    [switch] $Strict,
    [switch] $PrintResolvedPlan,
    [switch] $UnsafeReducedValidation,
    [switch] $AllowReducedValidation,
    [switch] $LabUnsafe,
    [switch] $NonInteractive,
    [switch] $Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$moduleManifest = Join-Path $PSScriptRoot 'ADBuilder.psd1'
Import-Module $moduleManifest -Force

$result = Test-ADBuilderConfig -ConfigPath $ConfigPath -Strict:$Strict -PrintResolvedPlan:$PrintResolvedPlan -UnsafeReducedValidation:$UnsafeReducedValidation -AllowReducedValidation:$AllowReducedValidation -LabUnsafe:$LabUnsafe -NonInteractive:$NonInteractive -Force:$Force
if (-not $result.Valid) { exit 1 }
exit 0
