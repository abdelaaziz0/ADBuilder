[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -Path $root -Recurse -Include *.ps1,*.psm1,*.psd1
foreach ($f in $files) {
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $f.FullName -Raw), [ref]$null)
}
Write-Host "Static parse checks passed for $($files.Count) PowerShell files." -ForegroundColor Green
