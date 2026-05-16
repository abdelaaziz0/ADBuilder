[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)] [string] $ConfigPath,
    [switch] $Resume,
    [switch] $DryRun,
    [switch] $IgnoreDrift,
    [string] $StatePath,
    [switch] $Force,
    [switch] $LabUnsafe,
    [switch] $NonInteractive,
    [switch] $AllowReducedValidation
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
    throw 'ADBuilder apply engine supports Windows PowerShell 5.1 only. Run from Windows PowerShell, not PowerShell 7.'
}

$moduleManifest = Join-Path $PSScriptRoot 'ADBuilder.psd1'
Import-Module $moduleManifest -Force

Invoke-ADBuilder -ConfigPath $ConfigPath -Resume:$Resume -DryRun:$DryRun -IgnoreDrift:$IgnoreDrift -StatePath $StatePath -Force:$Force -LabUnsafe:$LabUnsafe -NonInteractive:$NonInteractive -AllowReducedValidation:$AllowReducedValidation -WhatIf:$WhatIfPreference
