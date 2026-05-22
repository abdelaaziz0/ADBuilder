Describe 'ADBuilder structure' {
    It 'has entry scripts and module files' {
        Test-Path .\Build-ADDomain.ps1 | Should -BeTrue
        Test-Path .\Validate-ADBuilderConfig.ps1 | Should -BeTrue
        Test-Path .\ADBuilder.psd1 | Should -BeTrue
        Test-Path .\ADBuilder.psm1 | Should -BeTrue
    }

    It 'has required core files' {
        foreach ($f in @(
            '.\lib\Core\Logging.ps1',
            '.\lib\Core\State.ps1',
            '.\lib\Core\DAG.ps1',
            '.\lib\Core\Validation.ps1',
            '.\lib\Core\ProviderContract.ps1',
            '.\lib\Core\Orchestrator.ps1'
        )) { Test-Path $f | Should -BeTrue }
    }
}

Describe 'ADBuilder module import' {
    It 'imports the module' {
        Import-Module .\ADBuilder.psd1 -Force
        Get-Command Invoke-ADBuilder | Should -Not -BeNullOrEmpty
        Get-Command Test-ADBuilderConfig | Should -Not -BeNullOrEmpty
    }

    It 'resolves provider order for M1 example with unsafe reduced validation' {
        Import-Module .\ADBuilder.psd1 -Force
        $r = Test-ADBuilderConfig -ConfigPath .\examples\reference.json -UnsafeReducedValidation -NonInteractive -PrintResolvedPlan
        $r.Valid | Should -BeTrue
    }
}

BeforeAll {
function New-ADBuilderTestConfig {
    return [pscustomobject]@{
        metadata = [pscustomobject]@{ configVersion = '0.1'; description = 'unit test config' }
        mode = 'newForest'
        execution = [pscustomobject]@{
            labMode = $true
            reconcile = [pscustomobject]@{
                global = [pscustomobject]@{ default = 'additive' }
                perType = [pscustomobject]@{}
            }
        }
        forest = [pscustomobject]@{
            domainName = 'test.lab'
            netbiosName = 'TEST'
            installDns = $true
            dsrmPassword = [pscustomobject]@{ source = 'env'; name = 'ADBUILDER_DSRM_PASSWORD' }
        }
        providers = [pscustomobject]@{
            directory = [pscustomobject]@{
                enabled = $true
                sites = @()
                siteLinks = @()
                ous = @()
                groups = @()
                users = @()
                computers = @()
                fineGrainedPasswordPolicies = @()
                delegations = @()
                aclEdges = @()
            }
        }
        assertions = @()
        labVulnerabilities = [pscustomobject]@{ enabled = $false; items = @() }
    }
}

function Write-ADBuilderTestConfig {
    param($Config,[string]$Name)
    $path = Join-Path $TestDrive $Name
    $Config | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}
}

