function Import-ADBuilderConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [string]$JsonText
    )
    if ([string]::IsNullOrEmpty($JsonText)) {
        if (!(Test-Path -LiteralPath $ConfigPath)) { throw "Config not found: $ConfigPath" }
        $JsonText = Get-Content -LiteralPath $ConfigPath -Raw
    }
    try { $cfg = $JsonText | ConvertFrom-Json } catch { throw "Invalid JSON: $($_.Exception.Message)" }
    return Normalize-ADBuilderConfig -Config $cfg
}

function Ensure-ADBuilderProperty {
    param($Object,[string]$Name,$Value)
    if ($null -eq $Object) { return }
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Normalize-ADBuilderOU {
    param($OU)
    Ensure-ADBuilderProperty $OU 'path' $null
    Ensure-ADBuilderProperty $OU 'description' $null
    Ensure-ADBuilderProperty $OU 'protectFromDeletion' $null
    Ensure-ADBuilderProperty $OU 'children' @()
    foreach ($child in @($OU.children)) { Normalize-ADBuilderOU $child }
}

function Normalize-ADBuilderConfig {
    param($Config)
    if ($null -eq $Config) { return $Config }
    Ensure-ADBuilderProperty $Config 'execution' ([pscustomobject]@{})
    Ensure-ADBuilderProperty $Config.execution 'labMode' $false
    Ensure-ADBuilderProperty $Config.execution 'reconcile' ([pscustomobject]@{})
    Ensure-ADBuilderProperty $Config.execution.reconcile 'global' ([pscustomobject]@{ default='additive' })
    Ensure-ADBuilderProperty $Config.execution.reconcile.global 'default' 'additive'
    Ensure-ADBuilderProperty $Config.execution.reconcile 'perType' ([pscustomobject]@{})
    foreach ($p in @($Config.execution.reconcile.perType.PSObject.Properties)) {
        Ensure-ADBuilderProperty $p.Value 'allowDelete' $false
        Ensure-ADBuilderProperty $p.Value 'allowMove' $false
        Ensure-ADBuilderProperty $p.Value 'allowPasswordReset' $false
        Ensure-ADBuilderProperty $p.Value 'mode' $Config.execution.reconcile.global.default
    }

    Ensure-ADBuilderProperty $Config 'labVulnerabilities' ([pscustomobject]@{ enabled=$false; items=@() })
    Ensure-ADBuilderProperty $Config.labVulnerabilities 'enabled' $false
    Ensure-ADBuilderProperty $Config.labVulnerabilities 'items' @()
    Ensure-ADBuilderProperty $Config 'assertions' @()
    foreach ($a in @($Config.assertions)) {
        Ensure-ADBuilderProperty $a 'identity' $null
        Ensure-ADBuilderProperty $a 'principal' $null
        Ensure-ADBuilderProperty $a 'group' $null
        Ensure-ADBuilderProperty $a 'recursive' $false
    }
    Ensure-ADBuilderProperty $Config 'providers' ([pscustomobject]@{})

    if ((Test-ADBuilderHasProperty $Config 'forest') -and $null -ne $Config.forest) {
        Ensure-ADBuilderProperty $Config.forest 'forestMode' 'WinThreshold'
        Ensure-ADBuilderProperty $Config.forest 'domainMode' 'WinThreshold'
        Ensure-ADBuilderProperty $Config.forest 'installDns' $true
        Ensure-ADBuilderProperty $Config.forest 'databasePath' 'C:\Windows\NTDS'
        Ensure-ADBuilderProperty $Config.forest 'logPath' 'C:\Windows\NTDS'
        Ensure-ADBuilderProperty $Config.forest 'sysvolPath' 'C:\Windows\SYSVOL'
        Ensure-ADBuilderProperty $Config.forest 'dsrmPassword' ([pscustomobject]@{source='env';name='ADBUILDER_DSRM_PASSWORD'})
    }
    if ((Test-ADBuilderHasProperty $Config 'additionalDC') -and $null -ne $Config.additionalDC) {
        Ensure-ADBuilderProperty $Config.additionalDC 'installDns' $true
        Ensure-ADBuilderProperty $Config.additionalDC 'globalCatalog' $true
        Ensure-ADBuilderProperty $Config.additionalDC 'readOnly' $false
        Ensure-ADBuilderProperty $Config.additionalDC 'databasePath' 'C:\Windows\NTDS'
        Ensure-ADBuilderProperty $Config.additionalDC 'logPath' 'C:\Windows\NTDS'
        Ensure-ADBuilderProperty $Config.additionalDC 'sysvolPath' 'C:\Windows\SYSVOL'
        Ensure-ADBuilderProperty $Config.additionalDC 'dsrmPassword' ([pscustomobject]@{source='env';name='ADBUILDER_DSRM_PASSWORD'})
    }
    if ((Test-ADBuilderHasProperty $Config 'childDomain') -and $null -ne $Config.childDomain) {
        Ensure-ADBuilderProperty $Config.childDomain 'installDns' $true
        Ensure-ADBuilderProperty $Config.childDomain 'createDnsDelegation' $false
        Ensure-ADBuilderProperty $Config.childDomain 'domainMode' 'WinThreshold'
        Ensure-ADBuilderProperty $Config.childDomain 'databasePath' 'C:\Windows\NTDS'
        Ensure-ADBuilderProperty $Config.childDomain 'logPath' 'C:\Windows\NTDS'
        Ensure-ADBuilderProperty $Config.childDomain 'sysvolPath' 'C:\Windows\SYSVOL'
        Ensure-ADBuilderProperty $Config.childDomain 'dsrmPassword' ([pscustomobject]@{source='env';name='ADBUILDER_DSRM_PASSWORD'})
    }

    if (-not (Test-ADBuilderHasProperty $Config.providers 'directory') -or $null -eq $Config.providers.directory) {
        $Config.providers | Add-Member -MemberType NoteProperty -Name directory -Value ([pscustomobject]@{ enabled=$false }) -Force
    }
    $d = $Config.providers.directory
    Ensure-ADBuilderProperty $d 'enabled' $true
    foreach ($arr in @('sites','siteLinks','ous','groups','users','computers','fineGrainedPasswordPolicies','delegations','aclEdges')) { Ensure-ADBuilderProperty $d $arr @() }
    foreach ($ou in @($d.ous)) { Normalize-ADBuilderOU $ou }
    foreach ($g in @($d.groups)) {
        Ensure-ADBuilderProperty $g 'description' $null
        Ensure-ADBuilderProperty $g 'members' @()
        Ensure-ADBuilderProperty $g 'memberOf' @()
    }
    foreach ($u in @($d.users)) {
        Ensure-ADBuilderProperty $u 'givenName' $null
        Ensure-ADBuilderProperty $u 'surname' $null
        Ensure-ADBuilderProperty $u 'displayName' $u.samAccountName
        Ensure-ADBuilderProperty $u 'userPrincipalName' $null
        Ensure-ADBuilderProperty $u 'enabled' $true
        Ensure-ADBuilderProperty $u 'passwordNeverExpires' $true
        Ensure-ADBuilderProperty $u 'changePasswordAtLogon' $false
        Ensure-ADBuilderProperty $u 'title' $null
        Ensure-ADBuilderProperty $u 'department' $null
        Ensure-ADBuilderProperty $u 'groups' @()
        Ensure-ADBuilderProperty $u 'spns' @()
        Ensure-ADBuilderProperty $u 'accountControlFlags' @()
    }
    foreach ($c in @($d.computers)) {
        Ensure-ADBuilderProperty $c 'description' $null
        Ensure-ADBuilderProperty $c 'enabled' $true
    }
    foreach ($p in @($d.fineGrainedPasswordPolicies)) {
        Ensure-ADBuilderProperty $p 'appliesTo' @()
        Ensure-ADBuilderProperty $p 'minPasswordLength' 12
        Ensure-ADBuilderProperty $p 'passwordHistoryCount' 24
        Ensure-ADBuilderProperty $p 'complexityEnabled' $true
        Ensure-ADBuilderProperty $p 'reversibleEncryptionEnabled' $false
        Ensure-ADBuilderProperty $p 'lockoutThreshold' 0
        Ensure-ADBuilderProperty $p 'lockoutDuration' '00:30:00'
        Ensure-ADBuilderProperty $p 'lockoutObservationWindow' '00:30:00'
        Ensure-ADBuilderProperty $p 'maxPasswordAge' '42.00:00:00'
        Ensure-ADBuilderProperty $p 'minPasswordAge' '1.00:00:00'
    }
    foreach ($edge in @($d.delegations) + @($d.aclEdges)) { if ($edge) { Ensure-ADBuilderProperty $edge 'labUnsafe' $false } }
    return $Config
}

function Add-ADBuilderValidationWarning {
    param([string]$Message)
    $validationWarnings = Get-Variable -Name ADBuilderValidationWarnings -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $validationWarnings -and $null -ne $validationWarnings.Value) { [void]$validationWarnings.Value.Add($Message) }
    Write-ADBuilderLog -Level Warning -Message $Message
}

