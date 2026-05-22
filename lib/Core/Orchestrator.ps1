function Invoke-ADBuilder {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)] [string] $ConfigPath,
        [switch] $Resume,
        [switch] $DryRun,
        [switch] $IgnoreDrift,
        [string] $StatePath,
        [switch] $Force,
        [switch] $LabUnsafe,
        [switch] $NonInteractive,
        [switch] $UnsafeReducedValidation,
        [switch] $AllowReducedValidation
    )

    Initialize-ADBuilderLogging -RootPath $script:ADBuilderRoot
    Write-ADBuilderBanner
    $exitCode = 0
    try {
        if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Get-ADBuilderDefaultStatePath -RootPath $script:ADBuilderRoot }
        $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
        $configJson = Get-Content -LiteralPath $ConfigPath -Raw
        $configHash = Get-ADBuilderStringHash -Text $configJson

        Invoke-ADBuilderCanonicalSchemaValidation -ConfigPath $ConfigPath -JsonText $configJson -UnsafeReducedValidation:$UnsafeReducedValidation -AllowReducedValidation:$AllowReducedValidation
        $config = Import-ADBuilderConfig -ConfigPath $ConfigPath -JsonText $configJson
        Invoke-ADBuilderSemanticValidation -Config $config -LabUnsafe:$LabUnsafe -NonInteractive:$NonInteractive -Force:$Force

        $enabled = Get-ADBuilderEnabledProviders -Config $config
        $order = Resolve-ADBuilderProviderOrder -Providers $script:ADBuilderProviders -EnabledProviderNames $enabled
        $compiledHash = $configHash

        if ($DryRun) {
            Write-ADBuilderLog -Level DryRun -Message "Resolved provider order: $($order -join ' -> ')"
            if ($Resume) { Write-ADBuilderLog -Level DryRun -Message 'DryRun resume requested. No state or AD changes will be made.' }
            else { Write-ADBuilderLog -Level DryRun -Message 'DryRun Stage A. No AD DS promotion or provider actions will be made.' }
            $context = New-ADBuilderContext -Config $config -ConfigPath $ConfigPath -DryRun:$true -Force:$Force -LabUnsafe:$LabUnsafe -NonInteractive:$NonInteractive -State $null -StatePath $StatePath
            foreach ($name in $order) { Invoke-ADBuilderProvider -Provider $script:ADBuilderProviders[$name] -Context $context }
            Write-ADBuilderSummary
            return
        }

        if ($Resume) {
            Invoke-ADBuilderStageB -Config $config -ConfigPath $ConfigPath -ConfigHash $configHash -CompiledConfigHash $compiledHash -StatePath $StatePath -Order $order -IgnoreDrift:$IgnoreDrift -Force:$Force -LabUnsafe:$LabUnsafe -NonInteractive:$NonInteractive
        } else {
            if (Test-Path -LiteralPath $StatePath) {
                $existing = Load-ADBuilderState -Path $StatePath
                if ($existing.stage -ne 'Complete') { throw "Existing incomplete state found at $StatePath. Use -Resume or remove the state file intentionally." }
            }
            Invoke-ADBuilderStageA -Config $config -ConfigPath $ConfigPath -ConfigHash $configHash -CompiledConfigHash $compiledHash -Order $order -StatePath $StatePath -Force:$Force -LabUnsafe:$LabUnsafe -NonInteractive:$NonInteractive
        }

        Write-ADBuilderSummary
        $failures = Get-ADBuilderFailureCount
        if ($failures -gt 0) { $exitCode = 1 }
    } catch {
        Write-ADBuilderLog -Level Fatal -Message $_.Exception.Message
        $exitCode = 1
    } finally {
        Stop-ADBuilderLogging
    }
    if ($exitCode -ne 0) { exit $exitCode }
}

function New-ADBuilderContext {
    param($Config,[string]$ConfigPath,[switch]$DryRun,[switch]$Force,[switch]$LabUnsafe,[switch]$NonInteractive,$State,[string]$StatePath)
    return [pscustomobject]@{
        Config = $Config
        ConfigPath = $ConfigPath
        DryRun = [bool]$DryRun
        Force = [bool]$Force
        LabUnsafe = [bool]$LabUnsafe
        NonInteractive = [bool]$NonInteractive
        State = $State
        StatePath = $StatePath
    }
}