Describe 'ADBuilder Phase 1 memberships' {
    It 'adds a group to its parent from group.memberOf' {
        Import-Module .\ADBuilder.psd1 -Force
        InModuleScope ADBuilder {
            $d = [pscustomobject]@{
                groups = @(
                    [pscustomobject]@{ name = 'GroupA'; members = @(); memberOf = @('GroupB') },
                    [pscustomobject]@{ name = 'GroupB'; members = @(); memberOf = @() }
                )
                users = @()
                computers = @()
            }
            $m = Get-ADBuilderDesiredMemberships -DirectoryConfig $d
            @($m['GroupB']) | Should -Contain 'GroupA'
        }
    }

    It 'supports two-level group.memberOf nesting' {
        Import-Module .\ADBuilder.psd1 -Force
        InModuleScope ADBuilder {
            $d = [pscustomobject]@{
                groups = @(
                    [pscustomobject]@{ name = 'GroupA'; members = @(); memberOf = @('GroupB') },
                    [pscustomobject]@{ name = 'GroupB'; members = @(); memberOf = @('GroupC') },
                    [pscustomobject]@{ name = 'GroupC'; members = @(); memberOf = @() }
                )
                users = @()
                computers = @()
            }
            $m = Get-ADBuilderDesiredMemberships -DirectoryConfig $d
            @($m['GroupB']) | Should -Contain 'GroupA'
            @($m['GroupC']) | Should -Contain 'GroupB'
        }
    }

    It 'deduplicates group.members and group.memberOf overlap' {
        Import-Module .\ADBuilder.psd1 -Force
        InModuleScope ADBuilder {
            $d = [pscustomobject]@{
                groups = @(
                    [pscustomobject]@{ name = 'GroupA'; members = @(); memberOf = @('GroupB') },
                    [pscustomobject]@{ name = 'GroupB'; members = @('GroupA'); memberOf = @() }
                )
                users = @()
                computers = @()
            }
            $m = Get-ADBuilderDesiredMemberships -DirectoryConfig $d
            @($m['GroupB'] | Where-Object { $_ -eq 'GroupA' }).Count | Should -Be 1
        }
    }

    It 'preserves user.groups membership behavior' {
        Import-Module .\ADBuilder.psd1 -Force
        InModuleScope ADBuilder {
            $d = [pscustomobject]@{
                groups = @([pscustomobject]@{ name = 'GroupA'; members = @(); memberOf = @() })
                users = @([pscustomobject]@{ samAccountName = 'alice'; groups = @('GroupA') })
                computers = @()
            }
            $m = Get-ADBuilderDesiredMemberships -DirectoryConfig $d
            @($m['GroupA']) | Should -Contain 'alice'
        }
    }
}

