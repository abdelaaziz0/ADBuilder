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

    It 'resolves provider order for M1 example with reduced validation' {
        Import-Module .\ADBuilder.psd1 -Force
        $r = Test-ADBuilderConfig -ConfigPath .\examples\lab-newforest-m1.json -AllowReducedValidation -NonInteractive -PrintResolvedPlan
        $r.Valid | Should -BeTrue
    }
}
