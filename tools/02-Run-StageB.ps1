[CmdletBinding()]
param(
    [string]$ConfigPath = '.\examples\reference.json',
    [switch]$IgnoreDrift,
    [switch]$NoReducedValidation
)
$ErrorActionPreference='Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
if (-not $env:ADBUILDER_DSRM_PASSWORD) { $env:ADBUILDER_DSRM_PASSWORD=[Environment]::GetEnvironmentVariable('ADBUILDER_DSRM_PASSWORD','Machine') }
if (-not $env:ADBUILDER_DEFAULT_USER_PASSWORD) { $env:ADBUILDER_DEFAULT_USER_PASSWORD=[Environment]::GetEnvironmentVariable('ADBUILDER_DEFAULT_USER_PASSWORD','Machine') }
$splat = @{ ConfigPath = $ConfigPath; Resume = $true; NonInteractive = $true }
if ($IgnoreDrift) { $splat.IgnoreDrift = $true }
if (-not $NoReducedValidation) { $splat.UnsafeReducedValidation = $true }
& .\Build-ADDomain.ps1 @splat