Describe 'ADBuilder Phase 1 semantic validation' {
    It 'allows empty spns and accountControlFlags arrays' {
        Import-Module .\ADBuilder.psd1 -Force
        $config = New-ADBuilderTestConfig
        $config.providers.directory.users = @(
            [pscustomobject]@{ samAccountName = 'alice'; ou = 'OU=Users'; groups = @(); spns = @(); accountControlFlags = @() }
        )
        $r = Test-ADBuilderConfig -ConfigPath (Write-ADBuilderTestConfig $config 'empty-user-fields.json') -UnsafeReducedValidation -NonInteractive
        $r.Valid | Should -BeTrue
    }

    It 'rejects non-empty users[].spns with the affected user' {
        Import-Module .\ADBuilder.psd1 -Force
        $config = New-ADBuilderTestConfig
        $config.providers.directory.users = @(
            [pscustomobject]@{ samAccountName = 'alice'; ou = 'OU=Users'; groups = @(); spns = @('HTTP/foo'); accountControlFlags = @() }
        )
        $r = Test-ADBuilderConfig -ConfigPath (Write-ADBuilderTestConfig $config 'spns.json') -UnsafeReducedValidation -NonInteractive
        $r.Valid | Should -BeFalse
        ($r.Errors -join "`n") | Should -Match 'providers\.directory\.users\[\]\.spns'
        ($r.Errors -join "`n") | Should -Match 'alice'
    }

    It 'rejects non-empty users[].accountControlFlags with the affected user' {
        Import-Module .\ADBuilder.psd1 -Force
        $config = New-ADBuilderTestConfig
        $config.providers.directory.users = @(
            [pscustomobject]@{ samAccountName = 'alice'; ou = 'OU=Users'; groups = @(); spns = @(); accountControlFlags = @('DoNotRequirePreAuth') }
        )
        $r = Test-ADBuilderConfig -ConfigPath (Write-ADBuilderTestConfig $config 'uac-flags.json') -UnsafeReducedValidation -NonInteractive
        $r.Valid | Should -BeFalse
        ($r.Errors -join "`n") | Should -Match 'providers\.directory\.users\[\]\.accountControlFlags'
        ($r.Errors -join "`n") | Should -Match 'alice'
    }

    It 'rejects aclEdges[].objectType until ACL v2 exists' {
        Import-Module .\ADBuilder.psd1 -Force
        $config = New-ADBuilderTestConfig
        $config.providers.directory.aclEdges = @(
            [pscustomobject]@{ name = 'specific attr write'; trustee = 'TEST\alice'; target = 'OU=Targets,DC=test,DC=lab'; rights = @('WriteProperty'); objectType = 'msDS-SupersededManagedAccountLink'; labUnsafe = $true }
        )
        $r = Test-ADBuilderConfig -ConfigPath (Write-ADBuilderTestConfig $config 'acl-object-type.json') -UnsafeReducedValidation -NonInteractive -LabUnsafe
        $r.Valid | Should -BeFalse
        ($r.Errors -join "`n") | Should -Match 'providers\.directory\.aclEdges\[\]\.objectType'
        ($r.Errors -join "`n") | Should -Match 'specific attr write'
        ($r.Errors -join "`n") | Should -Match 'OU=Targets'
    }

    It 'rejects non-default aclEdges[].inheritance until ACL v2 exists' {
        Import-Module .\ADBuilder.psd1 -Force
        $config = New-ADBuilderTestConfig
        $config.providers.directory.aclEdges = @(
            [pscustomobject]@{ name = 'inherited read'; trustee = 'TEST\alice'; target = 'OU=Targets,DC=test,DC=lab'; rights = @('GenericRead'); inheritance = 'All' }
        )
        $r = Test-ADBuilderConfig -ConfigPath (Write-ADBuilderTestConfig $config 'acl-inheritance.json') -UnsafeReducedValidation -NonInteractive
        $r.Valid | Should -BeFalse
        ($r.Errors -join "`n") | Should -Match 'providers\.directory\.aclEdges\[\]\.inheritance'
        ($r.Errors -join "`n") | Should -Match 'inherited read'
    }

    It 'requires labUnsafe=true for dangerous ACL rights' {
        Import-Module .\ADBuilder.psd1 -Force
        foreach ($right in @('GenericAll','WriteDacl','WriteProperty')) {
            $config = New-ADBuilderTestConfig
            $config.providers.directory.aclEdges = @(
                [pscustomobject]@{ name = "$right edge"; trustee = 'TEST\alice'; target = 'OU=Targets,DC=test,DC=lab'; rights = @($right) }
            )
            $r = Test-ADBuilderConfig -ConfigPath (Write-ADBuilderTestConfig $config "$right-missing-labUnsafe.json") -UnsafeReducedValidation -NonInteractive
            $r.Valid | Should -BeFalse
            ($r.Errors -join "`n") | Should -Match "Dangerous ACL edge '$right edge' grants $right but labUnsafe=true is missing."
        }
    }

    It 'does not require labUnsafe=true for supported non-dangerous ACL rights' {
        Import-Module .\ADBuilder.psd1 -Force
        $config = New-ADBuilderTestConfig
        $config.providers.directory.aclEdges = @(
            [pscustomobject]@{ name = 'read edge'; trustee = 'TEST\alice'; target = 'OU=Targets,DC=test,DC=lab'; rights = @('GenericRead') }
        )
        $r = Test-ADBuilderConfig -ConfigPath (Write-ADBuilderTestConfig $config 'safe-acl.json') -UnsafeReducedValidation -NonInteractive
        $r.Valid | Should -BeTrue
    }

    It 'keeps labUnsafe ACLs behind the CLI -LabUnsafe switch' {
        Import-Module .\ADBuilder.psd1 -Force
        $config = New-ADBuilderTestConfig
        $config.providers.directory.aclEdges = @(
            [pscustomobject]@{ name = 'explicit unsafe'; trustee = 'TEST\alice'; target = 'OU=Targets,DC=test,DC=lab'; rights = @('GenericAll'); labUnsafe = $true }
        )
        $path = Write-ADBuilderTestConfig $config 'explicit-unsafe.json'
        (Test-ADBuilderConfig -ConfigPath $path -UnsafeReducedValidation -NonInteractive).Valid | Should -BeFalse
        (Test-ADBuilderConfig -ConfigPath $path -UnsafeReducedValidation -NonInteractive -LabUnsafe).Valid | Should -BeTrue
    }
}

