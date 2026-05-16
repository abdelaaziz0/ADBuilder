function Get-ADBuilderFileHash {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ADBuilderStringHash {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $sha.Dispose() }
}

function Get-ADBuilderDefaultStatePath {
    param([string]$RootPath)
    $dir = Join-Path $RootPath 'state'
    if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return Join-Path $dir 'current-run.json'
}

function New-ADBuilderStateObject {
    param(
        [string]$Mode,
        [string]$ConfigHash,
        [string]$CompiledConfigHash,
        [string[]]$ResolvedProviderOrder,
        [bool]$LabUnsafe
    )
    return [ordered]@{
        engineVersion = $script:ADBuilderEngineVersion
        configHash = $ConfigHash
        compiledConfigHash = $CompiledConfigHash
        resolvedProviderOrder = @($ResolvedProviderOrder)
        completedProviders = @()
        completedPhases = @{}
        failedProviders = @()
        stage = 'A'
        mode = $Mode
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        lastUpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        labUnsafe = $LabUnsafe
    }
}

function Save-ADBuilderState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)][string]$Path)
    $State.lastUpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $dir = Split-Path -Parent $Path
    if ($dir -and !(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = "$Path.tmp"
    $backup = "$Path.bak"
    $State | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $tmp -Encoding UTF8
    if (Test-Path -LiteralPath $Path) {
        try { Copy-Item -LiteralPath $Path -Destination $backup -Force -ErrorAction Stop } catch { }
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
}

function Load-ADBuilderState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { throw "State file not found: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch {
        $backup = "$Path.bak"
        if (Test-Path -LiteralPath $backup) {
            throw "State file is corrupt: $Path. A backup exists at $backup. Original error: $($_.Exception.Message)"
        }
        throw "State file is corrupt: $Path. Original error: $($_.Exception.Message)"
    }
}

function Test-ADBuilderStateVersion {
    param($State,[switch]$Force)
    if ($State.engineVersion -ne $script:ADBuilderEngineVersion) {
        if (-not $Force) {
            throw "State engine version '$($State.engineVersion)' does not match current '$script:ADBuilderEngineVersion'. Use -Force only if you understand the risk."
        }
        Write-ADBuilderLog -Level Warning -Message "Forcing resume across engine version mismatch: state=$($State.engineVersion), current=$script:ADBuilderEngineVersion"
    }
}
