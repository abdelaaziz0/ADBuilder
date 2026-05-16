function Register-ADBuilderProvider {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Provider)
    if ([string]::IsNullOrWhiteSpace([string]$Provider.Name)) { throw 'Provider missing Name.' }
    $script:ADBuilderProviders[[string]$Provider.Name] = $Provider
}

function Get-ADBuilderEnabledProviders {
    [CmdletBinding()]
    param($Config)
    $names = New-Object System.Collections.ArrayList
    if ((Test-ADBuilderHasProperty $Config 'providers') -and (Test-ADBuilderHasProperty $Config.providers 'directory') -and ($Config.providers.directory.enabled -ne $false)) { [void]$names.Add('directory') }
    if ((Test-ADBuilderHasProperty $Config 'assertions') -and @($Config.assertions).Count -gt 0) { [void]$names.Add('assertions') }
    return [string[]]$names
}

function Test-ADBuilderPhaseCompleted {
    param($State,[string]$ProviderName,[string]$PhaseName)
    if ($null -eq $State -or $null -eq $State.completedPhases) { return $false }
    $prop = $State.completedPhases.PSObject.Properties[$ProviderName]
    if ($null -eq $prop) { return $false }
    return @($prop.Value) -contains $PhaseName
}

function Add-ADBuilderCompletedPhase {
    param($State,[string]$ProviderName,[string]$PhaseName,[string]$StatePath)
    if ($null -eq $State) { return }
    if ($null -eq $State.completedPhases) { $State | Add-Member -NotePropertyName completedPhases -NotePropertyValue ([pscustomobject]@{}) -Force }
    $prop = $State.completedPhases.PSObject.Properties[$ProviderName]
    $arr = @()
    if ($null -ne $prop) { $arr = @($prop.Value) }
    if ($arr -notcontains $PhaseName) { $arr += $PhaseName }
    $State.completedPhases | Add-Member -NotePropertyName $ProviderName -NotePropertyValue ([string[]]$arr) -Force
    if ($StatePath) { Save-ADBuilderState -State $State -Path $StatePath }
}

function Invoke-ADBuilderProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] $Provider,
        [Parameter(Mandatory=$true)] $Context
    )
    Write-ADBuilderLog -Level Info -Message "Provider start: $($Provider.Name)"
    foreach ($phase in @($Provider.Phases)) {
        $phaseName = [string]$phase.Name
        $funcName = [string]$phase.Function
        if (Test-ADBuilderPhaseCompleted -State $Context.State -ProviderName ([string]$Provider.Name) -PhaseName $phaseName) {
            Write-ADBuilderLog -Level Skip -Message "Phase already completed in state: $($Provider.Name)/$phaseName"
            continue
        }
        if (-not (Get-Command $funcName -ErrorAction SilentlyContinue)) { throw "Provider '$($Provider.Name)' phase '$phaseName' references missing function '$funcName'." }
        Write-ADBuilderLog -Level Phase -Message "Phase start: $($Provider.Name)/$phaseName"
        $beforeFailures = Get-ADBuilderObjectFailureCount
        & $funcName -Context $Context
        $afterFailures = Get-ADBuilderObjectFailureCount
        if ($afterFailures -gt $beforeFailures) {
            throw "Phase '$($Provider.Name)/$phaseName' completed with $($afterFailures - $beforeFailures) failure(s). Phase not checkpointed."
        }
        Add-ADBuilderCompletedPhase -State $Context.State -ProviderName ([string]$Provider.Name) -PhaseName $phaseName -StatePath $Context.StatePath
        Write-ADBuilderLog -Level Success -Message "Phase complete: $($Provider.Name)/$phaseName"
    }
    Write-ADBuilderLog -Level Success -Message "Provider complete: $($Provider.Name)"
}
