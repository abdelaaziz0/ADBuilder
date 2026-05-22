BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'ADBuilder.psd1') -Force

    function Write-TempConfig {
        param([string]$Json,[string]$Name)
        $path = Join-Path $TestDrive $Name
        Set-Content -LiteralPath $path -Value $Json -Encoding UTF8
        return $path
    }

    $script:MinimalForestJson = @'
{
  "metadata": { "configVersion": "0.1" },
  "mode": "newForest",
  "forest": {
    "domainName": "minimal.lab",
    "netbiosName": "MINIMAL",
    "dsrmPassword": { "source": "env", "name": "ADBUILDER_DSRM_PASSWORD" }
  }
}
'@
}

Describe 'Phase 4 - validation' {
    It 'accepts a minimal M1 newForest config with no optional fields' {
        $path = Write-TempConfig $script:MinimalForestJson 'minimal-forest.json'
        $r = Test-ADBuilderConfig -ConfigPath $path -UnsafeReducedValidation -NonInteractive
        $r.Valid | Should -BeTrue
    }

    It 'rejects mode=newForest with an additionalDC block using the exact mode-block message' {
        $json = @'
{
  "metadata": { "configVersion": "0.1" },
  "mode": "newForest",
  "forest": {
    "domainName": "minimal.lab",
    "netbiosName": "MINIMAL",
    "dsrmPassword": { "source": "env", "name": "ADBUILDER_DSRM_PASSWORD" }
  },
  "additionalDC": { "domainName": "extra.lab" }
}
'@
        $path = Write-TempConfig $json 'forest-plus-additionaldc.json'
        $r = Test-ADBuilderConfig -ConfigPath $path -UnsafeReducedValidation -NonInteractive
        $r.Valid | Should -BeFalse
        ($r.Errors -join "`n") | Should -Match 'mode=newForest allows only the forest block'
    }
}

Describe 'Phase 4 - DAG provider order' {
    It 'returns a single-element order when only one provider is enabled' {
        InModuleScope ADBuilder {
            $order = Resolve-ADBuilderProviderOrder -Providers $script:ADBuilderProviders -EnabledProviderNames @('directory')
            @($order) | Should -Be @('directory')
        }
    }

    It 'throws a cycle-detected error when providers form a dependency cycle' {
        InModuleScope ADBuilder {
            $providers = @{
                A = [pscustomobject]@{ Name = 'A'; Requires = @('capB'); Provides = @('capA') }
                B = [pscustomobject]@{ Name = 'B'; Requires = @('capA'); Provides = @('capB') }
            }
            { Resolve-ADBuilderProviderOrder -Providers $providers -EnabledProviderNames @('A','B') } |
                Should -Throw -ExpectedMessage '*cycle detected*'
        }
    }
}

Describe 'Phase 4 - Resolve-ADBuilderDirectoryPath' {
    It 'resolves the four directory-path contract cases' {
        InModuleScope ADBuilder {
            $ctx = [pscustomobject]@{
                DryRun = $true
                Config = [pscustomobject]@{ mode = 'newForest'; forest = [pscustomobject]@{ domainName = 'lab.local' } }
            }
            Resolve-ADBuilderDirectoryPath -Context $ctx -Path '/' | Should -Be 'DC=lab,DC=local'
            Resolve-ADBuilderDirectoryPath -Context $ctx -Path '' | Should -Be 'DC=lab,DC=local'
            Resolve-ADBuilderDirectoryPath -Context $ctx -Path 'OU=X,OU=Y' | Should -Be 'OU=X,OU=Y,DC=lab,DC=local'
            Resolve-ADBuilderDirectoryPath -Context $ctx -Path 'OU=X,DC=lab,DC=local' | Should -Be 'OU=X,DC=lab,DC=local'
        }
    }

    It 'treats a relative path whose RDN value contains literal DC= as relative' {
        InModuleScope ADBuilder {
            $ctx = [pscustomobject]@{
                DryRun = $true
                Config = [pscustomobject]@{ mode = 'newForest'; forest = [pscustomobject]@{ domainName = 'lab.local' } }
            }
            Resolve-ADBuilderDirectoryPath -Context $ctx -Path 'OU=lab DC=old,OU=Targets' |
                Should -Be 'OU=lab DC=old,OU=Targets,DC=lab,DC=local'
        }
    }
}

Describe 'Phase 4 - assertion normalization' {
    It 'adds a null identity to a userExists assertion that omits it without raising StrictMode' {
        InModuleScope ADBuilder {
            $cfg = [pscustomobject]@{
                metadata = [pscustomobject]@{ configVersion = '0.1' }
                mode = 'newForest'
                forest = [pscustomobject]@{
                    domainName = 'norm.lab'; netbiosName = 'NORM'
                    dsrmPassword = [pscustomobject]@{ source = 'env'; name = 'ADBUILDER_DSRM_PASSWORD' }
                }
                assertions = @([pscustomobject]@{ type = 'userExists' })
            }
            $norm = Normalize-ADBuilderConfig -Config $cfg
            $a = @($norm.assertions)[0]
            (Test-ADBuilderHasProperty $a 'identity') | Should -BeTrue
            { $null = $a.identity } | Should -Not -Throw
            $a.identity | Should -BeNullOrEmpty
        }
    }
}

Describe 'Phase 4 - principal canonical map' {
    It 'maps a computer name and its sam form to the sam form' {
        InModuleScope ADBuilder {
            $d = [pscustomobject]@{
                users = @(); groups = @()
                computers = @([pscustomobject]@{ name = 'WEB01' })
            }
            $map = Get-ADBuilderPrincipalCanonicalMap -DirectoryConfig $d
            $map['WEB01'] | Should -Be 'WEB01$'
            $map['WEB01$'] | Should -Be 'WEB01$'
        }
    }
}
