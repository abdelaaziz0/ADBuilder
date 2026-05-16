[CmdletBinding()]
param(
    [string]$ConfigPath = '.\examples\lab-newforest-m1.json',
    [switch]$NoReducedValidation
)
$ErrorActionPreference='Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root
$rv = @()
if (-not $NoReducedValidation) { $rv += '-AllowReducedValidation' }
$badPath = Join-Path $root 'state\bad-modeblock-test.json'
if (!(Test-Path .\state)) { New-Item -ItemType Directory -Path .\state -Force | Out-Null }
$j = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$j | Add-Member -MemberType NoteProperty -Name additionalDC -Value ([pscustomobject]@{ domainName = 'bad.local' }) -Force
$j | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $badPath -Encoding UTF8
$out = Join-Path $root 'state\bad-modeblock-test.out.txt'
$err = Join-Path $root 'state\bad-modeblock-test.err.txt'
Remove-Item $out,$err -ErrorAction SilentlyContinue
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'Validate-ADBuilderConfig.ps1'),'-ConfigPath',$badPath,'-NonInteractive') + $rv
$p = Start-Process -FilePath $ps -ArgumentList $args -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
$text = ''
if (Test-Path $out) { $text += Get-Content $out -Raw }
if (Test-Path $err) { $text += Get-Content $err -Raw }
if ($p.ExitCode -eq 0) { throw 'Negative mode-block test failed: malformed config unexpectedly validated successfully.' }
if ($text -notmatch 'mode=newForest allows only the forest block') {
    Write-Host $text
    throw 'Negative mode-block test failed: expected clean mode-block error was not found.'
}
Write-Host 'Negative mode-block test passed.' -ForegroundColor Green
