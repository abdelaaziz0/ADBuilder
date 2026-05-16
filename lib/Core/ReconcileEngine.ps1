function Test-ADBuilderHasProperty {
    param($Object, [Parameter(Mandatory=$true)][string]$Name)
    if ($null -eq $Object) { return $false }
    return @($Object.PSObject.Properties.Name) -contains $Name
}

function Get-ADBuilderProperty {
    param($Object, [Parameter(Mandatory=$true)][string]$Name, $Default=$null)
    if (Test-ADBuilderHasProperty -Object $Object -Name $Name) { return $Object.$Name }
    return $Default
}

function Get-ADBuilderReconcilePolicy {
    param($Config,[Parameter(Mandatory=$true)][string]$TypeName)
    $defaultMode = 'additive'
    if ((Test-ADBuilderHasProperty $Config 'execution') -and (Test-ADBuilderHasProperty $Config.execution 'reconcile') -and (Test-ADBuilderHasProperty $Config.execution.reconcile 'global') -and (Test-ADBuilderHasProperty $Config.execution.reconcile.global 'default') -and $null -ne $Config.execution.reconcile.global.default) {
        $defaultMode = [string]$Config.execution.reconcile.global.default
    }
    $policy = [ordered]@{ mode=$defaultMode; allowDelete=$false; allowMove=$false; allowPasswordReset=$false }
    if ((Test-ADBuilderHasProperty $Config 'execution') -and (Test-ADBuilderHasProperty $Config.execution 'reconcile') -and (Test-ADBuilderHasProperty $Config.execution.reconcile 'perType') -and $null -ne $Config.execution.reconcile.perType) {
        foreach ($p in @($Config.execution.reconcile.perType.PSObject.Properties)) {
            if ($p.Name -eq $TypeName) {
                foreach ($field in @('mode','allowDelete','allowMove','allowPasswordReset')) {
                    if ((Test-ADBuilderHasProperty $p.Value $field) -and $null -ne $p.Value.$field) { $policy[$field] = $p.Value.$field }
                }
            }
        }
    }
    return [pscustomobject]$policy
}

function Test-ADBuilderMayUpdate { param($Policy) return @('additive','update','exact') -contains [string](Get-ADBuilderProperty $Policy 'mode' 'additive') }
function Test-ADBuilderMayDelete { param($Policy) return ([string](Get-ADBuilderProperty $Policy 'mode' 'additive') -eq 'exact' -and [bool](Get-ADBuilderProperty $Policy 'allowDelete' $false)) }
function Test-ADBuilderMayMove { param($Policy) return [bool](Get-ADBuilderProperty $Policy 'allowMove' $false) }
function Test-ADBuilderMayResetPassword { param($Policy) return [bool](Get-ADBuilderProperty $Policy 'allowPasswordReset' $false) }

function Invoke-ADBuilderCreateOrUpdate {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)] [string] $Bucket,
        [Parameter(Mandatory=$true)] [string] $Identity,
        [Parameter(Mandatory=$true)] [bool] $Exists,
        [Parameter(Mandatory=$true)] [scriptblock] $Create,
        [scriptblock] $Update,
        $Policy,
        [switch] $DryRun
    )
    try {
        if (-not $Exists) {
            if ($DryRun) { Write-ADBuilderLog -Level DryRun -Message "Would create $Bucket '$Identity'"; Add-ADBuilderSummary -Bucket $Bucket -Action WouldCreate; return }
            if ($PSCmdlet.ShouldProcess($Identity,"Create $Bucket")) { & $Create; Add-ADBuilderSummary -Bucket $Bucket -Action Created; Write-ADBuilderLog -Level Success -Message "Created $Bucket '$Identity'" }
            return
        }
        if (-not (Test-ADBuilderMayUpdate -Policy $Policy)) { Write-ADBuilderLog -Level Skip -Message "Exists; createOnly skips $Bucket '$Identity'"; Add-ADBuilderSummary -Bucket $Bucket -Action Skipped; return }
        if ($null -eq $Update) { Write-ADBuilderLog -Level Skip -Message "Exists; no update block for $Bucket '$Identity'"; Add-ADBuilderSummary -Bucket $Bucket -Action Skipped; return }
        if ($DryRun) { Write-ADBuilderLog -Level DryRun -Message "Would reconcile $Bucket '$Identity' using mode '$((Get-ADBuilderProperty $Policy 'mode' 'additive'))'"; Add-ADBuilderSummary -Bucket $Bucket -Action WouldUpdate; return }
        if ($PSCmdlet.ShouldProcess($Identity,"Update $Bucket")) { & $Update; Add-ADBuilderSummary -Bucket $Bucket -Action Updated; Write-ADBuilderLog -Level Success -Message "Reconciled $Bucket '$Identity'" }
    } catch {
        Write-ADBuilderLog -Level Error -Message "Failed $Bucket '$Identity': $($_.Exception.Message)"
        Add-ADBuilderSummary -Bucket $Bucket -Action Failed
    }
}
