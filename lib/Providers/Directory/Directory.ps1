function Get-ADBuilderDirectoryProvider {
    return [pscustomobject]@{
        Name = 'directory'
        Requires = @('domain.ready')
        Provides = @('directory.ousReady','directory.principalsReady','directory.aclsReady')
        Phases = @(
            @{ Name='Sites'; Function='Invoke-ADBuilderDirectorySites' },
            @{ Name='OUs'; Function='Invoke-ADBuilderDirectoryOUs' },
            @{ Name='Groups'; Function='Invoke-ADBuilderDirectoryGroups' },
            @{ Name='Users'; Function='Invoke-ADBuilderDirectoryUsers' },
            @{ Name='Computers'; Function='Invoke-ADBuilderDirectoryComputers' },
            @{ Name='Memberships'; Function='Invoke-ADBuilderDirectoryMemberships' },
            @{ Name='FGPP'; Function='Invoke-ADBuilderDirectoryFGPP' },
            @{ Name='ACLs'; Function='Invoke-ADBuilderDirectoryACLs' }
        )
    }
}

function Get-ADBuilderDirectoryConfig { param($Context) return $Context.Config.providers.directory }

function Convert-ADBuilderDNComponent {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $v = $Value -replace '\\','\5c' -replace ',','\,' -replace '\+','\+' -replace '"','\"' -replace '<','\<' -replace '>','\>' -replace ';','\;' -replace '=','\='
    if ($v.StartsWith(' ')) { $v='\'+$v }
    if ($v.EndsWith(' ')) { $v=$v.Substring(0,$v.Length-1)+'\ ' }
    if ($v.StartsWith('#')) { $v='\'+$v }
    return $v
}
function Convert-ADBuilderDnsNameToDN { param([string]$DnsName) return (($DnsName -split '\.') | ForEach-Object { 'DC=' + (Convert-ADBuilderDNComponent $_) }) -join ',' }
function Escape-ADBuilderLdapFilterValue { param([string]$Value) if ($null -eq $Value) { return '' }; return $Value.Replace('\','\5c').Replace('*','\2a').Replace('(','\28').Replace(')','\29').Replace([string][char]0,'\00') }

function Get-ADBuilderDomainDN {
    param($Context)
    if ($Context.DryRun) {
        switch ([string]$Context.Config.mode) {
            'newForest' { return Convert-ADBuilderDnsNameToDN ([string]$Context.Config.forest.domainName) }
            'additionalDC' { return Convert-ADBuilderDnsNameToDN ([string]$Context.Config.additionalDC.domainName) }
            'childDomain' { return Convert-ADBuilderDnsNameToDN ("$($Context.Config.childDomain.newDomainName).$($Context.Config.childDomain.parentDomainName)") }
        }
    }
    return (Get-ADDomain -ErrorAction Stop).DistinguishedName
}

function Resolve-ADBuilderDirectoryPath {
    param($Context,[string]$Path)
    $base = Get-ADBuilderDomainDN -Context $Context
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -eq '/') { return $base }
    if ($Path -match '(?i)(?:^|,)\s*DC=') { return $Path }
    return "$Path,$base"
}

function Get-ADBuilderTargetOUPath { param($Context,$Spec) return Resolve-ADBuilderDirectoryPath -Context $Context -Path ([string]$Spec.ou) }
function Test-ADBuilderSameContainer { param([string]$ObjectDN,[string]$ContainerDN) if ([string]::IsNullOrWhiteSpace($ObjectDN) -or [string]::IsNullOrWhiteSpace($ContainerDN)) { return $true }; return $ObjectDN.ToLowerInvariant().EndsWith((','+$ContainerDN).ToLowerInvariant()) }

function Get-ADBuilderADObjectOrNull {
    param([scriptblock]$ScriptBlock)
    try { return & $ScriptBlock } catch { return $null }
}

function Invoke-ADBuilderDirectorySites {
    param($Context)
    $d = Get-ADBuilderDirectoryConfig -Context $Context
    if ($null -eq $d) { return }
    if (@($d.sites).Count -eq 0 -and @($d.siteLinks).Count -eq 0) { return }
    if ($Context.DryRun) {
        foreach ($s in @($d.sites)) { Write-ADBuilderLog -Level DryRun -Message "Would ensure AD site: $($s.name)"; Add-ADBuilderSummary -Bucket 'sites' -Action WouldCreate; foreach($sub in @($s.subnets)){ Write-ADBuilderLog -Level DryRun -Message "Would ensure subnet $sub -> $($s.name)"; Add-ADBuilderSummary -Bucket 'subnets' -Action WouldCreate } }
        foreach ($l in @($d.siteLinks)) { Write-ADBuilderLog -Level DryRun -Message "Would ensure AD site link: $($l.name)"; Add-ADBuilderSummary -Bucket 'siteLinks' -Action WouldCreate }
        return
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    foreach ($s in @($d.sites)) {
        try {
            $site = Get-ADBuilderADObjectOrNull { Get-ADReplicationSite -Identity $s.name -ErrorAction Stop }
            if ($null -eq $site) { New-ADReplicationSite -Name $s.name -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'sites' -Action Created; Write-ADBuilderLog -Level Success -Message "Created site: $($s.name)" }
            else { if ($s.description) { Set-ADReplicationSite -Identity $s.name -Description $s.description -ErrorAction Stop }; Add-ADBuilderSummary -Bucket 'sites' -Action Skipped }
            foreach ($subnet in @($s.subnets)) {
                $existing = Get-ADBuilderADObjectOrNull { Get-ADReplicationSubnet -Identity $subnet -ErrorAction Stop }
                if ($null -eq $existing) { New-ADReplicationSubnet -Name $subnet -Site $s.name -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'subnets' -Action Created }
                else { Set-ADReplicationSubnet -Identity $subnet -Site $s.name -ErrorAction Stop; Add-ADBuilderSummary -Bucket 'subnets' -Action Updated }
            }
        } catch { Write-ADBuilderLog -Level Error -Message "Site phase failed for '$($s.name)': $($_.Exception.Message)"; Add-ADBuilderSummary -Bucket 'sites' -Action Failed }
    }
    foreach ($l in @($d.siteLinks)) {
        try {
            $existing = Get-ADBuilderADObjectOrNull { Get-ADReplicationSiteLink -Identity $l.name -ErrorAction Stop }
            if ($null -eq $existing) { New-ADReplicationSiteLink -Name $l.name -SitesIncluded $l.sites -Cost $l.cost -ReplicationFrequencyInMinutes $l.replicationFrequency -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'siteLinks' -Action Created }
            else { if($l.cost){ Set-ADReplicationSiteLink -Identity $l.name -Cost $l.cost -ErrorAction Stop }; if($l.replicationFrequency){ Set-ADReplicationSiteLink -Identity $l.name -ReplicationFrequencyInMinutes $l.replicationFrequency -ErrorAction Stop }; Add-ADBuilderSummary -Bucket 'siteLinks' -Action Updated }
        } catch { Write-ADBuilderLog -Level Error -Message "SiteLink phase failed for '$($l.name)': $($_.Exception.Message)"; Add-ADBuilderSummary -Bucket 'siteLinks' -Action Failed }
    }
}

function Invoke-ADBuilderDirectoryOUs {
    param($Context)
    $d = Get-ADBuilderDirectoryConfig -Context $Context
    if ($null -eq $d -or @($d.ous).Count -eq 0) { return }
    $policy = Get-ADBuilderReconcilePolicy -Config $Context.Config -TypeName 'ous'
    foreach ($ou in @($d.ous)) { Invoke-ADBuilderEnsureOURecursive -Context $Context -OU $ou -ParentPath $null -Policy $policy }
}

function Invoke-ADBuilderEnsureOURecursive {
    param($Context,$OU,[string]$ParentPath,$Policy)
    $parent = if ($OU.path) { Resolve-ADBuilderDirectoryPath -Context $Context -Path ([string]$OU.path) } elseif ($ParentPath) { $ParentPath } else { Get-ADBuilderDomainDN -Context $Context }
    $name = [string]$OU.name
    $dn = 'OU=' + (Convert-ADBuilderDNComponent $name) + ',' + $parent
    $existing = $null; $exists = $false
    if (-not $Context.DryRun) { $existing = Get-ADBuilderADObjectOrNull { Get-ADOrganizationalUnit -Identity $dn -Properties ProtectedFromAccidentalDeletion,Description -ErrorAction Stop }; $exists = $null -ne $existing }
    Invoke-ADBuilderCreateOrUpdate -Bucket 'ous' -Identity $dn -Exists:$exists -Policy $Policy -DryRun:($Context.DryRun) -Create {
        $prot = $true; if ($OU.protectFromDeletion -ne $null) { $prot = [bool]$OU.protectFromDeletion }
        $params = @{ Name=$name; Path=$parent; ProtectedFromAccidentalDeletion=$prot; ErrorAction='Stop' }
        if ($OU.description) { $params.Description = [string]$OU.description }
        New-ADOrganizationalUnit @params | Out-Null
    } -Update {
        $params = @{ Identity=$dn; ErrorAction='Stop' }
        if ($OU.description -ne $null) { $params.Description = [string]$OU.description }
        if ($OU.protectFromDeletion -ne $null) { $params.ProtectedFromAccidentalDeletion = [bool]$OU.protectFromDeletion }
        if ($params.Keys.Count -gt 2) { Set-ADOrganizationalUnit @params }
    }
    foreach ($child in @($OU.children)) { Invoke-ADBuilderEnsureOURecursive -Context $Context -OU $child -ParentPath $dn -Policy $Policy }
}

function Invoke-ADBuilderDirectoryGroups {
    param($Context)
    $d = Get-ADBuilderDirectoryConfig -Context $Context
    if ($null -eq $d -or @($d.groups).Count -eq 0) { return }
    $policy = Get-ADBuilderReconcilePolicy -Config $Context.Config -TypeName 'groups'
    foreach ($g in @($d.groups)) {
        $name = [string]$g.name; $path = Get-ADBuilderTargetOUPath -Context $Context -Spec $g
        $existing = $null; $exists = $false
        if (-not $Context.DryRun) { $existing = Get-ADBuilderADObjectOrNull { Get-ADGroup -Identity $name -Properties DistinguishedName,Description -ErrorAction Stop }; $exists = $null -ne $existing }
        Invoke-ADBuilderCreateOrUpdate -Bucket 'groups' -Identity $name -Exists:$exists -Policy $policy -DryRun:($Context.DryRun) -Create {
            $params = @{ Name=$name; SamAccountName=$name; GroupScope=$g.scope; GroupCategory=$g.category; Path=$path; ErrorAction='Stop' }
            if ($g.description) { $params.Description = [string]$g.description }
            New-ADGroup @params | Out-Null
        } -Update {
            if ($existing -and -not (Test-ADBuilderSameContainer -ObjectDN $existing.DistinguishedName -ContainerDN $path)) { if (Test-ADBuilderMayMove $policy) { Move-ADObject -Identity $existing.DistinguishedName -TargetPath $path -ErrorAction Stop } else { throw "Group exists outside desired OU and allowMove=false: $($existing.DistinguishedName)" } }
            if ($g.description -ne $null) { Set-ADGroup -Identity $name -Description ([string]$g.description) -ErrorAction Stop }
        }
    }
}

function Invoke-ADBuilderDirectoryUsers {
    param($Context)
    $d = Get-ADBuilderDirectoryConfig -Context $Context
    if ($null -eq $d -or @($d.users).Count -eq 0) { return }
    $policy = Get-ADBuilderReconcilePolicy -Config $Context.Config -TypeName 'users'
    foreach ($u in @($d.users)) {
        $sam = [string]$u.samAccountName; $path = Get-ADBuilderTargetOUPath -Context $Context -Spec $u
        $existing = $null; $exists = $false
        if (-not $Context.DryRun) { $existing = Get-ADBuilderADObjectOrNull { Get-ADUser -Identity $sam -Properties DistinguishedName,Enabled,Title,Department -ErrorAction Stop }; $exists = $null -ne $existing }
        Invoke-ADBuilderCreateOrUpdate -Bucket 'users' -Identity $sam -Exists:$exists -Policy $policy -DryRun:($Context.DryRun) -Create {
            $pwd = $null
            if ($u.password) { $pwd = Resolve-ADBuilderSecret -SecretSpec $u.password -FieldPath "providers.directory.users[$sam].password" -NonInteractive:([bool]$Context.NonInteractive) }
            elseif ($u.enabled -eq $true) { $pwd = Resolve-ADBuilderSecret -SecretSpec ([pscustomobject]@{source='env';name='ADBUILDER_DEFAULT_USER_PASSWORD'}) -FieldPath "providers.directory.users[$sam].password" -NonInteractive:([bool]$Context.NonInteractive) }
            $enabled = [bool]$u.enabled
            $userName = if ($u.displayName) { [string]$u.displayName } else { $sam }
            $params = @{ SamAccountName=$sam; Name=$userName; Path=$path; Enabled=$enabled; ErrorAction='Stop' }
            if ($u.givenName) { $params.GivenName = [string]$u.givenName }
            if ($u.surname) { $params.Surname = [string]$u.surname }
            if ($u.displayName) { $params.DisplayName = [string]$u.displayName }
            if ($u.userPrincipalName) { $params.UserPrincipalName = [string]$u.userPrincipalName }
            if ($pwd) { $params.AccountPassword = $pwd }
            New-ADUser @params | Out-Null
            Invoke-ADBuilderSetUserAttributes -Identity $sam -UserSpec $u
        } -Update {
            if ($existing -and -not (Test-ADBuilderSameContainer -ObjectDN $existing.DistinguishedName -ContainerDN $path)) { if (Test-ADBuilderMayMove $policy) { Move-ADObject -Identity $existing.DistinguishedName -TargetPath $path -ErrorAction Stop } else { throw "User exists outside desired OU and allowMove=false: $($existing.DistinguishedName)" } }
            Invoke-ADBuilderSetUserAttributes -Identity $sam -UserSpec $u
            if ((Test-ADBuilderMayResetPassword $policy) -and $u.password) { $pwd = Resolve-ADBuilderSecret -SecretSpec $u.password -FieldPath "providers.directory.users[$sam].password" -NonInteractive:([bool]$Context.NonInteractive); Set-ADAccountPassword -Identity $sam -Reset -NewPassword $pwd -ErrorAction Stop }
        }
    }
}

function Invoke-ADBuilderSetUserAttributes { param([string]$Identity,$UserSpec)
    $replace = @{}
    if ((Test-ADBuilderHasProperty $UserSpec 'title') -and $UserSpec.title -ne $null) { $replace['title'] = [string]$UserSpec.title }
    if ((Test-ADBuilderHasProperty $UserSpec 'department') -and $UserSpec.department -ne $null) { $replace['department'] = [string]$UserSpec.department }
    if ($replace.Keys.Count -gt 0) { Set-ADUser -Identity $Identity -Replace $replace -ErrorAction Stop }
    if ((Test-ADBuilderHasProperty $UserSpec 'enabled') -and $UserSpec.enabled -ne $null) { if ([bool]$UserSpec.enabled) { Enable-ADAccount -Identity $Identity -ErrorAction Stop } else { Disable-ADAccount -Identity $Identity -ErrorAction Stop } }
    if ((Test-ADBuilderHasProperty $UserSpec 'passwordNeverExpires') -and $UserSpec.passwordNeverExpires -ne $null) { Set-ADUser -Identity $Identity -PasswordNeverExpires:([bool]$UserSpec.passwordNeverExpires) -ErrorAction Stop }
    if ((Test-ADBuilderHasProperty $UserSpec 'changePasswordAtLogon') -and $UserSpec.changePasswordAtLogon -ne $null) { Set-ADUser -Identity $Identity -ChangePasswordAtLogon:([bool]$UserSpec.changePasswordAtLogon) -ErrorAction Stop }
}

function Invoke-ADBuilderDirectoryComputers {
    param($Context)
    $d = Get-ADBuilderDirectoryConfig -Context $Context
    if ($null -eq $d -or @($d.computers).Count -eq 0) { return }
    $policy = Get-ADBuilderReconcilePolicy -Config $Context.Config -TypeName 'computers'
    foreach ($c in @($d.computers)) {
        $name = [string]$c.name; $path = Get-ADBuilderTargetOUPath -Context $Context -Spec $c
        $existing = $null; $exists = $false
        if (-not $Context.DryRun) { $existing = Get-ADBuilderADObjectOrNull { Get-ADComputer -Identity $name -Properties DistinguishedName,Description -ErrorAction Stop }; $exists = $null -ne $existing }
        Invoke-ADBuilderCreateOrUpdate -Bucket 'computers' -Identity $name -Exists:$exists -Policy $policy -DryRun:($Context.DryRun) -Create {
            $enabled = [bool]$c.enabled
            $params = @{ Name=$name; SamAccountName="$name$"; Path=$path; Enabled=$enabled; ErrorAction='Stop' }
            if ($c.description) { $params.Description = [string]$c.description }
            New-ADComputer @params | Out-Null
        } -Update {
            if ($existing -and -not (Test-ADBuilderSameContainer -ObjectDN $existing.DistinguishedName -ContainerDN $path)) { if (Test-ADBuilderMayMove $policy) { Move-ADObject -Identity $existing.DistinguishedName -TargetPath $path -ErrorAction Stop } else { throw "Computer exists outside desired OU and allowMove=false: $($existing.DistinguishedName)" } }
            if ($c.description -ne $null) { Set-ADComputer -Identity $name -Description ([string]$c.description) -ErrorAction Stop }
            if ($c.enabled -ne $null) { if ([bool]$c.enabled) { Enable-ADAccount -Identity $name -ErrorAction Stop } else { Disable-ADAccount -Identity $name -ErrorAction Stop } }
        }
    }
}

function Get-ADBuilderPrincipalCanonicalMap {
    param($DirectoryConfig)
    $map = @{}
    foreach ($u in @($DirectoryConfig.users)) {
        if ($u -and $u.samAccountName) { $map[[string]$u.samAccountName] = [string]$u.samAccountName }
    }
    foreach ($g in @($DirectoryConfig.groups)) {
        if ($g -and $g.name) { $map[[string]$g.name] = [string]$g.name }
    }
    foreach ($c in @($DirectoryConfig.computers)) {
        if ($c -and $c.name) {
            $plain = [string]$c.name
            $sam = if ($plain.EndsWith('$')) { $plain } else { "$plain`$" }
            $map[$plain] = $sam
            $map[$sam] = $sam
        }
    }
    return $map
}

function ConvertTo-ADBuilderCanonicalMemberName {
    param([string]$Name,$CanonicalMap)
    if ($null -eq $Name) { return $Name }
    if ($CanonicalMap -and $CanonicalMap.ContainsKey($Name)) { return [string]$CanonicalMap[$Name] }
    return $Name
}

function Add-ADBuilderDesiredMembership {
    param($Membership,[string]$GroupName,[string]$MemberName)
    if ([string]::IsNullOrWhiteSpace($GroupName) -or [string]::IsNullOrWhiteSpace($MemberName)) { return }
    if (-not $Membership.ContainsKey($GroupName)) { $Membership[$GroupName] = New-Object System.Collections.ArrayList }
    if (-not $Membership[$GroupName].Contains($MemberName)) { [void]$Membership[$GroupName].Add($MemberName) }
}

function Get-ADBuilderDesiredMemberships { param($DirectoryConfig)
    $membership = @{}
    foreach ($g in @($DirectoryConfig.groups)) {
        $groupName = [string]$g.name
        if (-not [string]::IsNullOrWhiteSpace($groupName) -and -not $membership.ContainsKey($groupName)) { $membership[$groupName] = New-Object System.Collections.ArrayList }
        foreach ($m in @($g.members)) { Add-ADBuilderDesiredMembership -Membership $membership -GroupName $groupName -MemberName ([string]$m) }
        foreach ($parent in @($g.memberOf)) { Add-ADBuilderDesiredMembership -Membership $membership -GroupName ([string]$parent) -MemberName $groupName }
    }
    foreach ($u in @($DirectoryConfig.users)) {
        foreach ($gname in @($u.groups)) { Add-ADBuilderDesiredMembership -Membership $membership -GroupName ([string]$gname) -MemberName ([string]$u.samAccountName) }
    }
    return $membership
}

function Invoke-ADBuilderDirectoryMemberships {
    param($Context)
    $d = Get-ADBuilderDirectoryConfig -Context $Context
    if ($null -eq $d) { return }
    $policy = Get-ADBuilderReconcilePolicy -Config $Context.Config -TypeName 'memberships'
    $membership = Get-ADBuilderDesiredMemberships -DirectoryConfig $d
    $canonicalMap = Get-ADBuilderPrincipalCanonicalMap -DirectoryConfig $d
    foreach ($gname in $membership.Keys) {
        $desired = @($membership[$gname] | ForEach-Object { ConvertTo-ADBuilderCanonicalMemberName -Name ([string]$_) -CanonicalMap $canonicalMap } | Select-Object -Unique)
        if ($Context.DryRun) { Write-ADBuilderLog -Level DryRun -Message "Would reconcile membership for '$gname': $($desired -join ', ')"; Add-ADBuilderSummary -Bucket 'memberships' -Action WouldUpdate; continue }
        try {
            $current = @(Get-ADGroupMember -Identity $gname -Recursive:$false -ErrorAction Stop | ForEach-Object { if ($_.ObjectClass -eq 'computer') { "$($_.SamAccountName)" } elseif ($_.SamAccountName) { $_.SamAccountName } else { $_.Name } })
            foreach ($m in $desired) { if ($current -notcontains $m) { Add-ADGroupMember -Identity $gname -Members $m -ErrorAction Stop; Add-ADBuilderSummary -Bucket 'memberships' -Action Created; Write-ADBuilderLog -Level Success -Message "Added '$m' to '$gname'" } else { Add-ADBuilderSummary -Bucket 'memberships' -Action Skipped } }
            if (Test-ADBuilderMayDelete $policy) { foreach ($m in $current) { if ($desired -notcontains $m) { Remove-ADGroupMember -Identity $gname -Members $m -Confirm:$false -ErrorAction Stop; Add-ADBuilderSummary -Bucket 'memberships' -Action Updated; Write-ADBuilderLog -Level Success -Message "Removed unmanaged '$m' from '$gname' due exact reconcile" } } }
        } catch { Write-ADBuilderLog -Level Error -Message "Membership reconcile failed for '$gname': $($_.Exception.Message)"; Add-ADBuilderSummary -Bucket 'memberships' -Action Failed }
    }
}

function ConvertTo-ADBuilderTimeSpan {
    param($Value,[TimeSpan]$Default)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [TimeSpan]) { return $Value }
    return [TimeSpan]::Parse([string]$Value)
}

function Get-ADBuilderFGPPParams {
    param($Policy)
    return @{
        Precedence = [int]$Policy.precedence
        MinPasswordLength = [int](Get-ADBuilderProperty $Policy 'minPasswordLength' 12)
        PasswordHistoryCount = [int](Get-ADBuilderProperty $Policy 'passwordHistoryCount' 24)
        ComplexityEnabled = [bool](Get-ADBuilderProperty $Policy 'complexityEnabled' $true)
        ReversibleEncryptionEnabled = [bool](Get-ADBuilderProperty $Policy 'reversibleEncryptionEnabled' $false)
        LockoutThreshold = [int](Get-ADBuilderProperty $Policy 'lockoutThreshold' 0)
        LockoutDuration = (ConvertTo-ADBuilderTimeSpan (Get-ADBuilderProperty $Policy 'lockoutDuration' $null) ([TimeSpan]::FromMinutes(30)))
        LockoutObservationWindow = (ConvertTo-ADBuilderTimeSpan (Get-ADBuilderProperty $Policy 'lockoutObservationWindow' $null) ([TimeSpan]::FromMinutes(30)))
        MaxPasswordAge = (ConvertTo-ADBuilderTimeSpan (Get-ADBuilderProperty $Policy 'maxPasswordAge' $null) ([TimeSpan]::FromDays(42)))
        MinPasswordAge = (ConvertTo-ADBuilderTimeSpan (Get-ADBuilderProperty $Policy 'minPasswordAge' $null) ([TimeSpan]::FromDays(1)))
    }
}

function Invoke-ADBuilderDirectoryFGPP {
    param($Context)
    $d = Get-ADBuilderDirectoryConfig -Context $Context
    if ($null -eq $d -or @($d.fineGrainedPasswordPolicies).Count -eq 0) { return }
    $policy = Get-ADBuilderReconcilePolicy -Config $Context.Config -TypeName 'fineGrainedPasswordPolicies'
    foreach ($p in @($d.fineGrainedPasswordPolicies)) {
        $name = [string]$p.name
        if ($Context.DryRun) { Write-ADBuilderLog -Level DryRun -Message "Would ensure FGPP: $name"; Add-ADBuilderSummary -Bucket 'fgpp' -Action WouldCreate; continue }
        try {
            $existing = Get-ADBuilderADObjectOrNull { Get-ADFineGrainedPasswordPolicy -Identity $name -Properties AppliesTo -ErrorAction Stop }
            $fgppParams = Get-ADBuilderFGPPParams -Policy $p
            if ($null -eq $existing) {
                $params = @{ Name=$name; ErrorAction='Stop' }
                foreach ($k in $fgppParams.Keys) { $params[$k] = $fgppParams[$k] }
                New-ADFineGrainedPasswordPolicy @params | Out-Null
                Add-ADBuilderSummary -Bucket 'fgpp' -Action Created
            } elseif (Test-ADBuilderMayUpdate $policy) {
                $params = @{ Identity=$name; ErrorAction='Stop' }
                foreach ($k in $fgppParams.Keys) { $params[$k] = $fgppParams[$k] }
                Set-ADFineGrainedPasswordPolicy @params | Out-Null
                Add-ADBuilderSummary -Bucket 'fgpp' -Action Updated
            } else {
                Add-ADBuilderSummary -Bucket 'fgpp' -Action Skipped
            }
            $existingSubjects = Get-ADBuilderADObjectOrNull { Get-ADFineGrainedPasswordPolicySubject -Identity $name -ErrorAction Stop }
            $currentSubjectNames = @()
            foreach ($s in @($existingSubjects)) {
                if ($null -eq $s) { continue }
                if ($s.SamAccountName) { $currentSubjectNames += [string]$s.SamAccountName }
                if ($s.Name) { $currentSubjectNames += [string]$s.Name }
            }
            foreach ($target in @($p.appliesTo)) {
                if ($currentSubjectNames -contains [string]$target) {
                    Add-ADBuilderSummary -Bucket 'fgppSubjects' -Action Skipped
                    continue
                }
                Add-ADFineGrainedPasswordPolicySubject -Identity $name -Subjects $target -ErrorAction Stop
                Add-ADBuilderSummary -Bucket 'fgppSubjects' -Action Created
            }
        } catch { Write-ADBuilderLog -Level Error -Message "FGPP failed '$name': $($_.Exception.Message)"; Add-ADBuilderSummary -Bucket 'fgpp' -Action Failed }
    }
}

function Invoke-ADBuilderDirectoryACLs {
    param($Context)
    $d = Get-ADBuilderDirectoryConfig -Context $Context
    if ($null -eq $d) { return }
    $edges = @(); foreach ($x in @($d.delegations)) { $edges += $x }; foreach ($x in @($d.aclEdges)) { $edges += $x }
    foreach ($edge in $edges) {
        if ($null -eq $edge) { continue }
        $targetRaw = if ($edge.target) { [string]$edge.target } else { [string]$edge.ou }
        $target = Resolve-ADBuilderDirectoryPath -Context $Context -Path $targetRaw
        $trustee = [string]$edge.trustee
        if ($edge.labUnsafe -eq $true -and -not $Context.LabUnsafe) { throw "ACL '$($edge.name)' is labUnsafe but -LabUnsafe was not provided." }
        if ($Context.DryRun) { Write-ADBuilderLog -Level DryRun -Message "Would apply ACL rights '$($edge.rights -join ',')' for '$trustee' on '$target'"; Add-ADBuilderSummary -Bucket 'aclEdges' -Action WouldCreate; continue }
        try {
            $acl = Get-Acl -Path "AD:$target" -ErrorAction Stop
            $sid = (New-Object System.Security.Principal.NTAccount($trustee)).Translate([System.Security.Principal.SecurityIdentifier])
            foreach ($r in @($edge.rights)) {
                $right = [System.DirectoryServices.ActiveDirectoryRights]::$r
                $exists = $false
                foreach ($ace in $acl.Access) { if ($ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq $sid.Value -and (([int]$ace.ActiveDirectoryRights -band [int]$right) -eq [int]$right) -and $ace.AccessControlType -eq 'Allow') { $exists = $true; break } }
                if (-not $exists) { $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid,$right,'Allow'); $acl.AddAccessRule($rule) | Out-Null }
            }
            Set-Acl -Path "AD:$target" -AclObject $acl -ErrorAction Stop
            Add-ADBuilderSummary -Bucket 'aclEdges' -Action Updated
        } catch { Write-ADBuilderLog -Level Error -Message "ACL edge failed '$trustee' -> '$target': $($_.Exception.Message)"; Add-ADBuilderSummary -Bucket 'aclEdges' -Action Failed }
    }
}
