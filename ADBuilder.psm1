Set-StrictMode -Version 2.0

$script:ADBuilderRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ADBuilderEngineVersion = '0.3.0-rc3'
$script:ADBuilderProviders = @{}

$coreFiles = @(
    'lib/Core/Logging.ps1',
    'lib/Core/State.ps1',
    'lib/Core/Secrets.ps1',
    'lib/Core/ReconcileEngine.ps1',
    'lib/Core/DAG.ps1',
    'lib/Core/ProviderContract.ps1',
    'lib/Core/Validation.ps1',
    'lib/Core/Orchestrator.ps1'
)
foreach ($file in $coreFiles) {
    $path = Join-Path $script:ADBuilderRoot $file
    if (!(Test-Path -LiteralPath $path)) { throw "Missing core file: $file" }
    . $path
}

$providerFiles = @(
    'lib/Providers/Directory/Directory.ps1',
    'lib/Providers/Assertions/Assertions.ps1'
)
foreach ($file in $providerFiles) {
    $path = Join-Path $script:ADBuilderRoot $file
    if (!(Test-Path -LiteralPath $path)) { throw "Missing provider file: $file" }
    . $path
}

Register-ADBuilderProvider -Provider (Get-ADBuilderDirectoryProvider)
Register-ADBuilderProvider -Provider (Get-ADBuilderAssertionsProvider)

function Get-ADBuilderSupportedProviders {
    [CmdletBinding()]
    param()
    return $script:ADBuilderProviders.Keys | Sort-Object
}

Export-ModuleMember -Function Invoke-ADBuilder,Test-ADBuilderConfig,Get-ADBuilderSupportedProviders