Describe 'ADBuilder Phase 1 assertions' {
    It 'reports all assertion failures and throws after running them' {
        Import-Module .\ADBuilder.psd1 -Force
        InModuleScope ADBuilder {
            $script:ADBuilderSummary = @{}
            function Get-ADUser { param($Identity) throw "Missing user $Identity" }
            function Get-ADGroup { param($Identity) throw "Missing group $Identity" }
            $ctx = [pscustomobject]@{
                DryRun = $false
                Config = [pscustomobject]@{
                    assertions = @(
                        [pscustomobject]@{ type = 'userExists'; identity = 'missing-user' },
                        [pscustomobject]@{ type = 'groupExists'; identity = 'missing-group' }
                    )
                }
            }
            { Invoke-ADBuilderAssertions -Context $ctx } | Should -Throw
            Get-ADBuilderAssertionFailureCount | Should -Be 2
        }
    }

    It 'does not checkpoint assertion phase state after assertion failure' {
        Import-Module .\ADBuilder.psd1 -Force
        InModuleScope ADBuilder {
            $script:ADBuilderSummary = @{}
            function Get-ADUser { param($Identity) throw "Missing user $Identity" }
            $statePath = Join-Path ([System.IO.Path]::GetTempPath()) ("adbuilder-state-{0}.json" -f ([guid]::NewGuid()))
            try {
                $state = New-ADBuilderStateObject -Mode 'newForest' -ConfigHash 'config' -CompiledConfigHash 'compiled' -ResolvedProviderOrder @('assertions') -LabUnsafe:$false
                $state.stage = 'B'
                Save-ADBuilderState -State $state -Path $statePath
                $ctx = [pscustomobject]@{
                    DryRun = $false
                    Config = [pscustomobject]@{ assertions = @([pscustomobject]@{ type = 'userExists'; identity = 'missing-user' }) }
                    State = $state
                    StatePath = $statePath
                }
                { Invoke-ADBuilderProvider -Provider (Get-ADBuilderAssertionsProvider) -Context $ctx } | Should -Throw
                $saved = Load-ADBuilderState -Path $statePath
                $saved.stage | Should -Be 'B'
                (Test-ADBuilderPhaseCompleted -State $saved -ProviderName 'assertions' -PhaseName 'RunAssertions') | Should -BeFalse
            } finally {
                if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
            }
        }
    }
}

Describe 'ADBuilder Phase 1 validation mode' {
    It 'fails when canonical NJsonSchema is missing and unsafe reduced validation was not requested' {
        Import-Module .\ADBuilder.psd1 -Force
        if (Test-Path .\third_party\NJsonSchema\NJsonSchema.dll) { return }
        $config = New-ADBuilderTestConfig
        $r = Test-ADBuilderConfig -ConfigPath (Write-ADBuilderTestConfig $config 'canonical-required.json') -NonInteractive
        $r.Valid | Should -BeFalse
        ($r.Errors -join "`n") | Should -Match 'Canonical NJsonSchema validator not found'
    }

    It 'warns loudly when unsafe reduced validation is used' {
        Import-Module .\ADBuilder.psd1 -Force
        if (Test-Path .\third_party\NJsonSchema\NJsonSchema.dll) { return }
        $config = New-ADBuilderTestConfig
        $r = Test-ADBuilderConfig -ConfigPath (Write-ADBuilderTestConfig $config 'unsafe-reduced.json') -UnsafeReducedValidation -NonInteractive
        $r.Valid | Should -BeTrue
        ($r.Warnings -join "`n") | Should -Match 'schema validation is reduced'
        ($r.Warnings -join "`n") | Should -Match 'not for production/CI'
    }
}