function Invoke-ADBuilderCanonicalSchemaValidation {
    [CmdletBinding()]
    param([string]$ConfigPath,[string]$JsonText,[switch]$UnsafeReducedValidation,[switch]$AllowReducedValidation)
    $useUnsafeReducedValidation = [bool]$UnsafeReducedValidation -or [bool]$AllowReducedValidation
    if ($AllowReducedValidation -and -not $UnsafeReducedValidation) {
        Add-ADBuilderValidationWarning -Message '-AllowReducedValidation is deprecated and unsafe. Use -UnsafeReducedValidation to explicitly accept that schema validation may be reduced and is not for production/CI.'
    }
    $schemaPath = Join-Path $script:ADBuilderRoot 'schemas/root.schema.json'
    $dllDir = Join-Path $script:ADBuilderRoot 'third_party/NJsonSchema'
    $dll = Join-Path $dllDir 'NJsonSchema.dll'
    if (Test-Path -LiteralPath $dll) {
        try {
            $deps = Get-ChildItem -Path $dllDir -Filter '*.dll' -ErrorAction SilentlyContinue
            foreach ($d in $deps) { try { Add-Type -Path $d.FullName -ErrorAction Stop } catch { } }
            if ([string]::IsNullOrEmpty($JsonText)) { $JsonText = Get-Content -LiteralPath $ConfigPath -Raw }
            $schema = [NJsonSchema.JsonSchema]::FromFileAsync($schemaPath).GetAwaiter().GetResult()
            $errors = $schema.Validate($JsonText)
            if ($errors.Count -gt 0) {
                $lines = @()
                foreach ($e in $errors) { $lines += ("{0}: {1}" -f $e.Path, $e.Kind) }
                throw "Schema validation failed:`n$($lines -join "`n")"
            }
            Write-ADBuilderLog -Level Success -Message 'Canonical NJsonSchema validation passed.'
            return
        } catch {
            if (-not $useUnsafeReducedValidation) { throw "Canonical schema validation failed: $($_.Exception.Message)" }
            Add-ADBuilderValidationWarning -Message "UNSAFE REDUCED VALIDATION: schema validation is reduced because canonical NJsonSchema validation failed. This is not for production/CI. Error: $($_.Exception.Message)"
            return
        }
    }
    if ($useUnsafeReducedValidation) {
        Add-ADBuilderValidationWarning -Message 'UNSAFE REDUCED VALIDATION: schema validation is reduced because canonical NJsonSchema validator was not found. This is not for production/CI.'
        return
    }
    throw 'Canonical NJsonSchema validator not found. Vendor/pin NJsonSchema under third_party/NJsonSchema or pass -UnsafeReducedValidation for disposable lab testing only.'
}

function Assert-ADBuilderRequiredString {
    param($Object,[string]$Property,[string]$Path)
    if ($null -eq $Object -or -not (Test-ADBuilderHasProperty $Object $Property) -or $null -eq $Object.$Property -or [string]::IsNullOrWhiteSpace([string]$Object.$Property)) {
        throw "Required field missing: $Path.$Property"
    }
}

function Test-ADBuilderConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string] $ConfigPath,
        [switch] $Strict,
        [switch] $PrintResolvedPlan,
        [switch] $UnsafeReducedValidation,
        [switch] $AllowReducedValidation,
        [switch] $LabUnsafe,
        [switch] $NonInteractive,
        [switch] $Force
    )
    Initialize-ADBuilderLogging -RootPath $script:ADBuilderRoot
    Write-ADBuilderBanner
    $valid = $false
    $errors = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList
    $script:ADBuilderValidationWarnings = $warnings
    try {
        $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
        $jsonText = Get-Content -LiteralPath $resolvedConfigPath -Raw
        Invoke-ADBuilderCanonicalSchemaValidation -ConfigPath $resolvedConfigPath -JsonText $jsonText -UnsafeReducedValidation:$UnsafeReducedValidation -AllowReducedValidation:$AllowReducedValidation
        $config = Import-ADBuilderConfig -ConfigPath $resolvedConfigPath -JsonText $jsonText
        Invoke-ADBuilderSemanticValidation -Config $config -LabUnsafe:$LabUnsafe -NonInteractive:$NonInteractive -Force:$Force
        $enabled = Get-ADBuilderEnabledProviders -Config $config
        $order = Resolve-ADBuilderProviderOrder -Providers $script:ADBuilderProviders -EnabledProviderNames $enabled
        if ($PrintResolvedPlan) { Write-Host ("Resolved provider order: {0}" -f ($order -join ' -> ')) -ForegroundColor Cyan }
        $valid = $true
        Write-ADBuilderLog -Level Success -Message 'Configuration validation passed.'
    } catch {
        [void]$errors.Add($_.Exception.Message)
        Write-ADBuilderLog -Level Fatal -Message $_.Exception.Message
    } finally {
        $script:ADBuilderValidationWarnings = $null
        Stop-ADBuilderLogging
    }
    return [pscustomobject]@{ Valid = $valid; Errors = @($errors); Warnings = @($warnings) }
}

function Invoke-ADBuilderSemanticValidation {
    [CmdletBinding()]
    param($Config,[switch]$LabUnsafe,[switch]$NonInteractive,[switch]$Force)
    if ($null -eq $Config.metadata) { throw 'metadata is required.' }
    Assert-ADBuilderRequiredString -Object $Config.metadata -Property 'configVersion' -Path 'metadata'
    Assert-ADBuilderRequiredString -Object $Config -Property 'mode' -Path '$'
    if (@('newForest','additionalDC','childDomain') -notcontains [string]$Config.mode) { throw "Unsupported mode: $($Config.mode)" }
    switch ([string]$Config.mode) {
        'newForest' { if ($null -eq $Config.forest) { throw 'forest block is required when mode=newForest.' }; Assert-ADBuilderRequiredString $Config.forest 'domainName' 'forest'; Assert-ADBuilderRequiredString $Config.forest 'netbiosName' 'forest' }
        'additionalDC' { if ($null -eq $Config.additionalDC) { throw 'additionalDC block is required when mode=additionalDC.' }; Assert-ADBuilderRequiredString $Config.additionalDC 'domainName' 'additionalDC'; if ($null -eq $Config.additionalDC.credential) { throw 'additionalDC.credential is required.' } }
        'childDomain' { if ($null -eq $Config.childDomain) { throw 'childDomain block is required when mode=childDomain.' }; Assert-ADBuilderRequiredString $Config.childDomain 'parentDomainName' 'childDomain'; Assert-ADBuilderRequiredString $Config.childDomain 'newDomainName' 'childDomain'; Assert-ADBuilderRequiredString $Config.childDomain 'newDomainNetbiosName' 'childDomain'; if ($null -eq $Config.childDomain.credential) { throw 'childDomain.credential is required.' } }
    }
    $hasForest       = (Test-ADBuilderHasProperty $Config 'forest')       -and ($null -ne $Config.forest)
    $hasAdditionalDC = (Test-ADBuilderHasProperty $Config 'additionalDC') -and ($null -ne $Config.additionalDC)
    $hasChildDomain  = (Test-ADBuilderHasProperty $Config 'childDomain')  -and ($null -ne $Config.childDomain)
    if ([string]$Config.mode -eq 'newForest'    -and ($hasAdditionalDC -or $hasChildDomain))  { throw 'mode=newForest allows only the forest block; remove additionalDC/childDomain blocks.' }
    if ([string]$Config.mode -eq 'additionalDC' -and ($hasForest -or $hasChildDomain))        { throw 'mode=additionalDC allows only the additionalDC block; remove forest/childDomain blocks.' }
    if ([string]$Config.mode -eq 'childDomain'  -and ($hasForest -or $hasAdditionalDC))      { throw 'mode=childDomain allows only the childDomain block; remove forest/additionalDC blocks.' }

    if ($Config.providers) {
        foreach ($rp in @('dns','gpo','kerberos','adcs')) {
            if (Test-ADBuilderHasProperty $Config.providers $rp) { $val = $Config.providers.$rp; if ($val -and $val.enabled -ne $false) { throw "Provider '$rp' is reserved beyond M1 and must be omitted or set enabled=false." } }
        }
    }
    $defaultMode = [string]$Config.execution.reconcile.global.default
    if ($defaultMode -eq 'exact' -and -not $Force) { throw 'Global reconcile mode exact requires -Force.' }
    foreach ($p in @($Config.execution.reconcile.perType.PSObject.Properties)) { if ($p.Value.mode -eq 'exact' -and -not $Force) { throw "Reconcile exact for '$($p.Name)' requires -Force." } }
    if ($Config.labVulnerabilities.enabled -eq $true -and -not $LabUnsafe) { throw 'labVulnerabilities.enabled=true requires -LabUnsafe.' }
    if ($Config.labVulnerabilities.enabled -eq $true) { throw 'labVulnerabilities intent compiler is reserved beyond M1. Use explicit provider-local labUnsafe ACLs only in M1.' }
    if ($NonInteractive) { Test-ADBuilderSecretsNonInteractive -Config $Config }
    Invoke-ADBuilderDirectorySemanticValidation -Config $Config -LabUnsafe:$LabUnsafe
}

function Test-ADBuilderSecretsNonInteractive {
    param($Config)
    $mode = [string]$Config.mode
    $dsrm = switch ($mode) { 'newForest' { $Config.forest.dsrmPassword } 'additionalDC' { $Config.additionalDC.dsrmPassword } 'childDomain' { $Config.childDomain.dsrmPassword } }
    if ($null -eq $dsrm -or ($dsrm -isnot [string] -and [string]$dsrm.source -eq 'prompt')) { throw 'DSRM password would prompt but -NonInteractive is set.' }
    if ($mode -in @('additionalDC','childDomain')) {
        $cred = if ($mode -eq 'additionalDC') { $Config.additionalDC.credential } else { $Config.childDomain.credential }
        if ($cred.password -isnot [string] -and [string]$cred.password.source -eq 'prompt') { throw "$mode credential password would prompt but -NonInteractive is set." }
    }
}

function Test-ADBuilderHasEffectiveValue {
    param($Value)
    if ($null -eq $Value) { return $false }
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        if ($item -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($item)) { return $true }
        } else {
            return $true
        }
    }
    return $false
}

function Get-ADBuilderAclEdgeName {
    param($Edge)
    if ($Edge -and (Test-ADBuilderHasProperty $Edge 'name') -and -not [string]::IsNullOrWhiteSpace([string]$Edge.name)) { return [string]$Edge.name }
    return '<unnamed>'
}

function Get-ADBuilderAclEdgeTarget {
    param($Edge)
    if ($Edge -and (Test-ADBuilderHasProperty $Edge 'target') -and -not [string]::IsNullOrWhiteSpace([string]$Edge.target)) { return [string]$Edge.target }
    if ($Edge -and (Test-ADBuilderHasProperty $Edge 'ou') -and -not [string]::IsNullOrWhiteSpace([string]$Edge.ou)) { return [string]$Edge.ou }
    return '<unknown target>'
}

function Assert-ADBuilderUnsupportedAclPrecisionFields {
    param($Edge,[string]$CollectionPath)
    $edgeName = Get-ADBuilderAclEdgeName -Edge $Edge
    $target = Get-ADBuilderAclEdgeTarget -Edge $Edge
    $rights = @($Edge.rights)
    $firstRight = if ($rights.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$rights[0])) { [string]$rights[0] } else { 'requested rights' }

    if ((Test-ADBuilderHasProperty $Edge 'objectType') -and (Test-ADBuilderHasEffectiveValue $Edge.objectType)) {
        throw "$CollectionPath.objectType is not implemented by this ADBuilder runtime; broad $firstRight would be created instead. Refusing silent broadening. Edge: '$edgeName', target: '$target'."
    }
    if ((Test-ADBuilderHasProperty $Edge 'inheritedObjectType') -and (Test-ADBuilderHasEffectiveValue $Edge.inheritedObjectType)) {
        throw "$CollectionPath.inheritedObjectType is not implemented by this ADBuilder runtime. Refusing to ignore requested inherited object type. Edge: '$edgeName', target: '$target'."
    }
    if ((Test-ADBuilderHasProperty $Edge 'inheritance') -and (Test-ADBuilderHasEffectiveValue $Edge.inheritance)) {
        $inheritance = [string]$Edge.inheritance
        if ($inheritance -ne 'None') {
            throw "$CollectionPath.inheritance is not implemented by this ADBuilder runtime. Refusing to ignore requested inheritance '$inheritance'. Edge: '$edgeName', target: '$target'."
        }
    }
    if ((Test-ADBuilderHasProperty $Edge 'accessType') -and (Test-ADBuilderHasEffectiveValue $Edge.accessType)) {
        $accessType = [string]$Edge.accessType
        if ($accessType -ne 'Allow') {
            throw "$CollectionPath.accessType is not implemented by this ADBuilder runtime. Refusing to ignore requested accessType '$accessType'. Edge: '$edgeName', target: '$target'."
        }
    }
    if ((Test-ADBuilderHasProperty $Edge 'appliesTo') -and (Test-ADBuilderHasEffectiveValue $Edge.appliesTo)) {
        throw "$CollectionPath.appliesTo is not implemented by this ADBuilder runtime. Refusing to ignore requested appliesTo. Edge: '$edgeName', target: '$target'."
    }
}

function Assert-ADBuilderDangerousAclRequiresLabUnsafe {
    param($Edge)
    $dangerousRights = @('GenericAll','GenericWrite','WriteDacl','WriteOwner','CreateChild','DeleteChild','ExtendedRight','WriteProperty')
    foreach ($right in @($Edge.rights)) {
        $rightName = [string]$right
        if ($dangerousRights -contains $rightName -and (Get-ADBuilderProperty $Edge 'labUnsafe' $false) -ne $true) {
            $edgeName = Get-ADBuilderAclEdgeName -Edge $Edge
            throw "Dangerous ACL edge '$edgeName' grants $rightName but labUnsafe=true is missing."
        }
    }
}

function Invoke-ADBuilderDirectorySemanticValidation {
    param($Config,[switch]$LabUnsafe)
    $d = $Config.providers.directory
    if ($null -eq $d -or $d.enabled -eq $false) { return }
    $names = @{}
    foreach ($kind in @('groups','users','computers')) {
        foreach ($obj in @($d.$kind)) {
            $id = if ($kind -eq 'users') { [string]$obj.samAccountName } elseif ($kind -eq 'computers') { [string]$obj.name } else { [string]$obj.name }
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $key = "$kind|$id".ToLowerInvariant()
            if ($names.ContainsKey($key)) { throw "Duplicate $kind identity in config: $id" }
            $names[$key] = $true
        }
    }
    $knownGroups = @{}; foreach ($g in @($d.groups)) { $knownGroups[[string]$g.name] = $g }
    $knownUsers = @{}; foreach ($u in @($d.users)) { $knownUsers[[string]$u.samAccountName] = $u }
    $knownComputers = @{}; foreach ($c in @($d.computers)) { $knownComputers[[string]$c.name] = $c; $knownComputers["$($c.name)$"] = $c }
    $builtIns = @('Domain Users','Domain Admins','Enterprise Admins','Administrators','Authenticated Users','Everyone','Domain Computers')
    foreach ($g in @($d.groups)) { foreach ($m in @($g.members)) { if (-not $knownUsers.ContainsKey($m) -and -not $knownGroups.ContainsKey($m) -and -not $knownComputers.ContainsKey($m) -and ($builtIns -notcontains $m)) { throw "Group '$($g.name)' references unknown member '$m'. Add it to users/groups/computers or use a known built-in principal." } } }
    foreach ($g in @($d.groups)) { foreach ($parent in @($g.memberOf)) { if (-not $knownGroups.ContainsKey($parent) -and ($builtIns -notcontains $parent)) { throw "Group '$($g.name)' references unknown parent group '$parent' in memberOf." } } }
    foreach ($u in @($d.users)) { foreach ($gname in @($u.groups)) { if (-not $knownGroups.ContainsKey($gname) -and ($builtIns -notcontains $gname)) { throw "User '$($u.samAccountName)' references unknown group '$gname'." } } }
    foreach ($u in @($d.users)) {
        $userId = if (-not [string]::IsNullOrWhiteSpace([string]$u.samAccountName)) { [string]$u.samAccountName } elseif (Test-ADBuilderHasProperty $u 'name') { [string]$u.name } else { '<unknown user>' }
        if ((Test-ADBuilderHasProperty $u 'spns') -and (Test-ADBuilderHasEffectiveValue $u.spns)) {
            throw "providers.directory.users[].spns is accepted by the schema but not implemented by this ADBuilder runtime. Affected user: '$userId'. Remove it or enable the future SPN provider."
        }
        if ((Test-ADBuilderHasProperty $u 'accountControlFlags') -and (Test-ADBuilderHasEffectiveValue $u.accountControlFlags)) {
            throw "providers.directory.users[].accountControlFlags is accepted by the schema but not implemented by this ADBuilder runtime. Affected user: '$userId'. Remove it or implement account-control support."
        }
    }
    Test-ADBuilderGroupCycles -Groups $d.groups
    $precedence = @{}
    foreach ($p in @($d.fineGrainedPasswordPolicies)) {
        $prec = [string]$p.precedence
        if ($precedence.ContainsKey($prec)) { throw "Duplicate FGPP precedence '$prec' in config." }
        $precedence[$prec] = $true
        foreach ($target in @($p.appliesTo)) {
            if ($knownUsers.ContainsKey($target)) { continue }
            if ($knownGroups.ContainsKey($target)) { $grp = $knownGroups[$target]; if ([string]$grp.scope -ne 'Global' -or [string]$grp.category -ne 'Security') { throw "FGPP '$($p.name)' appliesTo '$target', but FGPP can target only users or global security groups." }; continue }
            throw "FGPP '$($p.name)' appliesTo unknown target '$target'."
        }
    }
    foreach ($edge in @($d.delegations)) {
        if ($null -eq $edge) { continue }
        if ((Get-ADBuilderProperty $edge 'labUnsafe' $false) -eq $true -and -not $LabUnsafe) { throw "ACL/delegation '$(Get-ADBuilderAclEdgeName -Edge $edge)' has labUnsafe=true and requires -LabUnsafe." }
        foreach ($r in @($edge.rights)) { if (@('GenericAll','GenericRead','GenericWrite','WriteDacl','WriteOwner','CreateChild','DeleteChild','ReadProperty','WriteProperty','ExtendedRight','Delete','ListChildren') -notcontains [string]$r) { throw "Unsupported ACL right '$r' in M1. Use one of the documented simple ActiveDirectoryRights values." } }
        Assert-ADBuilderUnsupportedAclPrecisionFields -Edge $edge -CollectionPath 'providers.directory.delegations[]'
        Assert-ADBuilderDangerousAclRequiresLabUnsafe -Edge $edge
    }
    foreach ($edge in @($d.aclEdges)) {
        if ($null -eq $edge) { continue }
        if ((Get-ADBuilderProperty $edge 'labUnsafe' $false) -eq $true -and -not $LabUnsafe) { throw "ACL/delegation '$(Get-ADBuilderAclEdgeName -Edge $edge)' has labUnsafe=true and requires -LabUnsafe." }
        foreach ($r in @($edge.rights)) { if (@('GenericAll','GenericRead','GenericWrite','WriteDacl','WriteOwner','CreateChild','DeleteChild','ReadProperty','WriteProperty','ExtendedRight','Delete','ListChildren') -notcontains [string]$r) { throw "Unsupported ACL right '$r' in M1. Use one of the documented simple ActiveDirectoryRights values." } }
        Assert-ADBuilderUnsupportedAclPrecisionFields -Edge $edge -CollectionPath 'providers.directory.aclEdges[]'
        Assert-ADBuilderDangerousAclRequiresLabUnsafe -Edge $edge
    }
}

function Test-ADBuilderGroupCycles {
    param($Groups)
    $graph = @{}; $groupNames = @{}
    foreach ($g in @($Groups)) { $groupNames[[string]$g.name] = $true; $graph[[string]$g.name] = @() }
    foreach ($g in @($Groups)) {
        $groupName = [string]$g.name
        $children=@($graph[$groupName])
        foreach ($m in @($g.members)) { if ($groupNames.ContainsKey([string]$m)) { $children += [string]$m } }
        $graph[$groupName] = @($children | Select-Object -Unique)
        foreach ($parent in @($g.memberOf)) {
            $parentName = [string]$parent
            if ($groupNames.ContainsKey($parentName)) { $graph[$parentName] = @(@($graph[$parentName]) + $groupName | Select-Object -Unique) }
        }
    }
    $visiting=@{}; $visited=@{}
    function VisitGroup([string]$n) { if ($visiting.ContainsKey($n)) { throw "Circular group nesting detected at '$n'." }; if ($visited.ContainsKey($n)) { return }; $visiting[$n]=$true; foreach ($m in @($graph[$n])) { VisitGroup $m }; $visiting.Remove($n); $visited[$n]=$true }
    foreach ($name in $graph.Keys) { VisitGroup $name }
}
