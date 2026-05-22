[CmdletBinding()]
param(
    [string]$InterfaceAlias = 'Ethernet',
    [string]$StaticIP = '172.20.10.50',
    [int]$PrefixLength = 24,
    [string]$Gateway = '172.20.10.1',
    [string]$PrePromotionDns = '',
    [string]$ComputerName = 'DC01',
    [string]$BuiltinAdminPassword = '',
    [string]$DSRMPassword = '',
    [string]$DefaultUserPassword = '',
    [switch]$RotateSecrets,
    [switch]$SkipRename,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'

function Convert-PrefixToMask([int]$Prefix) {
    $mask = [uint32]0
    for ($i=0; $i -lt $Prefix; $i++) { $mask = $mask -bor ([uint32]1 -shl (31-$i)) }
    return (($mask -shr 24) -band 255).ToString()+'.'+(($mask -shr 16) -band 255)+'.'+(($mask -shr 8) -band 255)+'.'+($mask -band 255)
}

function Assert-Admin {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $p=New-Object Security.Principal.WindowsPrincipal($id)
    if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Run as Administrator.' }
}

function New-ADBuilderRandomPassword {
    param([int]$Length = 24)
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lower = 'abcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $digits = '23456789'.ToCharArray()
    $symbols = '!@#%_-+=?'.ToCharArray()
    $all = @($upper + $lower + $digits + $symbols)
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    try {
        function Pick($arr) {
            $b = New-Object byte[] 1
            $rng.GetBytes($b)
            return $arr[$b[0] % $arr.Length]
        }
        $chars = New-Object System.Collections.ArrayList
        [void]$chars.Add((Pick $upper)); [void]$chars.Add((Pick $lower)); [void]$chars.Add((Pick $digits)); [void]$chars.Add((Pick $symbols))
        while ($chars.Count -lt $Length) { [void]$chars.Add((Pick $all)) }
        for ($i=$chars.Count-1; $i -gt 0; $i--) {
            $b = New-Object byte[] 1; $rng.GetBytes($b); $j = $b[0] % ($i+1)
            $tmp=$chars[$i]; $chars[$i]=$chars[$j]; $chars[$j]=$tmp
        }
        return -join $chars
    } finally { $rng.Dispose() }
}

function Get-OrCreateSecret {
    param([string]$Name,[string]$Provided,[switch]$Rotate)
    if (-not [string]::IsNullOrWhiteSpace($Provided)) { return $Provided }
    $existing = [Environment]::GetEnvironmentVariable($Name,'Machine')
    if (-not $Rotate -and -not [string]::IsNullOrWhiteSpace($existing)) { return $existing }
    return New-ADBuilderRandomPassword
}

Assert-Admin
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

$BuiltinAdminPassword = Get-OrCreateSecret -Name 'ADBUILDER_BUILTIN_ADMIN_PASSWORD' -Provided $BuiltinAdminPassword -Rotate:$RotateSecrets
$DSRMPassword = Get-OrCreateSecret -Name 'ADBUILDER_DSRM_PASSWORD' -Provided $DSRMPassword -Rotate:$RotateSecrets
$DefaultUserPassword = Get-OrCreateSecret -Name 'ADBUILDER_DEFAULT_USER_PASSWORD' -Provided $DefaultUserPassword -Rotate:$RotateSecrets

if ([string]::IsNullOrWhiteSpace($PrePromotionDns)) { $PrePromotionDns = $Gateway }
$mask = Convert-PrefixToMask $PrefixLength
Write-Host "Configuring IPv4 on $InterfaceAlias -> $StaticIP/$PrefixLength gw $Gateway dns $PrePromotionDns" -ForegroundColor Cyan
if ($null -eq (Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue)) {
    $available = @(Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    throw "Network adapter '$InterfaceAlias' not found. Available adapters: $($available -join ', '). Re-run with -InterfaceAlias set to one of these."
}
& netsh interface ipv4 set address name="$InterfaceAlias" source=static address=$StaticIP mask=$mask gateway=$Gateway | Out-Host
if ($LASTEXITCODE -ne 0) { throw "netsh failed to set the static IPv4 address on '$InterfaceAlias' (exit $LASTEXITCODE). The VM was not reconfigured; not renaming or rebooting." }
& netsh interface ipv4 set dnsservers name="$InterfaceAlias" source=static address=$PrePromotionDns validate=no | Out-Host
if ($LASTEXITCODE -ne 0) { throw "netsh failed to set DNS servers on '$InterfaceAlias' (exit $LASTEXITCODE). The VM was not reconfigured; not renaming or rebooting." }

$admin = (Get-LocalUser | Where-Object { $_.SID -like '*-500' } | Select-Object -First 1).Name
if ($admin) {
    Write-Host "Enabling localized built-in administrator: $admin" -ForegroundColor Cyan
    & net user $admin $BuiltinAdminPassword /active:yes | Out-Host
}

[Environment]::SetEnvironmentVariable('ADBUILDER_BUILTIN_ADMIN_PASSWORD',$BuiltinAdminPassword,'Machine')
[Environment]::SetEnvironmentVariable('ADBUILDER_DSRM_PASSWORD',$DSRMPassword,'Machine')
[Environment]::SetEnvironmentVariable('ADBUILDER_DEFAULT_USER_PASSWORD',$DefaultUserPassword,'Machine')
$env:ADBUILDER_BUILTIN_ADMIN_PASSWORD=$BuiltinAdminPassword
$env:ADBUILDER_DSRM_PASSWORD=$DSRMPassword
$env:ADBUILDER_DEFAULT_USER_PASSWORD=$DefaultUserPassword

$stateDir = Join-Path $root 'state'
if (!(Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
$secretPath = Join-Path $stateDir 'generated-secrets.txt'
$secretText = @()
$secretText += 'ADBuilder generated lab secrets. Keep private. Delete after the lab is built.'
$secretText += "GeneratedUtc=$((Get-Date).ToUniversalTime().ToString('o'))"
$secretText += "ComputerName=$ComputerName"
$secretText += "LocalizedBuiltinAdmin=$admin"
$secretText += "BuiltinAdminPassword=$BuiltinAdminPassword"
$secretText += "DSRMPassword=$DSRMPassword"
$secretText += "DefaultUserPassword=$DefaultUserPassword"
$secretText | Set-Content -LiteralPath $secretPath -Encoding UTF8
try { & icacls.exe $secretPath /inheritance:r /grant:r "Administrators:F" /grant:r "SYSTEM:F" | Out-Null } catch { }

$markerPath = Join-Path $stateDir 'prepared.marker.json'
$marker = [ordered]@{
    preparedUtc = (Get-Date).ToUniversalTime().ToString('o')
    computerName = $ComputerName
    currentComputerName = $env:COMPUTERNAME
    interfaceAlias = $InterfaceAlias
    staticIP = $StaticIP
    prefixLength = $PrefixLength
    gateway = $Gateway
    prePromotionDns = $PrePromotionDns
    localizedBuiltinAdmin = $admin
}
$marker | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $markerPath -Encoding UTF8

Write-Host ''
Write-Host "Generated/selected passwords were written to: $secretPath" -ForegroundColor Yellow
Write-Host 'Keep this file private and delete it once the lab is built.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Current network:' -ForegroundColor Cyan
ipconfig /all

if (-not $SkipRename -and $env:COMPUTERNAME -ne $ComputerName) {
    Write-Host "Renaming computer from $env:COMPUTERNAME to $ComputerName" -ForegroundColor Yellow
    Rename-Computer -NewName $ComputerName -Force
    if (-not $NoRestart) {
        Write-Host 'Restarting now. After reboot run the same command again: .\RUN-ME.ps1' -ForegroundColor Yellow
        Restart-Computer -Force
    } else {
        Write-Host 'Rename pending. Restart manually before Stage A.' -ForegroundColor Yellow
    }
    return
}

Write-Host ''
Write-Host 'Preparation complete. Take a VM snapshot now, then run:' -ForegroundColor Green
Write-Host '  .\RUN-ME.ps1' -ForegroundColor Green
Write-Host 'or:' -ForegroundColor DarkGray
Write-Host '  .\tools\01-Run-StageA.ps1' -ForegroundColor DarkGray