function Invoke-ADBuilderStageA {
    param($Config,[string]$ConfigPath,[string]$ConfigHash,[string]$CompiledConfigHash,[string[]]$Order,[string]$StatePath,[switch]$Force,[switch]$LabUnsafe,[switch]$NonInteractive)

    Write-ADBuilderLog -Level Info -Message 'Stage A starting.'
    Test-ADBuilderAdmin
    Test-ADBuilderRuntimePrerequisites

    $dsrm = Get-ADBuilderDSRMPassword -Config $Config -NonInteractive:$NonInteractive
    Install-ADBuilderADDSFeature
    Test-ADBuilderADDSPrerequisites -Config $Config -DSRMPassword $dsrm -NonInteractive:$NonInteractive

    $state = New-ADBuilderStateObject -Mode ([string]$Config.mode) -ConfigHash $ConfigHash -CompiledConfigHash $CompiledConfigHash -ResolvedProviderOrder $Order -LabUnsafe:([bool]$LabUnsafe)
    $state.stage = 'A'
    Save-ADBuilderState -State $state -Path $StatePath

    Invoke-ADBuilderPromotion -Config $Config -DSRMPassword $dsrm -NonInteractive:$NonInteractive -Force:$Force

    $state.stage = 'AwaitingReboot'
    Save-ADBuilderState -State $state -Path $StatePath
    Write-ADBuilderLog -Level Success -Message "Stage A complete. State saved to $StatePath"
    Write-Host ''
    Write-Host 'Reboot this server, then run:' -ForegroundColor Yellow
    Write-Host "  .\Build-ADDomain.ps1 -ConfigPath `"$ConfigPath`" -Resume" -ForegroundColor Yellow
}

function Invoke-ADBuilderStageB {
    param($Config,[string]$ConfigPath,[string]$ConfigHash,[string]$CompiledConfigHash,[string]$StatePath,[string[]]$Order,[switch]$IgnoreDrift,[switch]$Force,[switch]$LabUnsafe,[switch]$NonInteractive)

    Write-ADBuilderLog -Level Info -Message 'Stage B starting.'
    $state = Load-ADBuilderState -Path $StatePath
    Test-ADBuilderStateVersion -State $state -Force:$Force
    if ($state.stage -eq 'Complete') { throw 'State is already Complete; start a new run or remove the state file intentionally.' }
    if ($state.configHash -ne $ConfigHash) {
        $msg = "Config drift detected. State hash=$($state.configHash), current hash=$ConfigHash."
        if (-not $IgnoreDrift) { throw "$msg Use -IgnoreDrift to continue intentionally." }
        Write-ADBuilderLog -Level Warning -Message "$msg Continuing due to -IgnoreDrift."
    }

    if ($state.compiledConfigHash -and $state.compiledConfigHash -ne $CompiledConfigHash) {
        $msg = "Compiled config drift detected. State hash=$($state.compiledConfigHash), current hash=$CompiledConfigHash."
        if (-not $IgnoreDrift) { throw "$msg Use -IgnoreDrift to continue intentionally." }
        Write-ADBuilderLog -Level Warning -Message "$msg Continuing due to -IgnoreDrift."
    }

    if ($IgnoreDrift) {
        $resolvedOrder = $Order
        Write-ADBuilderLog -Level Warning -Message 'Using recomputed provider order because -IgnoreDrift was supplied.'
    } else {
        $resolvedOrder = [string[]]@($state.resolvedProviderOrder)
    }

    Wait-ADBuilderPostPromotionReady -Config $Config

    $state.stage = 'B'
    Save-ADBuilderState -State $state -Path $StatePath
    $context = New-ADBuilderContext -Config $Config -ConfigPath $ConfigPath -DryRun:$false -Force:$Force -LabUnsafe:$LabUnsafe -NonInteractive:$NonInteractive -State $state -StatePath $StatePath

    foreach ($name in $resolvedOrder) {
        if (@($state.completedProviders) -contains $name) {
            Write-ADBuilderLog -Level Skip -Message "Provider already completed in state: $name"
            continue
        }
        try {
            Invoke-ADBuilderProvider -Provider $script:ADBuilderProviders[$name] -Context $context
            $completed = New-Object System.Collections.ArrayList
            foreach ($p in @($state.completedProviders)) { [void]$completed.Add([string]$p) }
            [void]$completed.Add($name)
            $state.completedProviders = [string[]]$completed
            Save-ADBuilderState -State $state -Path $StatePath
        } catch {
            Write-ADBuilderLog -Level Error -Message "Provider failed '$name': $($_.Exception.Message)"
            Add-ADBuilderSummary -Bucket "provider:$name" -Action Failed
            $failed = New-Object System.Collections.ArrayList
            if (-not (Test-ADBuilderHasProperty $state 'failedProviders')) { $state | Add-Member -NotePropertyName failedProviders -NotePropertyValue @() -Force }
            foreach ($p in @($state.failedProviders)) { [void]$failed.Add([string]$p) }
            if (@($failed) -notcontains $name) { [void]$failed.Add($name) }
            $state.failedProviders = [string[]]$failed
            Save-ADBuilderState -State $state -Path $StatePath
            throw
        }
    }

    $state.stage = 'Complete'
    Save-ADBuilderState -State $state -Path $StatePath
    Write-ADBuilderLog -Level Success -Message 'Stage B complete.'
}

function Test-ADBuilderAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run ADBuilder as Administrator.' }
}

function Test-ADBuilderRuntimePrerequisites {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Windows PowerShell 5.1 is required.' }
}

function Install-ADBuilderADDSFeature {
    if (!(Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) { throw 'Install-WindowsFeature not available. Run on Windows Server.' }
    Write-ADBuilderLog -Level Info -Message 'Installing AD-Domain-Services feature.'
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -ErrorAction Stop | Out-Null
}

function Get-ADBuilderDSRMPassword {
    param($Config,[switch]$NonInteractive)
    switch ([string]$Config.mode) {
        'newForest' { return Resolve-ADBuilderSecret -SecretSpec $Config.forest.dsrmPassword -FieldPath 'forest.dsrmPassword' -NonInteractive:$NonInteractive }
        'additionalDC' { return Resolve-ADBuilderSecret -SecretSpec $Config.additionalDC.dsrmPassword -FieldPath 'additionalDC.dsrmPassword' -NonInteractive:$NonInteractive }
        'childDomain' { return Resolve-ADBuilderSecret -SecretSpec $Config.childDomain.dsrmPassword -FieldPath 'childDomain.dsrmPassword' -NonInteractive:$NonInteractive }
    }
}

function Test-ADBuilderADDSPrerequisites {
    param($Config,[securestring]$DSRMPassword,[switch]$NonInteractive)
    Import-Module ADDSDeployment -ErrorAction Stop
    Write-ADBuilderLog -Level Info -Message "Running ADDS prerequisite test for mode $($Config.mode)."
    switch ([string]$Config.mode) {
        'newForest' {
            $params = @{ DomainName=$Config.forest.domainName; DomainNetbiosName=$Config.forest.netbiosName; SafeModeAdministratorPassword=$DSRMPassword; InstallDns=([bool]$Config.forest.installDns); ErrorAction='Stop' }
            if ($Config.forest.forestMode) { $params.ForestMode = [string]$Config.forest.forestMode }
            if ($Config.forest.domainMode) { $params.DomainMode = [string]$Config.forest.domainMode }
            if ($Config.forest.databasePath) { $params.DatabasePath = [string]$Config.forest.databasePath }
            if ($Config.forest.logPath) { $params.LogPath = [string]$Config.forest.logPath }
            if ($Config.forest.sysvolPath) { $params.SysvolPath = [string]$Config.forest.sysvolPath }
            Test-ADDSForestInstallation @params | Out-Null
        }
        'additionalDC' {
            $cred = New-ADBuilderCredential -CredentialSpec $Config.additionalDC.credential -FieldPath 'additionalDC.credential' -NonInteractive:$NonInteractive
            $params = @{ DomainName=$Config.additionalDC.domainName; Credential=$cred; SafeModeAdministratorPassword=$DSRMPassword; InstallDns=([bool]$Config.additionalDC.installDns); ErrorAction='Stop' }
            if ($Config.additionalDC.siteName) { $params.SiteName = [string]$Config.additionalDC.siteName }
            if ($Config.additionalDC.replicationSourceDC) { $params.ReplicationSourceDC = [string]$Config.additionalDC.replicationSourceDC }
            if ($Config.additionalDC.globalCatalog -ne $null) { $params.NoGlobalCatalog = -not [bool]$Config.additionalDC.globalCatalog }
            if ($Config.additionalDC.readOnly -eq $true) { $params.ReadOnlyReplica = $true }
            if ($Config.additionalDC.databasePath) { $params.DatabasePath = [string]$Config.additionalDC.databasePath }
            if ($Config.additionalDC.logPath) { $params.LogPath = [string]$Config.additionalDC.logPath }
            if ($Config.additionalDC.sysvolPath) { $params.SysvolPath = [string]$Config.additionalDC.sysvolPath }
            Test-ADDSDomainControllerInstallation @params | Out-Null
        }
        'childDomain' {
            $cred = New-ADBuilderCredential -CredentialSpec $Config.childDomain.credential -FieldPath 'childDomain.credential' -NonInteractive:$NonInteractive
            $params = @{ ParentDomainName=$Config.childDomain.parentDomainName; NewDomainName=$Config.childDomain.newDomainName; Credential=$cred; SafeModeAdministratorPassword=$DSRMPassword; InstallDns=([bool]$Config.childDomain.installDns); ErrorAction='Stop' }
            if ($Config.childDomain.newDomainNetbiosName) { $params.NewDomainNetbiosName = [string]$Config.childDomain.newDomainNetbiosName }
            if ($Config.childDomain.createDnsDelegation -ne $null) { $params.CreateDnsDelegation = [bool]$Config.childDomain.createDnsDelegation }
            if ($Config.childDomain.siteName) { $params.SiteName = [string]$Config.childDomain.siteName }
            if ($Config.childDomain.replicationSourceDC) { $params.ReplicationSourceDC = [string]$Config.childDomain.replicationSourceDC }
            if ($Config.childDomain.domainMode) { $params.DomainMode = [string]$Config.childDomain.domainMode }
            if ($Config.childDomain.databasePath) { $params.DatabasePath = [string]$Config.childDomain.databasePath }
            if ($Config.childDomain.logPath) { $params.LogPath = [string]$Config.childDomain.logPath }
            if ($Config.childDomain.sysvolPath) { $params.SysvolPath = [string]$Config.childDomain.sysvolPath }
            Test-ADDSDomainInstallation @params | Out-Null
        }
    }
}

function Invoke-ADBuilderPromotion {
    param($Config,[securestring]$DSRMPassword,[switch]$NonInteractive,[switch]$Force)
    Import-Module ADDSDeployment -ErrorAction Stop
    Write-ADBuilderLog -Level Info -Message "Promoting server for mode $($Config.mode)."
    switch ([string]$Config.mode) {
        'newForest' {
            $params = @{ DomainName=$Config.forest.domainName; DomainNetbiosName=$Config.forest.netbiosName; SafeModeAdministratorPassword=$DSRMPassword; InstallDns=([bool]$Config.forest.installDns); NoRebootOnCompletion=$true; Force=$true; ErrorAction='Stop' }
            if ($Config.forest.forestMode) { $params.ForestMode = [string]$Config.forest.forestMode }
            if ($Config.forest.domainMode) { $params.DomainMode = [string]$Config.forest.domainMode }
            if ($Config.forest.databasePath) { $params.DatabasePath = [string]$Config.forest.databasePath }
            if ($Config.forest.logPath) { $params.LogPath = [string]$Config.forest.logPath }
            if ($Config.forest.sysvolPath) { $params.SysvolPath = [string]$Config.forest.sysvolPath }
            Install-ADDSForest @params
        }
        'additionalDC' {
            $cred = New-ADBuilderCredential -CredentialSpec $Config.additionalDC.credential -FieldPath 'additionalDC.credential' -NonInteractive:$NonInteractive
            $params = @{ DomainName=$Config.additionalDC.domainName; Credential=$cred; SafeModeAdministratorPassword=$DSRMPassword; InstallDns=([bool]$Config.additionalDC.installDns); NoRebootOnCompletion=$true; Force=$true; ErrorAction='Stop' }
            if ($Config.additionalDC.siteName) { $params.SiteName = [string]$Config.additionalDC.siteName }
            if ($Config.additionalDC.replicationSourceDC) { $params.ReplicationSourceDC = [string]$Config.additionalDC.replicationSourceDC }
            if ($Config.additionalDC.globalCatalog -ne $null) { $params.NoGlobalCatalog = -not [bool]$Config.additionalDC.globalCatalog }
            if ($Config.additionalDC.readOnly -eq $true) { $params.ReadOnlyReplica = $true }
            if ($Config.additionalDC.databasePath) { $params.DatabasePath = [string]$Config.additionalDC.databasePath }
            if ($Config.additionalDC.logPath) { $params.LogPath = [string]$Config.additionalDC.logPath }
            if ($Config.additionalDC.sysvolPath) { $params.SysvolPath = [string]$Config.additionalDC.sysvolPath }
            Install-ADDSDomainController @params
        }
        'childDomain' {
            $cred = New-ADBuilderCredential -CredentialSpec $Config.childDomain.credential -FieldPath 'childDomain.credential' -NonInteractive:$NonInteractive
            $params = @{ ParentDomainName=$Config.childDomain.parentDomainName; NewDomainName=$Config.childDomain.newDomainName; NewDomainNetbiosName=$Config.childDomain.newDomainNetbiosName; Credential=$cred; SafeModeAdministratorPassword=$DSRMPassword; InstallDns=([bool]$Config.childDomain.installDns); CreateDnsDelegation=([bool]$Config.childDomain.createDnsDelegation); NoRebootOnCompletion=$true; Force=$true; ErrorAction='Stop' }
            if ($Config.childDomain.siteName) { $params.SiteName = [string]$Config.childDomain.siteName }
            if ($Config.childDomain.replicationSourceDC) { $params.ReplicationSourceDC = [string]$Config.childDomain.replicationSourceDC }
            if ($Config.childDomain.domainMode) { $params.DomainMode = [string]$Config.childDomain.domainMode }
            if ($Config.childDomain.databasePath) { $params.DatabasePath = [string]$Config.childDomain.databasePath }
            if ($Config.childDomain.logPath) { $params.LogPath = [string]$Config.childDomain.logPath }
            if ($Config.childDomain.sysvolPath) { $params.SysvolPath = [string]$Config.childDomain.sysvolPath }
            Install-ADDSDomain @params
        }
    }
}

function Wait-ADBuilderPostPromotionReady {
    param($Config)
    Import-Module ActiveDirectory -ErrorAction Stop
    $domainName = switch ([string]$Config.mode) {
        'newForest' { [string]$Config.forest.domainName }
        'additionalDC' { [string]$Config.additionalDC.domainName }
        'childDomain' { "$($Config.childDomain.newDomainName).$($Config.childDomain.parentDomainName)" }
    }
    Write-ADBuilderLog -Level Info -Message "Waiting for AD readiness in domain $domainName."
    $deadline = (Get-Date).AddMinutes(15)
    do {
        try {
            $tcp = New-Object Net.Sockets.TcpClient
            $async = $tcp.BeginConnect('127.0.0.1',9389,$null,$null)
            if (-not $async.AsyncWaitHandle.WaitOne(1500,$false)) { throw 'ADWS port 9389 not accepting connections yet.' }
            $tcp.EndConnect($async); $tcp.Close()
            Get-ADDomain -ErrorAction Stop | Out-Null
            if (-not (Test-Path '\\localhost\SYSVOL')) { throw 'SYSVOL share not ready.' }
            if (-not (Test-Path '\\localhost\NETLOGON')) { throw 'NETLOGON share not ready.' }
            Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$domainName" -Type SRV -ErrorAction Stop | Out-Null
            if ([string]$Config.mode -eq 'additionalDC' -and (Get-Command repadmin.exe -ErrorAction SilentlyContinue)) {
                $out = & repadmin.exe /replsummary 2>&1
                if ($LASTEXITCODE -ne 0) { throw "repadmin /replsummary failed: $out" }
            }
            Write-ADBuilderLog -Level Success -Message 'AD readiness checks passed.'
            return
        } catch {
            Write-ADBuilderLog -Level Info -Message "Readiness pending: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)
    throw 'Timed out waiting for AD readiness (ADWS, Get-ADDomain, SYSVOL, NETLOGON, SRV record, replication when relevant).'
}
