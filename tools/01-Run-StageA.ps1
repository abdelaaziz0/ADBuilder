[CmdletBinding()]
param(
    [string]$ConfigPath = '.\examples\lab-newforest-m1.json',
    [switch]$ResetState,
    [switch]$SkipDryRun,
    [switch]$NoReducedValidation
)
$ErrorActionPreference='Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
if (-not $env:ADBUILDER_DSRM_PASSWORD) { $env:ADBUILDER_DSRM_PASSWORD=[Environment]::GetEnvironmentVariable('ADBUILDER_DSRM_PASSWORD','Machine') }
if (-not $env:ADBUILDER_DEFAULT_USER_PASSWORD) { $env:ADBUILDER_DEFAULT_USER_PASSWORD=[Environment]::GetEnvironmentVariable('ADBUILDER_DEFAULT_USER_PASSWORD','Machine') }
if (-not $env:ADBUILDER_DSRM_PASSWORD) { throw 'ADBUILDER_DSRM_PASSWORD is not set. Run tools\00-Prepare-ServerCore.ps1 first.' }
if (-not $env:ADBUILDER_DEFAULT_USER_PASSWORD) { throw 'ADBUILDER_DEFAULT_USER_PASSWORD is not set. Run tools\00-Prepare-ServerCore.ps1 first.' }
if ($ResetState -and (Test-Path .\state\current-run.json)) { Remove-Item .\state\current-run.json -Force }
$rv = @()
if (-not $NoReducedValidation) { $rv += '-AllowReducedValidation' }
Write-Host 'Validating config...' -ForegroundColor Cyan
& .\Validate-ADBuilderConfig.ps1 -ConfigPath $ConfigPath @rv -NonInteractive -PrintResolvedPlan
if ($LASTEXITCODE -ne 0) { throw 'Validation failed.' }
if (-not $SkipDryRun) {
    Write-Host 'Dry run...' -ForegroundColor Cyan
    & .\Build-ADDomain.ps1 -ConfigPath $ConfigPath -DryRun @rv -NonInteractive
    if ($LASTEXITCODE -ne 0) { throw 'Dry run failed.' }
}
Write-Host 'Running Stage A. Do not interrupt.' -ForegroundColor Yellow
& .\Build-ADDomain.ps1 -ConfigPath $ConfigPath @rv -NonInteractive
Write-Host 'If Stage A succeeded, reboot with: Restart-Computer -Force' -ForegroundColor Green
