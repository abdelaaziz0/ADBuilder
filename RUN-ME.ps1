[CmdletBinding()]
param(
    [string]$InterfaceAlias = 'Ethernet',
    [string]$StaticIP = '172.20.10.50',
    [int]$PrefixLength = 24,
    [string]$Gateway = '172.20.10.1',
    [string]$PrePromotionDns = '',
    [string]$ComputerName = 'DC01',
    [string]$ConfigPath = '.\examples\reference.json',
    [switch]$NoAutoReboot,
    [switch]$ResetState,
    [switch]$SkipDryRun,
    [switch]$SkipNegativeTest,
    [switch]$NoReducedValidation,
    [switch]$IgnoreDrift
)
$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $p=New-Object Security.Principal.WindowsPrincipal($id)
    if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Run this script as Administrator.' }
}

function Get-StateObject {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { throw "State file exists but cannot be parsed: $Path. Check .bak or delete intentionally." }
    }
    return $null
}

function Is-DomainReadyEnough {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $null = Get-ADDomain -ErrorAction Stop
        return $true
    } catch { return $false }
}

Assert-Admin
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

$statePath = Join-Path $root 'state\current-run.json'
$prepMarker = Join-Path $root 'state\prepared.marker.json'

if (-not (Test-Path -LiteralPath $prepMarker) -or ($env:COMPUTERNAME -ne $ComputerName)) {
    Write-Host '[RUN-ME] Preparing fresh Server/Core VM...' -ForegroundColor Cyan
    $prepArgs = @('-InterfaceAlias',$InterfaceAlias,'-StaticIP',$StaticIP,'-PrefixLength',$PrefixLength,'-Gateway',$Gateway,'-ComputerName',$ComputerName)
    if ($PrePromotionDns) { $prepArgs += @('-PrePromotionDns',$PrePromotionDns) }
    if ($NoAutoReboot) { $prepArgs += '-NoRestart' }
    & .\tools\00-Prepare-ServerCore.ps1 @prepArgs
    if ($env:COMPUTERNAME -ne $ComputerName) {
        Write-Host '[RUN-ME] Rename requested. Reboot, then run .\RUN-ME.ps1 again.' -ForegroundColor Yellow
        return
    }
}

if (-not $env:ADBUILDER_DSRM_PASSWORD) { $env:ADBUILDER_DSRM_PASSWORD=[Environment]::GetEnvironmentVariable('ADBUILDER_DSRM_PASSWORD','Machine') }
if (-not $env:ADBUILDER_DEFAULT_USER_PASSWORD) { $env:ADBUILDER_DEFAULT_USER_PASSWORD=[Environment]::GetEnvironmentVariable('ADBUILDER_DEFAULT_USER_PASSWORD','Machine') }
if (-not $env:ADBUILDER_DSRM_PASSWORD -or -not $env:ADBUILDER_DEFAULT_USER_PASSWORD) { throw 'Missing ADBuilder machine secrets. Re-run tools\00-Prepare-ServerCore.ps1.' }

if ($ResetState -and (Test-Path -LiteralPath $statePath)) {
    Write-Host '[RUN-ME] ResetState requested; removing state\current-run.json' -ForegroundColor Yellow
    Remove-Item -LiteralPath $statePath -Force
}

$state = Get-StateObject -Path $statePath

if ($null -eq $state) {
    if (-not $SkipNegativeTest) {
        Write-Host '[RUN-ME] Running negative mode-block test...' -ForegroundColor Cyan
        & .\tools\04-Test-NegativeModeBlock.ps1 -ConfigPath $ConfigPath -NoReducedValidation:$NoReducedValidation
    }
    Write-Host '[RUN-ME] Running Stage A wrapper...' -ForegroundColor Cyan
    & .\tools\01-Run-StageA.ps1 -ConfigPath $ConfigPath -ResetState:$ResetState -SkipDryRun:$SkipDryRun -NoReducedValidation:$NoReducedValidation
    $state = Get-StateObject -Path $statePath
    if ($state -and [string]$state.stage -eq 'AwaitingReboot') {
        if ($NoAutoReboot) {
            Write-Host '[RUN-ME] Stage A completed. Reboot manually, then run .\RUN-ME.ps1 again.' -ForegroundColor Green
            Write-Host '  Restart-Computer -Force' -ForegroundColor Yellow
        } else {
            Write-Host '[RUN-ME] Stage A completed. Rebooting now. After reboot, run .\RUN-ME.ps1 again.' -ForegroundColor Green
            Restart-Computer -Force
        }
    }
    return
}

if ([string]$state.stage -eq 'AwaitingReboot' -or [string]$state.stage -eq 'A' -or [string]$state.stage -eq 'B') {
    if (-not (Is-DomainReadyEnough)) {
        if ($NoAutoReboot) {
            Write-Host '[RUN-ME] State says Stage A ran, but AD is not ready in this boot. Reboot manually and run .\RUN-ME.ps1 again.' -ForegroundColor Yellow
            Write-Host '  Restart-Computer -Force' -ForegroundColor Yellow
        } else {
            Write-Host '[RUN-ME] State says Stage A ran, but AD is not ready. Rebooting now.' -ForegroundColor Yellow
            Restart-Computer -Force
        }
        return
    }
    Write-Host '[RUN-ME] Running Stage B...' -ForegroundColor Cyan
    & .\tools\02-Run-StageB.ps1 -ConfigPath $ConfigPath -IgnoreDrift:$IgnoreDrift -NoReducedValidation:$NoReducedValidation
    Write-Host '[RUN-ME] Running post-check...' -ForegroundColor Cyan
    & .\tools\03-PostCheck.ps1
    Write-Host '[RUN-ME] Done.' -ForegroundColor Green
    return
}

if ([string]$state.stage -eq 'Complete') {
    Write-Host '[RUN-ME] State is already Complete. Running post-check only.' -ForegroundColor Green
    & .\tools\03-PostCheck.ps1
    return
}

throw "Unknown state stage: $($state.stage)"
