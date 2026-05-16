function Initialize-ADBuilderLogging {
    [CmdletBinding()]
    param([string]$RootPath)

    $logDir = Join-Path $RootPath 'logs'
    if (!(Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:ADBuilderLogPath = Join-Path $logDir "build-$timestamp.log"
    $script:ADBuilderSummary = @{}
    try { Start-Transcript -Path $script:ADBuilderLogPath -Force | Out-Null } catch { }
}

function Stop-ADBuilderLogging {
    try { Stop-Transcript | Out-Null } catch { }
}

function Write-ADBuilderBanner {
    [CmdletBinding()]
    param()
    if ($env:ADBUILDER_NO_BANNER -eq '1' -or $env:ADBUILDER_BANNER_SHOWN -eq '1') { return }
    $env:ADBUILDER_BANNER_SHOWN = '1'
    $lines = @(
        '    ___    ____  ____        _ __    __          ',
        '   /   |  / __ \/ __ )__  __(_) /___/ /__  _____',
        '  / /| | / / / / __  / / / / / / __  / _ \/ ___/',
        ' / ___ |/ /_/ / /_/ / /_/ / / / /_/ /  __/ /    ',
        '/_/  |_/_____/_____/\__,_/_/_/\__,_/\___/_/     ',
        '          ADBuilder | Active Directory lab engine'
    )
    foreach ($line in $lines) { Write-Host $line -ForegroundColor Cyan }
    Write-Host ''
}

function Write-ADBuilderLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [ValidateSet('Info','Success','Warning','Error','Skip','DryRun','Fatal','Phase','Dependency')] [string] $Level,
        [Parameter(Mandatory=$true)] [string] $Message
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[$ts][$Level]"
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Fatal'   { 'Red' }
        'Skip'    { 'DarkGray' }
        'DryRun'  { 'Cyan' }
        'Phase'   { 'White' }
        'Dependency' { 'Magenta' }
        default   { 'Gray' }
    }
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Add-ADBuilderSummary {
    param(
        [Parameter(Mandatory=$true)] [string] $Bucket,
        [Parameter(Mandatory=$true)] [ValidateSet('Created','Updated','Skipped','Failed','DependencyFailed','WouldCreate','WouldUpdate','WouldSkip','AssertPassed','AssertFailed')] [string] $Action
    )
    if (-not $script:ADBuilderSummary.ContainsKey($Bucket)) {
        $script:ADBuilderSummary[$Bucket] = @{
            Created = 0; Updated = 0; Skipped = 0; Failed = 0; DependencyFailed = 0;
            WouldCreate = 0; WouldUpdate = 0; WouldSkip = 0;
            AssertPassed = 0; AssertFailed = 0
        }
    }
    if (-not $script:ADBuilderSummary[$Bucket].ContainsKey($Action)) { $script:ADBuilderSummary[$Bucket][$Action] = 0 }
    $script:ADBuilderSummary[$Bucket][$Action] = [int]$script:ADBuilderSummary[$Bucket][$Action] + 1
}

function Write-ADBuilderSummary {
    Write-Host ''
    Write-Host '=== ADBuilder Summary ===' -ForegroundColor White
    foreach ($bucket in ($script:ADBuilderSummary.Keys | Sort-Object)) {
        $s = $script:ADBuilderSummary[$bucket]
        Write-Host ("{0,-22} created={1} updated={2} skipped={3} failed={4} depFailed={5} dryCreate={6} dryUpdate={7} assertsPass={8} assertsFail={9}" -f $bucket,$s.Created,$s.Updated,$s.Skipped,$s.Failed,$s.DependencyFailed,$s.WouldCreate,$s.WouldUpdate,$s.AssertPassed,$s.AssertFailed)
    }
}

function Get-ADBuilderObjectFailureCount {
    $total = 0
    foreach ($bucket in $script:ADBuilderSummary.Keys) {
        $total += [int]$script:ADBuilderSummary[$bucket].Failed
        $total += [int]$script:ADBuilderSummary[$bucket].DependencyFailed
    }
    return $total
}

function Get-ADBuilderAssertionFailureCount {
    $total = 0
    foreach ($bucket in $script:ADBuilderSummary.Keys) {
        $total += [int]$script:ADBuilderSummary[$bucket].AssertFailed
    }
    return $total
}

function Get-ADBuilderFailureCount {
    return (Get-ADBuilderObjectFailureCount) + (Get-ADBuilderAssertionFailureCount)
}
